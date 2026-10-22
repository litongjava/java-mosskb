package nexus.io.mosskb.service;

import java.util.List;

import com.alibaba.fastjson2.JSONObject;
import com.jfinal.kit.Kv;

import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.db.TableInput;
import nexus.io.db.TableResult;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.kit.RowUtils;
import nexus.io.mosskb.vo.ResultPage;
import nexus.io.mosskb.vo.UserLoginReqVo;
import nexus.io.model.page.Page;
import nexus.io.model.result.ResultVo;
import nexus.io.table.services.ApiTable;
import nexus.io.tio.boot.admin.utils.TioAdminEnvUtils;
import nexus.io.tio.utils.crypto.Md5Utils;
import nexus.io.tio.utils.jwt.JwtUtils;
import nexus.io.tio.utils.token.TokenManager;

public class KbUserService {

  private static final String ACCOUNT_BY_USERNAME = """
      select id, password, token_version
      from moss_kb_user
      where username = ?
        and is_active = true
        and deleted = 0
      """;

  private static final String PROFILE_BY_ID = """
      select id, username, email, phone, nick_name, role, language, tenant_id
      from moss_kb_user
      where id = ?
      """;

  /** 与前端语言下拉一致：简体中文、繁体中文、英文。 */
  private static final List<String> SUPPORT_LANGUAGES = List.of("zh-CN", "zh-Hant", "en-US");

  /**
   * 切换界面语言：只改 language 与 update_time，不碰令牌与密码。
   * language 为空的老账号继续跟随浏览器语言，直到用户自己切换一次。
   */
  private static final String SWITCH_LANGUAGE = """
      update moss_kb_user
      set language = ?,
          update_time = now()
      where id = ?
        and deleted = 0
      """;

  private static final String PAGE_CONDITION = """
      where deleted = 0
        and (username ilike ? or email ilike ?)
        and (? = true or tenant_id = ?)
      """;

  private static final String COUNT_USERS = """
      select count(*)
      from moss_kb_user
      """ + PAGE_CONDITION;

  private static final String PAGE_USERS = """
      select id, tenant_id, username, email, phone, is_active, role, nick_name, create_time, update_time, source
      from moss_kb_user
      """ + PAGE_CONDITION + """
      order by create_time desc
      limit ? offset ?
      """;

  /**
   * 修改当前登录用户的密码。改密后递增 token_version，旧令牌在拦截器里立刻失效。
   */
  private static final String RESET_CURRENT_PASSWORD = """
      update moss_kb_user
      set password = ?,
          token_version = token_version + 1,
          update_time = now()
      where id = ?
        and deleted = 0
        and is_active = true
      """;

  public ResultVo login(UserLoginReqVo vo) {
    if (vo == null || vo.getUsername() == null || vo.getPassword() == null) {
      return ResultVo.fail("用户名或者密码不正确");
    }
    Row account = Db.findFirst(ACCOUNT_BY_USERNAME, vo.getUsername());
    if (account == null || !UserPassword.matches(vo.getPassword(), account.getStr("password"))) {
      return ResultVo.fail("用户名或者密码不正确");
    }
    Long userId = account.getLong("id");
    String SECRET_KEY = TioAdminEnvUtils.getAdminSecretKey();
    String token = JwtUtils.createToken(SECRET_KEY, java.util.Map.of("userId", userId, "exp", System.currentTimeMillis() / 1000 + 3600, "token_version", account.getLong("token_version")));
    TokenManager.login(userId, token);
    return ResultVo.ok("成功", token);
  }

  public ResultVo index(Long userId) {
    Row record = Db.findFirst(PROFILE_BY_ID, userId);
    Kv kv = record.toKv();
    List<String> permissions = Aop.get(PermissionsService.class).getPermissionsByRole(kv.getStr("role"), userId);
    kv.set("permissions", permissions);
    return ResultVo.ok(kv);
  }

  public ResultVo logout(Long userId) {
    TokenManager.logout(userId);
    return ResultVo.ok();
  }

  /**
   * 切换当前登录用户的界面语言。语言只决定界面与接口消息的语种，不属于权限，
   * 因此身份同样只认令牌，不接受请求体里的用户标识。
   *
   * @param userId 当前登录用户，取自令牌
   * @param input  请求体，只读取 language
   */
  public ResultVo switchLanguage(Long userId, JSONObject input) {
    if (userId == null) {
      return ResultVo.fail("未登录");
    }
    String language = input == null ? null : input.getString("language");
    // List.of(...).contains(null) 会抛 NPE，所以空值要先挡掉。
    if (language == null || !SUPPORT_LANGUAGES.contains(language)) {
      return ResultVo.fail("语言只支持：" + String.join(",", SUPPORT_LANGUAGES));
    }
    int updated = Db.update(SWITCH_LANGUAGE, language, userId);
    if (updated != 1) {
      return ResultVo.fail("用户不存在或已被禁用");
    }
    return ResultVo.ok();
  }

  /**
   * 修改当前登录用户的密码，不校验邮箱验证码：调用方已经在拦截器里通过登录令牌确定身份。
   *
   * @param userId 当前登录用户，取自令牌，绝不从请求体读取
   * @param input  请求体，只读取 password 与 re_password
   */
  public ResultVo resetCurrentPassword(Long userId, JSONObject input) {
    if (userId == null) {
      return ResultVo.fail("未登录");
    }
    String password = input == null ? null : input.getString("password");
    String rePassword = input == null ? null : input.getString("re_password");
    if (password == null || password.length() < 6 || password.length() > 20 || !password.equals(rePassword)) {
      return ResultVo.fail("密码需为 6～20 位，且两次输入一致");
    }
    int updated = Db.update(RESET_CURRENT_PASSWORD, UserPassword.hash(password), userId);
    if (updated != 1) {
      return ResultVo.fail("用户不存在或已被禁用");
    }
    // 令牌版本已经变化，这里再清掉当前会话，前端会跳回登录页重新登录。
    TokenManager.logout(userId);
    return ResultVo.ok();
  }

  public ResultVo page(Integer pageNo, Integer pageSize) {
    return page(pageNo, pageSize, null);
  }

  public ResultVo page(Integer pageNo, Integer pageSize, String search) {
    int currentPage = Math.max(1, pageNo == null ? 1 : pageNo);
    int currentSize = Math.max(1, Math.min(100, pageSize == null ? 20 : pageSize));
    String term = "%" + (search == null ? "" : search) + "%";
    Row actor = TeamAccess.account(TioRequestContext.getUserIdLong());
    if (!TeamAccess.administrator(actor)) {
      return ResultVo.fail("无权查看用户");
    }
    boolean allTeams = TeamAccess.superAdmin(actor);
    Long team = TeamAccess.teamId(actor);
    long total = Db.queryLong(COUNT_USERS, term, term, allTeams, team);
    List<Row> rows = Db.find(PAGE_USERS, term, term, allTeams, team, currentSize, (long) (currentPage - 1) * currentSize);
    return ResultVo.ok(new ResultPage<Kv>(currentPage, currentSize, (int) total, RowUtils.toKv(rows, false)));
  }
}
