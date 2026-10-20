package nexus.io.mosskb.controller;

import nexus.io.annotation.Post;
import nexus.io.annotation.RequestPath;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.kb.MossKbApplicationChatMessageService;
import nexus.io.mosskb.service.kb.SseChatEventSink;
import nexus.io.mosskb.vo.MossKbChatRequestVo;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.core.Tio;
import nexus.io.tio.http.common.HeaderName;
import nexus.io.tio.http.common.HeaderValue;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;
import nexus.io.tio.http.server.util.CORSUtils;
import nexus.io.tio.server.ServerChannelContext;
import nexus.io.tio.utils.json.JsonUtils;

@RequestPath("/api/application/chat_message")
public class ApiApplicationChatMessageController {

  @Post("/{chatId}")
  public HttpResponse ask(Long chatId, HttpRequest request, ServerChannelContext channelContext) {
    String bodyString = request.getBodyString();
    MossKbChatRequestVo mossKbChatRequestVo = JsonUtils.parse(bodyString, MossKbChatRequestVo.class);
    HttpResponse httpResponse = TioRequestContext.getResponse();
    CORSUtils.enableCORS(httpResponse);
    // 设置sse请求头
    httpResponse.addServerSentEventsHeader();
    // 设置响应头
    httpResponse.addHeader(HeaderName.Transfer_Encoding, HeaderValue.from("chunked"));
    httpResponse.addHeader(HeaderName.Keep_Alive, HeaderValue.from("timeout=60"));
    // 手动发送消息到客户端,因为已经设置了sse的请求头,所以客户端的连接不会关闭
    Tio.bSend(channelContext, httpResponse);
    httpResponse.setSend(false);
    try {
      ResultVo result = Aop.get(MossKbApplicationChatMessageService.class).ask(new SseChatEventSink(channelContext), chatId, mossKbChatRequestVo);
      if (result.getCode() != 200) {
        nexus.io.tio.http.server.util.SseEmitter.pushSSEChunk(channelContext, "error", JsonUtils.toJson(result));
        nexus.io.tio.http.server.util.SseEmitter.closeChunkConnection(channelContext);
      }
    } catch (Exception e) {
      nexus.io.tio.http.server.util.SseEmitter.pushSSEChunk(channelContext, "error", JsonUtils.toJson(ResultVo.fail(e.getMessage())));
      nexus.io.tio.http.server.util.SseEmitter.closeChunkConnection(channelContext);
    }
    return httpResponse;
  }
}
