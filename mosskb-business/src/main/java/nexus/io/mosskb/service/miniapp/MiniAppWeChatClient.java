package nexus.io.mosskb.service.miniapp;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

import com.alibaba.fastjson2.JSONObject;

import lombok.extern.slf4j.Slf4j;
import nexus.io.tio.utils.environment.EnvUtils;
import nexus.io.tio.utils.hutool.StrUtil;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * 微信小程序开放接口的访问封装：应用凭据只从配置读取，令牌在进程内缓存并提前刷新，
 * 避免每次生成小程序码都请求一次 access_token。
 */
@Slf4j
public class MiniAppWeChatClient {

  /** 小程序页面路径，扫码后由微信直接打开该页面。 */
  public static final String DEFAULT_PAGE = "pages/index/index";

  /** 小程序码的默认边长。 */
  public static final int DEFAULT_QR_WIDTH = 430;

  /** 微信开放接口的默认地址，可通过 wechat.miniapp.api-base 指向代理。 */
  private static final String DEFAULT_API_BASE = "https://api.weixin.qq.com";

  /** 微信令牌有效期 7200 秒，提前刷新可以避开边界时间。 */
  private static final long REFRESH_AHEAD_SECONDS = 300;

  private static final MediaType JSON = MediaType.get("application/json; charset=utf-8");

  private static final OkHttpClient HTTP_CLIENT = new OkHttpClient.Builder()
      //
      .connectTimeout(10, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).writeTimeout(30, TimeUnit.SECONDS)
      //
      .build();

  private static volatile String cachedAccessToken;
  private static volatile long cachedAccessTokenExpireAt;

  /** 是否配置了小程序凭据；未配置时只能走本地调试登录。 */
  public static boolean configured() {
    return StrUtil.isNotBlank(appId()) && StrUtil.isNotBlank(secret());
  }

  public static String appId() {
    return EnvUtils.get("wechat.miniapp.appid");
  }

  public static String secret() {
    return EnvUtils.get("wechat.miniapp.secret");
  }

  /** 默认小程序页面，可用 wechat.miniapp.page 覆盖。 */
  public static String defaultPage() {
    return EnvUtils.get("wechat.miniapp.page", DEFAULT_PAGE);
  }

  /**
   * 微信开放接口地址。默认直连微信，需要走代理或本地联调时用 wechat.miniapp.api-base 覆盖，
   * 末尾斜杠会被去掉，避免拼出双斜杠。
   */
  public static String apiBase() {
    String base = EnvUtils.get("wechat.miniapp.api-base", DEFAULT_API_BASE).trim();
    while (base.endsWith("/")) {
      base = base.substring(0, base.length() - 1);
    }
    return base;
  }

  /**
   * 小程序码的运行环境：release 正式版、trial 体验版、develop 开发版。
   * 本地开发默认 develop，这样未发布的页面也能扫码打开。
   */
  public static String defaultEnvVersion() {
    return EnvUtils.get("wechat.miniapp.env-version", EnvUtils.isDevMode() ? "develop" : "release");
  }

  /**
   * 用 wx.login 的 code 换 openid。
   *
   * @return openid，微信返回错误时抛出 {@link MiniAppWeChatException}
   */
  public JSONObject codeToSession(String code) {
    String url = apiBase() + "/sns/jscode2session?appid=" + appId() + "&secret=" + secret() + "&js_code=" + code
        + "&grant_type=authorization_code";
    JSONObject json = getJson(url);
    if (StrUtil.isBlank(json.getString("openid"))) {
      throw new MiniAppWeChatException(wxError(json));
    }
    return json;
  }

  /** 生成不限量小程序码，返回图片二进制。 */
  public byte[] unlimitedQrCode(String scene, String page, boolean checkPath, String envVersion, int width) {
    JSONObject body = new JSONObject();
    body.put("scene", scene);
    if (StrUtil.isNotBlank(page)) {
      body.put("page", page);
    }
    body.put("check_path", checkPath);
    body.put("env_version", envVersion);
    if (width > 0) {
      body.put("width", width);
    }
    Request request = new Request.Builder().url(apiBase() + "/wxa/getwxacodeunlimit?access_token=" + accessToken())
        //
        .post(RequestBody.create(body.toJSONString(), JSON)).build();
    try (Response response = HTTP_CLIENT.newCall(request).execute()) {
      ResponseBody responseBody = response.body();
      if (responseBody == null) {
        throw new MiniAppWeChatException("微信没有返回小程序码内容");
      }
      byte[] bytes = responseBody.bytes();
      // 出错时微信返回 JSON 而不是图片，解析出 errmsg 更利于排查
      if (isJsonPayload(bytes)) {
        throw new MiniAppWeChatException(wxError(JSONObject.parseObject(new String(bytes, StandardCharsets.UTF_8))));
      }
      if (!response.isSuccessful() || bytes.length == 0) {
        throw new MiniAppWeChatException("微信返回小程序码失败，HTTP " + response.code());
      }
      return bytes;
    } catch (IOException e) {
      log.error("request wechat qrcode failed", e);
      throw new MiniAppWeChatException("访问微信接口失败：" + e.getMessage());
    }
  }

  /** 进程内缓存的接口调用凭证。 */
  public String accessToken() {
    String token = cachedAccessToken;
    if (StrUtil.isNotBlank(token) && System.currentTimeMillis() < cachedAccessTokenExpireAt) {
      return token;
    }
    synchronized (MiniAppWeChatClient.class) {
      if (StrUtil.isNotBlank(cachedAccessToken) && System.currentTimeMillis() < cachedAccessTokenExpireAt) {
        return cachedAccessToken;
      }
      JSONObject json = getJson(apiBase() + "/cgi-bin/token?grant_type=client_credential&appid=" + appId() + "&secret=" + secret());
      String accessToken = json.getString("access_token");
      if (StrUtil.isBlank(accessToken)) {
        throw new MiniAppWeChatException(wxError(json));
      }
      Integer expiresIn = json.getInteger("expires_in");
      long ttlSeconds = Math.max(60, (expiresIn == null ? 7200 : expiresIn) - REFRESH_AHEAD_SECONDS);
      cachedAccessToken = accessToken;
      cachedAccessTokenExpireAt = System.currentTimeMillis() + ttlSeconds * 1000L;
      return accessToken;
    }
  }

  private JSONObject getJson(String url) {
    Request request = new Request.Builder().url(url).get().build();
    try (Response response = HTTP_CLIENT.newCall(request).execute()) {
      ResponseBody responseBody = response.body();
      if (responseBody == null) {
        throw new MiniAppWeChatException("微信没有返回内容，HTTP " + response.code());
      }
      String text = responseBody.string();
      if (!response.isSuccessful()) {
        throw new MiniAppWeChatException("访问微信接口失败，HTTP " + response.code());
      }
      JSONObject json = JSONObject.parseObject(text);
      if (json == null) {
        throw new MiniAppWeChatException("微信返回内容无法解析");
      }
      return json;
    } catch (IOException e) {
      log.error("request wechat api failed: {}", url, e);
      throw new MiniAppWeChatException("访问微信接口失败：" + e.getMessage());
    }
  }

  /** 微信错误码与描述拼成可读原因，日志里不输出应用凭据。 */
  private String wxError(JSONObject json) {
    Integer errcode = json.getInteger("errcode");
    String errmsg = json.getString("errmsg");
    if (errcode == null && StrUtil.isBlank(errmsg)) {
      return "微信接口返回未知错误";
    }
    return "微信接口错误：" + (errcode == null ? "" : errcode) + " " + (errmsg == null ? "" : errmsg);
  }

  private boolean isJsonPayload(byte[] bytes) {
    for (byte value : bytes) {
      if (value == ' ' || value == '\r' || value == '\n' || value == '\t') {
        continue;
      }
      return value == '{';
    }
    return false;
  }
}
