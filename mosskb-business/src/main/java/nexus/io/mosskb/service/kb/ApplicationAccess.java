package nexus.io.mosskb.service.kb;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;

public final class ApplicationAccess {
  private ApplicationAccess() {}

  private static final String FIND_ACCESS_NUM = """
      select access_num
      from moss_kb_application_access_token
      where application_id = ?
        and deleted = 0
      """;

  private static final String FIND_PUBLIC_CLIENT = """
      select intraday_access_num
      from moss_kb_application_public_access_client
      where client_id = ?
        and application_id = ?
        and deleted = 0
      order by id desc
      limit 1
      """;

  /** 跨天时把当日计数归零，只动前一天留下的记录。 */
  private static final String RESET_INTRADAY_ACCESS_NUM = """
      update moss_kb_application_public_access_client
      set intraday_access_num = 0,
          update_time = now()
      where client_id = ?
        and application_id = ?
        and deleted = 0
        and update_time < date_trunc('day', now())
      """;

  private static final String COUNT_QUESTION = """
      update moss_kb_application_public_access_client
      set access_num = access_num + 1,
          intraday_access_num = intraday_access_num + 1,
          update_time = now()
      where client_id = ?
        and application_id = ?
        and deleted = 0
      """;

  public static boolean owns(Long userId, Long applicationId) {
    if (userId == null || applicationId == null) {
      return false;
    }
    Row app = Db.findById("moss_kb_application", applicationId);
    return app != null && (userId.equals(app.getLong("user_id")));
  }

  public static boolean canChat(Long clientId, Long applicationId) {
    if (owns(clientId, applicationId)) {
      return true;
    }
    return clientId != null && Db.queryLong("select count(*) from moss_kb_application_public_access_client c join moss_kb_application_access_token t on t.application_id=c.application_id where c.client_id=? and c.application_id=? and t.is_active=true and t.deleted=0", clientId, applicationId) > 0;
  }

  public static boolean canReadChat(Long clientId, Long applicationId, Long chatId) {
    Row chat = Db.findById("moss_kb_application_chat", chatId);
    return chat != null && !Boolean.TRUE.equals(chat.getBoolean("is_deleted")) && applicationId.equals(chat.getLong("application_id"))
        && (owns(clientId, applicationId) || (canChat(clientId, applicationId) && clientId.equals(chat.getLong("client_id"))));
  }

  /**
   * 访客的当日提问上限：公开访问链接上配置了次数（0 表示不限）时按访客分别累计。
   * 返回 null 表示可以提问，否则返回拒绝原因；应用所有者不受该限制。
   */
  public static String refuseReason(Long clientId, Long applicationId) {
    if (owns(clientId, applicationId)) {
      return null;
    }
    Row client = publicClient(clientId, applicationId);
    if (client == null) {
      return null;
    }
    Integer limit = Db.queryInt(FIND_ACCESS_NUM, applicationId);
    if (limit == null || limit <= 0) {
      return null;
    }
    Integer used = client.getInt("intraday_access_num");
    if (used != null && used >= limit) {
      return "今日提问次数已用完，请明天再试";
    }
    return null;
  }

  /** 记一次访客提问，当日次数与累计次数同时加一。 */
  public static void countQuestion(Long clientId, Long applicationId) {
    if (owns(clientId, applicationId)) {
      return;
    }
    Db.update(COUNT_QUESTION, clientId, applicationId);
  }

  private static Row publicClient(Long clientId, Long applicationId) {
    if (clientId == null || applicationId == null) {
      return null;
    }
    Db.update(RESET_INTRADAY_ACCESS_NUM, clientId, applicationId);
    return Db.findFirst(FIND_PUBLIC_CLIENT, clientId, applicationId);
  }
}
