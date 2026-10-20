package nexus.io.mosskb.handler.miniapp;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.miniapp.MiniAppAuthService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.miniapp.MiniAppLoginRequestVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;

/** POST /api/miniapp/auth/login 小程序访客登录。 */
public class MiniAppLoginHandler {

  public HttpResponse handle(HttpRequest request) {
    MiniAppLoginRequestVo input = ParameterValidationUtils.body(request, MiniAppLoginRequestVo.class);
    RespBodyVo body = Aop.get(MiniAppAuthService.class).login(input);
    return TioRequestContext.getResponse().respond(body);
  }
}
