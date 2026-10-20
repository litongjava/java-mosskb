package nexus.io.mosskb.handler.miniapp;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.miniapp.MiniAppChatService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.miniapp.MiniAppChatRequestVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;

/** POST /api/miniapp/chat/{chatId}/message 一次性返回回答的提问接口。 */
public class MiniAppChatMessageHandler {

  public HttpResponse handle(HttpRequest request) {
    Long chatId = ParameterValidationUtils.pathId(request, "chatId");
    Long clientId = TioRequestContext.getUserIdLong();
    MiniAppChatRequestVo input = ParameterValidationUtils.body(request, MiniAppChatRequestVo.class);
    RespBodyVo body = Aop.get(MiniAppChatService.class).chat(chatId, clientId, input);
    return TioRequestContext.getResponse().respond(body);
  }
}
