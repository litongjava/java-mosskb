package nexus.io.mosskb.service;

import java.util.Date;

import com.alibaba.fastjson2.JSONObject;

import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

/** Administrator-managed local accounts; never accept roles or ownership from request bodies. */
public class UserManagementService {

  /** User names are 6-20 characters from a restricted set so they stay safe in URLs and exports. */
  private static final String USERNAME_PATTERN = "[A-Za-z0-9_.@-]{6,20}";

  /** Advisory lock key that serializes account creation across JVM instances. */
  private static final long CREATE_LOCK_KEY = 7335647387278176L;

  private static final String COUNT_BY_USERNAME = """
      select count(*)
      from moss_kb_user
      where username = ?
      """;

  private static final String ACCOUNT_BY_ID = """
      select id, role
      from moss_kb_user
      where id = ?
        and deleted = 0
      """;

  private static final String BUMP_TOKEN_VERSION = """
      update moss_kb_user
      set token_version = token_version + 1
      where id = ?
      """;

  private static final String RESET_PASSWORD = """
      update moss_kb_user
      set password = ?,
          token_version = token_version + 1,
          update_time = now()
      where id = ?
        and deleted = 0
      """;

  private static final String LOGICAL_DELETE = """
      update moss_kb_user
      set deleted = 1,
          is_active = false,
          token_version = token_version + 1,
          update_time = now()
      where id <> 1
        and upper(role) <> 'SUPER_ADMIN'
        and id = ?
        and deleted = 0
      """;

  private static final String TAKE_CREATE_LOCK = """
      select pg_advisory_xact_lock(%d)
      """.formatted(CREATE_LOCK_KEY);

  public ResultVo create(JSONObject input) {
    Row actor = TeamAccess.account(TioRequestContext.getUserIdLong());
    if (!TeamAccess.administrator(actor) || input == null) {
      return ResultVo.fail("无权创建用户");
    }
    String role = TeamAccess.superAdmin(actor) ? "ADMIN" : "USER";
    Long id = SnowflakeIdUtils.id();
    Long team = TeamAccess.superAdmin(actor) ? id : TeamAccess.teamId(actor);
    String username = input.getString("username");
    String password = input.getString("password");
    if (username == null || !username.matches(USERNAME_PATTERN) || password == null || password.length() < 6
        || password.length() > 20) {
      return ResultVo.fail("用户名需为 6～20 位字母、数字或 _ . @ -，密码需为 6～20 位");
    }
    if (Db.queryLong(COUNT_BY_USERNAME, username) > 0) {
      return ResultVo.fail("用户名已存在");
    }
    Row user = Row.by("id", id).set("username", username).set("password", UserPassword.hash(password))
        .set("role", role).set("tenant_id", team).set("is_active", true).set("source", "LOCAL").set("deleted", 0);
    for (String field : new String[] {"email", "phone", "nick_name"}) {
      String value = input.getString(field);
      if (value != null && value.length() > 254) {
        return ResultVo.fail("用户资料过长");
      }
      user.set(field, value == null ? "" : value);
    }
    // Serialize account creation across JVM instances to prevent duplicate names without changing existing records.
    boolean[] duplicate = {false};
    Db.tx(() -> {
      Db.query(TAKE_CREATE_LOCK);
      if (Db.queryLong(COUNT_BY_USERNAME, username) > 0) {
        duplicate[0] = true;
      } else {
        Db.save("moss_kb_user", user);
      }
      return true;
    });
    if (duplicate[0]) {
      return ResultVo.fail("用户名已存在");
    }
    return ResultVo.ok(JSONObject.of("id", user.getLong("id").toString(), "username", username, "role", role, "tenant_id", team.toString(), "is_active", true));
  }

  public ResultVo update(Long id, JSONObject input) {
    if (!TeamAccess.canManage(id)) {
      return ResultVo.fail("无权管理该用户");
    }
    Row existing = Db.findFirst(ACCOUNT_BY_ID, id);
    if (existing == null) {
      return ResultVo.fail("用户不存在");
    }
    Row update = Row.by("id", id);
    for (String field : new String[] {"email", "phone", "nick_name"}) {
      if (input.containsKey(field)) {
        String value = input.getString(field);
        if (value == null || value.length() > 254) {
          return ResultVo.fail("用户资料无效");
        }
        update.set(field, value);
      }
    }
    boolean activeChanged = input.containsKey("is_active");
    if (activeChanged) {
      if (id == 1L || "SUPER_ADMIN".equalsIgnoreCase(existing.getStr("role"))) {
        return ResultVo.fail("不能禁用管理员");
      }
      update.set("is_active", input.getBooleanValue("is_active"));
    }
    update.set("update_time", new Date());
    Db.update("moss_kb_user", update);
    if (activeChanged) {
      Db.update(BUMP_TOKEN_VERSION, id);
    }
    return ResultVo.ok();
  }

  public ResultVo resetPassword(Long id, JSONObject input) {
    if (!TeamAccess.canManage(id)) {
      return ResultVo.fail("无权管理该用户");
    }
    String password = input.getString("password");
    if (password == null || password.length() < 6 || password.length() > 20 || !password.equals(input.getString("re_password"))) {
      return ResultVo.fail("密码需为 6～20 位，且两次输入一致");
    }
    int updated = Db.update(RESET_PASSWORD, UserPassword.hash(password), id);
    return updated == 1 ? ResultVo.ok() : ResultVo.fail("用户不存在");
  }

  public ResultVo delete(Long id) {
    if (!TeamAccess.canManage(id)) {
      return ResultVo.fail("无权管理该用户");
    }
    int updated = Db.update(LOGICAL_DELETE, id);
    return updated == 1 ? ResultVo.ok() : ResultVo.fail("用户不存在或不能删除管理员");
  }
}
