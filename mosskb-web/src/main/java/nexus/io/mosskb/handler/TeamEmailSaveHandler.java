package nexus.io.mosskb.handler;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.model.TeamEmailSettings;
import nexus.io.mosskb.service.TeamSettingsService;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;

public class TeamEmailSaveHandler {
  public HttpResponse handle(HttpRequest request) {
    return TioRequestContext.getResponse().respond(Aop.get(TeamSettingsService.class).save(TioRequestContext.getUserIdLong(), request.getBodyObject(TeamEmailSettings.class)));
  }
}
