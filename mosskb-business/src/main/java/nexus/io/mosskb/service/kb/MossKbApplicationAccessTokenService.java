package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.jfinal.kit.Kv;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.model.MossKbApplicationAccessToken;
import nexus.io.mosskb.model.MossKbApplicationPublicAccessClient;
import nexus.io.mosskb.service.MossKbAuthService;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.boot.admin.utils.TioAdminEnvUtils;
import nexus.io.tio.utils.hutool.StrUtil;
import nexus.io.tio.utils.jwt.JwtUtils;
import nexus.io.tio.utils.mcid.McIdUtils;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;
import nexus.io.tio.utils.token.TokenManager;

/**
 * 应用公开链接。一个应用一条记录，作为分享页 /ui/#/chat/{access_token} 的短令牌与显示开关。
 */
public class MossKbApplicationAccessTokenService {

  /** 界面支持的语言，与前端语言包目录同名；留空表示跟随访客浏览器语言。 */
  private static final List<String> SUPPORTED_LANGUAGES = List.of("en-US", "zh-CN", "zh-Hant");

  /** 白名单条目上限，避免把任意长度的文本写进数据库。 */
  private static final int WHITE_LIST_LIMIT = 32;

  /** 单次访问上限的上界，「不限次数」用 0 表示。 */
  private static final int ACCESS_NUM_MAX = 1_000_000;

  private static final String COLUMNS = "application_id,access_token,is_active,access_num,white_active,white_list,"
      + "show_source,language,create_time,update_time";

  private static final String FIND_BY_APPLICATION = """
      select %s
      from moss_kb_application_access_token
      where application_id = ?
        and deleted = 0
      """.formatted(COLUMNS);

  private static final String FIND_BY_TOKEN = """
      select %s
      from moss_kb_application_access_token
      where access_token = ?
        and deleted = 0
        and is_active = true
      """.formatted(COLUMNS);

  public ResultVo getById(Long applicationId) {
    Row record = Db.findFirst(FIND_BY_APPLICATION, applicationId);
    return ResultVo.ok(record == null ? Kv.create() : record.toKv());
  }

  /**
   * 公开链接的写入：只改请求里出现的字段，未出现的保持原值。
   */
  public ResultVo update(Long userId, Long applicationId, JSONObject input) {
    if (!ApplicationAccess.owns(userId, applicationId)) {
      return ResultVo.fail("应用不存在或无权访问");
    }
    if (Db.queryLong("select count(*) from moss_kb_application_access_token where application_id=? and deleted=0",
        applicationId) == 0) {
      return ResultVo.fail("公开访问链接不存在");
    }
    List<String> assignments = new ArrayList<>();
    List<Object> args = new ArrayList<>();
    if (input.containsKey("is_active")) {
      assignments.add("is_active = ?");
      args.add(Boolean.TRUE.equals(input.getBoolean("is_active")));
    }
    if (Boolean.TRUE.equals(input.getBoolean("access_token_reset"))) {
      assignments.add("access_token = ?");
      args.add(McIdUtils.id());
    }
    if (input.containsKey("show_source")) {
      assignments.add("show_source = ?");
      args.add(Boolean.TRUE.equals(input.getBoolean("show_source")));
    }
    if (input.containsKey("access_num")) {
      Integer accessNum = input.getInteger("access_num");
      if (accessNum != null && (accessNum < 0 || accessNum > ACCESS_NUM_MAX)) {
        return ResultVo.fail("访问次数允许 0 到 " + ACCESS_NUM_MAX + "，0 表示不限次数");
      }
      assignments.add("access_num = ?");
      args.add(accessNum == null ? 0 : accessNum);
    }
    if (input.containsKey("white_active")) {
      assignments.add("white_active = ?");
      args.add(Boolean.TRUE.equals(input.getBoolean("white_active")));
    }
    if (input.containsKey("white_list")) {
      assignments.add("white_list = ?");
      args.add((Object) whiteList(input.getJSONArray("white_list")));
    }
    if (input.containsKey("language")) {
      String language = input.getString("language");
      if (StrUtil.isNotBlank(language) && !SUPPORTED_LANGUAGES.contains(language)) {
        return ResultVo.fail("不支持的语言：" + language);
      }
      assignments.add("language = ?");
      args.add(StrUtil.isBlank(language) ? null : language);
    }
    if (assignments.isEmpty()) {
      return getById(applicationId);
    }
    assignments.add("update_time = now()");
    args.add(applicationId);
    Db.update("update moss_kb_application_access_token set " + String.join(", ", assignments)
        + " where application_id = ? and deleted = 0", args.toArray());
    return getById(applicationId);
  }

  /**
   * 分享链接的认证入口：短令牌换长期令牌，首次访问时登记访客。
   */
  public ResultVo authentication(Long shortToken, String longToken) {
    Row token = Db.findFirst(FIND_BY_TOKEN, shortToken);
    if (token == null) {
      return ResultVo.fail("not found applicaiton id:" + shortToken);
    }
    Long applicationId = token.getLong("application_id");
    Long clientId = Aop.get(MossKbAuthService.class).getIdByToken(longToken);
    if (clientId != null && Db.queryLong("select count(*) from moss_kb_application_public_access_client where application_id=? and client_id=?",
        applicationId, clientId) > 0) {
      return ResultVo.ok(longToken);
    }
    return ResultVo.ok(bindClient(applicationId, token.getStr("language")));
  }

  /**
   * 登记访客并签发长期令牌，返回长期令牌本身。
   */
  private String bindClient(Long applicationId, String language) {
    Long clientId = SnowflakeIdUtils.id();
    String SECRET_KEY = TioAdminEnvUtils.getAdminSecretKey();
    String longToken = JwtUtils.createTokenByUserId(SECRET_KEY, clientId);
    TokenManager.login(clientId, longToken);
    new MossKbApplicationPublicAccessClient().setId(SnowflakeIdUtils.id()).setClientId(clientId)
        .setApplicationId(applicationId)
        //
        .setAccessNum(0).setIntradayAccessNum(0)
        //
        .save();
    return longToken;
  }

  /** 白名单做去空、去首尾空白与条数限制。 */
  private String[] whiteList(JSONArray array) {
    List<String> values = new ArrayList<>();
    if (array != null) {
      for (int i = 0; i < array.size() && values.size() < WHITE_LIST_LIMIT; i++) {
        String value = array.getString(i);
        if (StrUtil.isNotBlank(value) && value.trim().length() <= 128) {
          values.add(value.trim());
        }
      }
    }
    return values.toArray(new String[0]);
  }

  /**
   * 新建应用时同步创建公开链接：默认启用、默认不显示来源、不限语言。
   */
  public void create(Long applicationId) {
    MossKbApplicationAccessToken token = new MossKbApplicationAccessToken().setApplicationId(applicationId)
        //
        .setAccessToken(McIdUtils.id()).setIsActive(true).setAccessNum(100).setWhiteActive(false)
        //
        .setWhiteList(new String[] {})
        //
        .setShowSource(true);
    token.save();
  }

  public void delete(Long applicationId) {
    MossKbApplicationAccessToken token = new MossKbApplicationAccessToken().setApplicationId(applicationId);
    token.delete();
  }
}
