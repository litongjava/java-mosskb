package nexus.io.mosskb.service.miniapp;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;

/**
 * 小程序码 scene 的解析。scene 只承载应用公开访问令牌，扫到码的人拿到的正是分享链接本身，
 * 因此不需要在 scene 里再放应用标识。
 */
public class MiniAppSceneService {

  /** 一个 scene 对应的应用与访问令牌。 */
  public record SceneApplication(Long applicationId, Long accessToken, String applicationName, String language) {
  }

  private static final String FIND_BY_SCENE = """
      select t.application_id, t.access_token, t.language, a.name
      from moss_kb_application_access_token t
      join moss_kb_application a on a.id = t.application_id
      where t.access_token = ?
        and t.is_active = true
        and t.deleted = 0
        and a.deleted = 0
      """;

  /** scene 不存在、不是合法令牌、应用已删除或公开访问已停用时返回 null。 */
  public SceneApplication resolve(String scene) {
    Long accessToken = accessToken(scene);
    if (accessToken == null) {
      return null;
    }
    Row row = Db.findFirst(FIND_BY_SCENE, accessToken);
    if (row == null) {
      return null;
    }
    return new SceneApplication(row.getLong("application_id"), row.getLong("access_token"), row.getStr("name"),
        row.getStr("language"));
  }

  /**
   * scene 对应的是数字型公开访问令牌。这里先转成长整型再查询，
   * 既让数据库能用索引比较，也顺手挡掉明显的伪造 scene。
   */
  private Long accessToken(String scene) {
    if (scene == null) {
      return null;
    }
    String value = scene.trim();
    if (value.isEmpty() || value.length() > 19 || !value.chars().allMatch(Character::isDigit)) {
      return null;
    }
    try {
      return Long.valueOf(value);
    } catch (NumberFormatException e) {
      return null;
    }
  }

  /** 把应用当前有效的公开访问令牌作为 scene，供生成小程序码使用。 */
  public String sceneOf(Long applicationId) {
    return Db.queryStr("select access_token from moss_kb_application_access_token"
        + " where application_id = ? and deleted = 0 order by update_time desc limit 1", applicationId);
  }
}
