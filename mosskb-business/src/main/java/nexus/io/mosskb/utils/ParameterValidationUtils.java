package nexus.io.mosskb.utils;

import com.alibaba.fastjson2.JSONObject;
import com.jfinal.kit.Kv;

import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.utils.hutool.StrUtil;
import nexus.io.tio.utils.json.FastJson2Utils;
import nexus.io.tio.utils.json.JsonUtils;
import nexus.io.tio.utils.validator.ParameterValidator;

/**
 * HTTP 入参校验的封装：把请求体、路径参数、查询参数统一交给 {@link ParameterValidator}，
 * 校验失败一律抛出 {@code ParameterValidationException}，由全局异常处理器转成 400 响应。
 */
public final class ParameterValidationUtils {

  /** 普通 JSON 请求体的默认上限，避免把任意长度的文本读进内存。 */
  public static final int DEFAULT_BODY_LIMIT = 16384;

  private ParameterValidationUtils() {
  }

  /**
   * 读取并校验请求体：空请求体、超过长度上限、不是 JSON 对象时都会抛出参数校验异常。
   *
   * @return 原始 JSON 文本，交给调用方按实体类解析
   */
  public static String requestBody(HttpRequest request, int maxLength) {
    String bodyString = request == null ? null : request.getBodyString();
    ParameterValidator.require(StrUtil.isNotBlank(bodyString), "请求体不能为空");
    ParameterValidator.require(bodyString.length() <= maxLength, "请求体过大");
    ParameterValidator.require(isJsonObject(bodyString), "请求体必须是 JSON 对象");
    return bodyString;
  }

  public static String requestBody(HttpRequest request) {
    return requestBody(request, DEFAULT_BODY_LIMIT);
  }

  /** 请求体解析成实体类，parse 结果为 null 时按参数错误处理。 */
  public static <T> T body(HttpRequest request, Class<T> type, int maxLength) {
    String bodyString = requestBody(request, maxLength);
    T input = JsonUtils.parse(bodyString, type);
    ParameterValidator.require(input != null, "请求体必须是 JSON 对象");
    return input;
  }

  public static <T> T body(HttpRequest request, Class<T> type) {
    return body(request, type, DEFAULT_BODY_LIMIT);
  }

  /** 请求体里字段不固定的场景，统一用 Kv 承载。 */
  public static Kv kvBody(HttpRequest request, int maxLength) {
    JSONObject json = FastJson2Utils.parseObject(requestBody(request, maxLength));
    return Kv.create().set(json);
  }

  /** 路径参数里的长整型标识：必须存在且是正整数。 */
  public static Long pathId(HttpRequest request, String name) {
    String raw = request == null ? null : request.getParam(name);
    ParameterValidator.require(StrUtil.isNotBlank(raw), name + " 不能为空");
    return ParameterValidator.id(raw.trim(), name);
  }

  /** 必填文本，并限制长度上限。 */
  public static String requiredText(Object raw, String name, int maxLength) {
    return ParameterValidator.text(raw, name, maxLength, true);
  }

  /** 选填文本，并限制长度上限。 */
  public static String optionalText(Object raw, String name, int maxLength) {
    return ParameterValidator.text(raw, name, maxLength, false);
  }

  public static void required(Object value, String message) {
    ParameterValidator.require(value != null, message);
  }

  private static boolean isJsonObject(String bodyString) {
    String trimmed = bodyString.trim();
    return trimmed.startsWith("{") && trimmed.endsWith("}");
  }
}
