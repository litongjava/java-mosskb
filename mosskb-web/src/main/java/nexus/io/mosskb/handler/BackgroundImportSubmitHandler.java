package nexus.io.mosskb.handler;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.model.BackgroundImportRequest;
import nexus.io.mosskb.service.kb.BackgroundImportService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;
public class BackgroundImportSubmitHandler {
  public HttpResponse handle(HttpRequest request) {
    Long dataset = ParameterValidationUtils.pathId(request, "datasetId");
    Long owner = TioRequestContext.getUserIdLong();
    BackgroundImportService service = Aop.get(BackgroundImportService.class);
    return TioRequestContext.getResponse().respond(service.submit(owner, dataset, request.getBodyObject(BackgroundImportRequest.class)));
  }
}
