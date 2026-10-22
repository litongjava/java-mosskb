package nexus.io.mosskb.service.kb;

import org.postgresql.util.PGobject;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.kit.PgObjectUtils;
import nexus.io.mosskb.model.MossKbApplicationChat;
import nexus.io.mosskb.model.MossKbApplicationTempSetting;
import nexus.io.mosskb.vo.MossKbApplicationVo;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

public class MossKbApplicationChatService {

  public ResultVo openPublished(Long applicationId) {
    Long clientId = nexus.io.tio.boot.http.TioRequestContext.getUserIdLong();
    if (!ApplicationAccess.canChat(clientId, applicationId)) {
      return ResultVo.fail("应用不存在或无权访问");
    }
    long chatId = SnowflakeIdUtils.id();
    new MossKbApplicationChat().setId(chatId).setApplicationId(applicationId).setClientId(clientId).setChatType(0).save();
    return ResultVo.ok(chatId);
  }

  public ResultVo open(String bodyString, MossKbApplicationVo vo) {
    Long id = vo.getId();
    Long userId = nexus.io.tio.boot.http.TioRequestContext.getUserIdLong();
    Row app = Db.findById("moss_kb_application", id);
    if (userId == null || app == null || (!userId.equals(app.getLong("user_id")))) {
      return ResultVo.fail("应用不存在或无权访问");
    }
    long chatId = SnowflakeIdUtils.id();
    PGobject jsonb = PgObjectUtils.jsonb(bodyString);
    Db.tx(() -> {
      Db.save(MossKbApplicationTempSetting.tableName, Row.by("id", chatId).set("setting", jsonb));
      new MossKbApplicationChat().setId(chatId).setApplicationId(id).setClientId(userId).setChatType(1).save();
      return true;
    });
    return ResultVo.ok(chatId);
  }

}
