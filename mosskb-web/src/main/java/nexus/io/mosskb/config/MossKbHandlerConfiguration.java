package nexus.io.mosskb.config;

import nexus.io.mosskb.handler.TeamEmailReadHandler;
import nexus.io.mosskb.handler.BackgroundImportSubmitHandler;
import nexus.io.mosskb.handler.BackgroundImportListHandler;
import nexus.io.mosskb.handler.TeamEmailSaveHandler;
import nexus.io.mosskb.handler.ApiRagDatasetRetrievalTitleHandler;
import nexus.io.mosskb.httphandler.SearxngSearchHandler;
import nexus.io.tio.boot.admin.config.TioAdminControllerConfiguration;
import nexus.io.tio.boot.admin.config.TioAdminHandlerConfiguration;
import nexus.io.tio.boot.server.TioBootServer;
import nexus.io.tio.http.server.router.HttpRequestRouter;

public class MossKbHandlerConfiguration {
  public void config() {
    HttpRequestRouter router = TioBootServer.me().getRequestRouter();
    if (router == null) {
      return;
    }
    router.post("/api/dataset/{datasetId}/background-import", new BackgroundImportSubmitHandler()::handle);
    router.get("/api/dataset/{datasetId}/background-import", new BackgroundImportListHandler()::handle);
    router.get("/api/email_setting", new TeamEmailReadHandler()::handle);
    router.post("/api/email_setting/save", new TeamEmailSaveHandler()::handle);
    SearxngSearchHandler searxngSearchHandler = new SearxngSearchHandler();
    router.add("/api/v1/search", searxngSearchHandler::search);
    ApiRagDatasetRetrievalTitleHandler apiRagDatasetHandler = new ApiRagDatasetRetrievalTitleHandler();
    router.add("/api/v1/rag/dataset/retrieval/title", apiRagDatasetHandler::index);

    // 微信小程序接口
    new MiniAppHandlerConfiguration().config();

    new TioAdminHandlerConfiguration().config();
    new TioAdminControllerConfiguration().config();
  }
}
