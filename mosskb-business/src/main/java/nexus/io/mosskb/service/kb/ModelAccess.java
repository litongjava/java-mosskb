package nexus.io.mosskb.service.kb;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;

public final class ModelAccess {
  private ModelAccess() { }
  public static boolean owns(Long user, Long id) {
    Row row = id == null ? null : Db.findById("moss_kb_model", id);
    return row != null && user != null && (user.equals(row.getLong("user_id")));
  }
  public static boolean canUse(Long user, Long id) {
    if (id == null) {
      return true;
    }
    Row row = Db.findById("moss_kb_model", id);
    return row != null && user != null && (user.equals(row.getLong("user_id")));
  }
}
