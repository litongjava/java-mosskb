package nexus.io.mosskb.handler.miniapp;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.miniapp.MiniAppQrCodeService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.miniapp.MiniAppQrCodeRequestVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;

/** POST /api/miniapp/admin/qrcode 管理端生成智能提示的小程序码。 */
public class MiniAppQrCodeHandler {

  public HttpResponse handle(HttpRequest request) {
    MiniAppQrCodeRequestVo input = ParameterValidationUtils.body(request, MiniAppQrCodeRequestVo.class);
    Long userId = TioRequestContext.getUserIdLong();
    RespBodyVo body = Aop.get(MiniAppQrCodeService.class).generate(userId, input);
    return TioRequestContext.getResponse().respond(body);
  }
}
