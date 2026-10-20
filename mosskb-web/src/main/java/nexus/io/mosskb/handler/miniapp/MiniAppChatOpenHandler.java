package nexus.io.mosskb.handler.miniapp;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.miniapp.MiniAppChatService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;

/** POST /api/miniapp/chat/open/{applicationId} 创建会话。 */
public class MiniAppChatOpenHandler {

  public HttpResponse handle(HttpRequest request) {
    Long applicationId = ParameterValidationUtils.pathId(request, "applicationId");
    Long clientId = TioRequestContext.getUserIdLong();
    RespBodyVo body = Aop.get(MiniAppChatService.class).openChat(applicationId, clientId);
    return TioRequestContext.getResponse().respond(body);
  }
}
