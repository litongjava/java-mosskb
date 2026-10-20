package nexus.io.mosskb.service.miniapp;

import com.alibaba.fastjson2.JSONObject;

import lombok.extern.slf4j.Slf4j;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.constant.MossKbTableNames;
import nexus.io.mosskb.service.kb.ApplicationAccess;
import nexus.io.mosskb.service.kb.BlockingChatEventSink;
import nexus.io.mosskb.service.kb.MossKbApplicationChatMessageService;
import nexus.io.mosskb.service.kb.MossKbApplicationChatService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.MossKbChatRequestVo;
import nexus.io.mosskb.vo.miniapp.MiniAppApplicationVo;
import nexus.io.mosskb.vo.miniapp.MiniAppChatAnswerVo;
import nexus.io.mosskb.vo.miniapp.MiniAppChatRequestVo;
import nexus.io.mosskb.vo.miniapp.MiniAppSessionVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.utils.environment.EnvUtils;
import nexus.io.tio.utils.json.FastJson2Utils;

/**
 * 小程序侧的对话服务。提问沿用后台同一套检索与推理流程，只是把回答一次性取回，
 * 因此小程序无需处理 SSE 长连接。
 */
@Slf4j
public class MiniAppChatService {

  /** 等待回答的上限，一次请求超时后小程序可以稍后重新发起。 */
  private static final long DEFAULT_TIMEOUT_MS = 120_000L;

  /** 会话与记录所属应用的校验放在服务层，避免仅凭会话标识就能读到他人的回答。 */
  private static final String FIND_CHAT = """
      select application_id, client_id, is_deleted
      from moss_kb_application_chat
      where id = ?
      """;

  private static final String FIND_LAST_RECORD = """
      select id, answer_text
      from moss_kb_application_chat_record
      where chat_id = ?
      order by id desc
      limit 1
      """;

  public RespBodyVo profile(Long applicationId, Long clientId) {
    if (!ApplicationAccess.canChat(clientId, applicationId)) {
      return RespBodyVo.fail("智能提示不存在或未开放访问");
    }
    Row app = Db.findById(MossKbTableNames.moss_kb_application, applicationId);
    if (app == null) {
      return RespBodyVo.fail("智能提示不存在");
    }
    MiniAppApplicationVo data = new MiniAppApplicationVo()
        //
        .setId(String.valueOf(applicationId)).setName(app.getStr("name")).setDescription(app.getStr("desc"))
        //
        .setPrologue(app.getStr("prologue")).setDialogue_number(app.getInt("dialogue_number"))
        //
        .setIcon(app.getStr("icon")).setShow_source(app.getBoolean("show_source"));
    return RespBodyVo.ok(data);
  }

  /** 为新访客开一个会话，返回会话标识。 */
  public RespBodyVo openChat(Long applicationId, Long clientId) {
    if (!ApplicationAccess.canChat(clientId, applicationId)) {
      return RespBodyVo.fail("智能提示不存在或未开放访问");
    }
    ResultVo result = Aop.get(MossKbApplicationChatService.class).openPublished(applicationId);
    if (result.getCode() != 200 || result.getData() == null) {
      return RespBodyVo.fail(result.getMessage() == null ? "会话创建失败" : result.getMessage());
    }
    return RespBodyVo.ok(new MiniAppSessionVo().setChat_id(String.valueOf(result.getData()))
        .setApplication_id(String.valueOf(applicationId)));
  }

  /** 提问并等待回答。 */
  public RespBodyVo chat(Long chatId, Long clientId, MiniAppChatRequestVo input) {
    String message = ParameterValidationUtils.requiredText(input.getMessage(), "message", 8000);
    Row chat = Db.findFirst(FIND_CHAT, chatId);
    if (chat == null || Boolean.TRUE.equals(chat.getBoolean("is_deleted"))) {
      return RespBodyVo.fail("会话不存在，请重新进入");
    }
    Long applicationId = chat.getLong("application_id");
    if (!ApplicationAccess.canReadChat(clientId, applicationId, chatId)) {
      return RespBodyVo.fail("无权访问该会话");
    }

    MossKbChatRequestVo request = new MossKbChatRequestVo().setMessage(message).setRe_chat(false);
    BlockingChatEventSink sink = new BlockingChatEventSink();
    ResultVo started = Aop.get(MossKbApplicationChatMessageService.class).ask(sink, chatId, request);
    if (started.getCode() != 200) {
      return RespBodyVo.fail(started.getMessage() == null ? "提问失败" : started.getMessage());
    }

    boolean finished = sink.await(timeoutMillis());
    if (!finished && sink.hasError()) {
      return RespBodyVo.fail(errorMessage(sink.error()));
    }
    MiniAppChatAnswerVo data = answer(chatId, sink, !finished);
    if (!finished) {
      log.warn("miniapp chat timeout, chatId={}", chatId);
    }
    return RespBodyVo.ok(data);
  }

  /** 回答以数据库记录为准，写入延迟时退回通道里收集到的正文。 */
  private MiniAppChatAnswerVo answer(Long chatId, BlockingChatEventSink sink, boolean timeout) {
    Row record = Db.findFirst(FIND_LAST_RECORD, chatId);
    String answer = record == null ? null : record.getStr("answer_text");
    if (answer == null || answer.isBlank()) {
      answer = sink.answer();
    }
    MiniAppChatAnswerVo data = new MiniAppChatAnswerVo().setChat_id(String.valueOf(chatId))
        //
        .setMessage_id(record == null ? null : String.valueOf(record.getLong("id")))
        //
        .setAnswer(answer).setTimeout(timeout);
    return data;
  }

  /** 通道里的错误是 Kv JSON，取出 message 作为回显原因。 */
  private String errorMessage(String payload) {
    try {
      JSONObject json = FastJson2Utils.parseObject(payload);
      String message = json == null ? null : json.getString("message");
      return message == null ? "回答生成失败，请稍后重试" : message;
    } catch (Exception e) {
      return "回答生成失败，请稍后重试";
    }
  }

  private long timeoutMillis() {
    return EnvUtils.getLong("wechat.miniapp.chat-timeout-ms", DEFAULT_TIMEOUT_MS);
  }
}
