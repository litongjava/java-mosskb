package nexus.io.mosskb.service;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.tio.boot.http.TioRequestContext;

/** Account identity is retained for account operations; resource ownership uses the team owner. */
public final class TeamAccess {
  private TeamAccess() {
  }

  public static Row account(Long id) {
    return id == null ? null : Db.findFirst("""
        select id, role, tenant_id from moss_kb_user
        where id = ? and deleted = 0 and is_active = true
        """, id);
  }

  public static boolean superAdmin(Row account) {
    return account != null && "SUPER_ADMIN".equalsIgnoreCase(account.getStr("role"));
  }

  public static boolean administrator(Row account) {
    return superAdmin(account) || account != null && "ADMIN".equalsIgnoreCase(account.getStr("role"));
  }

  public static Long teamId(Row account) {
    Long tenant = account.getLong("tenant_id");
    return tenant == null || tenant == 0 ? account.getLong("id") : tenant;
  }

  public static boolean canManage(Long target) {
    Row actor = account(TioRequestContext.getUserIdLong());
    Row user = target == null ? null : Db.findById("moss_kb_user", target);
    return administrator(actor) && user != null && (superAdmin(actor)
        || "USER".equalsIgnoreCase(user.getStr("role")) && teamId(actor).equals(teamId(user)));
  }
}
