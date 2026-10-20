package nexus.io.mosskb.stream;

import java.io.IOException;
import java.util.List;

import org.postgresql.util.PGobject;

import lombok.extern.slf4j.Slf4j;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.http.common.sse.SsePacket;
import nexus.io.kit.PgObjectUtils;
import nexus.io.mosskb.constant.MossKbTableNames;
import nexus.io.mosskb.constant.SSEConstant;
import nexus.io.mosskb.service.ChatStreamCallCan;
import nexus.io.mosskb.service.kb.ChatEventSink;
import nexus.io.mosskb.service.kb.SseChatEventSink;
import nexus.io.mosskb.utils.TokenCounter;
import nexus.io.mosskb.vo.MossKbChatRecordDetail;
import nexus.io.mosskb.vo.MossKbChatStep;
import nexus.io.mosskb.vo.MossKbRetrieveResult;
import nexus.io.mosskb.vo.MossKbStreamChatVo;
import nexus.io.openai.chat.ChatResponseDelta;
import nexus.io.openai.chat.Choice;
import nexus.io.openai.chat.OpenAiChatResponse;
import nexus.io.tio.core.ChannelContext;
import nexus.io.tio.core.Tio;
import nexus.io.tio.utils.json.FastJson2Utils;
import nexus.io.tio.utils.json.JsonUtils;
import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.Response;
import okhttp3.ResponseBody;

@Slf4j
public class ChatStreamCallbackImpl implements Callback {

  private final Long chatId;
  private final Long messageId;
  private final long start;
  private final MossKbRetrieveResult searchStep;
  private final MossKbChatStep chatStep;
  private final ChatEventSink sink;

  /** SSE 分享页使用：回答增量实时推送到浏览器连接。 */
  public ChatStreamCallbackImpl(Long chatId, Long messageId, long start, MossKbRetrieveResult searchStep, MossKbChatStep chatStep,
      //
      ChannelContext channelContext) {
    this(chatId, messageId, start, searchStep, chatStep, new SseChatEventSink(channelContext));
  }

  /** 一次性返回的场景（小程序、服务端调用）使用自定义通道。 */
  public ChatStreamCallbackImpl(Long chatId, Long messageId, long start, MossKbRetrieveResult searchStep, MossKbChatStep chatStep,
      //
      ChatEventSink sink) {
    this.chatId = chatId;
    this.messageId = messageId;
    this.start = start;
    this.searchStep = searchStep;
    this.chatStep = chatStep;
    this.sink = sink;

  }

  @Override
  public void onResponse(Call call, Response response) throws IOException {
    if (!response.isSuccessful()) {
      sendError("推理服务返回 HTTP " + response.code());
      response.close();
      cleanup(chatId);
      sink.finish();
      return;
    }

    try (ResponseBody responseBody = response.body()) {
      if (responseBody == null) {
        String message = "response body is null";
        log.error(message);
        sendError(message);
        cleanup(chatId);
        sink.finish();
        return;
      }      StringBuffer completionContent = processResponseBody(chatId, messageId, sink, responseBody);
      long elpased = System.currentTimeMillis() - start;
      double runTime = ((double) elpased) / 1000;
      int answer_tokens = TokenCounter.countTokens(completionContent.toString());
      chatStep.setRun_time(runTime).setAnswer_tokens(answer_tokens);

      MossKbChatRecordDetail detail = new MossKbChatRecordDetail(chatStep, searchStep);
      String json = JsonUtils.toJson(detail);
      PGobject pgobject = PgObjectUtils.json(json);
      Row record = Row.by("id", messageId).set("run_time", runTime).set("answer_text", completionContent.toString())
          //
          .set("answer_tokens", answer_tokens).set("message_tokens", chatStep.getMessage_tokens())
          //
          .set("details", pgobject);
      Db.update(MossKbTableNames.moss_kb_application_chat_record, record);
      // Persist before the end event, so an immediate follow-up sees this answer.
      MossKbStreamChatVo end = new MossKbStreamChatVo();
      end.setContent("").setChat_id(chatId).setId(messageId).setChat_record_id(messageId.toString());
      end.setOperate(true).setIs_end(true).setNode_is_end(true);
      sink.chunk(JsonUtils.toJson(end));

    } catch (Exception e) {
      log.error("Streaming answer failed", e);
      sendError("回答生成失败，请稍后重试");
    } finally {
      cleanup(chatId);
      sink.finish();
    }

  }

  @Override
  public void onFailure(Call call, IOException e) {
    sendError("推理服务连接失败，请稍后重试");
    cleanup(chatId);
    sink.finish();
  }

  public StringBuffer processResponseBody(Long chatId, Long messageId, ChatEventSink sink, ResponseBody responseBody) throws IOException {
    StringBuffer completionContent = new StringBuffer();
    StringBuffer fnCallName = new StringBuffer();
    StringBuffer fnCallArgs = new StringBuffer();

    String line;
    while ((line = responseBody.source().readUtf8Line()) != null) {
      if (line.length() < 1) {
        continue;
      }

      // 因为原始数据是data:开头
      if (line.startsWith("data: ") && !line.equals("data: [DONE]")) {
        processResponseChunk(chatId, messageId, sink, completionContent, line);
      }
    }

    // 发送一个大小为 0 的 chunk 以表示消息结束
    if (fnCallName.length() > 0) {
      // 获取数据
      String functionCallResult = functionCall(fnCallName, fnCallArgs);
      // 再次发送到大模型
      if (functionCallResult != null) {
        // 处理 functionCallResult 的逻辑
        // 例如，可以重新调用 stream 方法
      } else {
        long end = System.currentTimeMillis();
        log.info("finish llm in {} (ms):", (end - start));
        sink.finish();
      }
    }
    return completionContent;
  }

  private void processResponseChunk(Long chatId, Long messageId, ChatEventSink sink, StringBuffer completionContent, String line) {
    String data = line.substring(6);
    if (data.endsWith("}")) {
      OpenAiChatResponse chatResponse = FastJson2Utils.parse(data, OpenAiChatResponse.class);
      List<Choice> choices = chatResponse.getChoices();
      if (choices != null && !choices.isEmpty() && choices.get(0).getDelta() != null) {
        ChatResponseDelta delta = choices.get(0).getDelta();
        String part = delta.getContent();
        if (part != null && part.length() > 0) {
          completionContent.append(part);
          MossKbStreamChatVo mossKbStreamChatVo = new MossKbStreamChatVo();
          mossKbStreamChatVo.setContent(part);
          mossKbStreamChatVo.setChat_id(chatId).setId(messageId).setChat_record_id(messageId.toString());
          mossKbStreamChatVo.setOperate(true).setIs_end(false);

          String message = JsonUtils.toJson(mossKbStreamChatVo);
          sink.chunk(message);
        }
      }
    }
  }

  private void sendError(String message) {
    sink.event("error", JsonUtils.toJson(com.jfinal.kit.Kv.by("code", 500).set("message", message)));
  }

  private String functionCall(StringBuffer fnCallName, StringBuffer fnCallArgs) {
    // 实现你的 functionCall 逻辑
    return null;
  }

  public void cleanup(Long chatId) {
    ChatStreamCallCan.remove(chatId);
    nexus.io.mosskb.service.kb.ChatExecution.end(chatId);
  }
}
