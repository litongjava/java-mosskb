package nexus.io.mosskb.config;

import java.util.ArrayList;
import java.util.List;

import nexus.io.mosskb.controller.ApiApplicationChatController;
import nexus.io.mosskb.controller.ApiApplicationChatMessageController;
import nexus.io.mosskb.controller.ApiApplicationController;
import nexus.io.mosskb.controller.ApiAuthCASController;
import nexus.io.mosskb.controller.ApiAuthLDAPController;
import nexus.io.mosskb.controller.ApiAuthOAUTH2Controller;
import nexus.io.mosskb.controller.ApiAuthOIDCController;
import nexus.io.mosskb.controller.ApiAuthTypesController;
import nexus.io.mosskb.controller.ApiDatasetController;
import nexus.io.mosskb.controller.ApiDatasetDocumentController;
import nexus.io.mosskb.controller.ApiDisplayController;
import nexus.io.mosskb.controller.ApiEmailSettingController;
import nexus.io.mosskb.controller.ApiFunctionLibController;
import nexus.io.mosskb.controller.ApiModelController;
import nexus.io.mosskb.controller.ApiPlatformController;
import nexus.io.mosskb.controller.ApiProfileController;
import nexus.io.mosskb.controller.ApiProviderController;
import nexus.io.mosskb.controller.ApiQrTypeController;
import nexus.io.mosskb.controller.ApiTableMossKbParagraphController;
import nexus.io.mosskb.controller.ApiTeamController;
import nexus.io.mosskb.controller.ApiUserController;
import nexus.io.mosskb.controller.ApiUserManage;
import nexus.io.mosskb.controller.ApiValidController;
import nexus.io.tio.boot.http.handler.controller.TioBootHttpControllerRouter;
import nexus.io.tio.boot.server.TioBootServer;

public class MossKbControllerConfiguration {

  public void config() {
    TioBootHttpControllerRouter controllerRouter = TioBootServer.me().getControllerRouter();
    if (controllerRouter == null) {
      return;
    }
    List<Class<?>> scannedClasses = new ArrayList<>();
    scannedClasses.add(ApiApplicationChatController.class);
    scannedClasses.add(ApiApplicationChatMessageController.class);
    scannedClasses.add(ApiApplicationController.class);
    scannedClasses.add(ApiAuthCASController.class);
    scannedClasses.add(ApiAuthLDAPController.class);
    scannedClasses.add(ApiAuthOAUTH2Controller.class);
    scannedClasses.add(ApiAuthOIDCController.class);
    scannedClasses.add(ApiAuthTypesController.class);
    scannedClasses.add(ApiDatasetController.class);
    scannedClasses.add(ApiDatasetDocumentController.class);
    scannedClasses.add(ApiDisplayController.class);

    scannedClasses.add(ApiFunctionLibController.class);
    scannedClasses.add(ApiModelController.class);
    scannedClasses.add(ApiPlatformController.class);
    scannedClasses.add(ApiProfileController.class);
    scannedClasses.add(ApiProviderController.class);
    scannedClasses.add(ApiQrTypeController.class);
    scannedClasses.add(ApiTableMossKbParagraphController.class);

    scannedClasses.add(ApiUserController.class);
    scannedClasses.add(ApiUserManage.class);
    scannedClasses.add(ApiValidController.class);
    //scannedClasses.add(MongodbController.class);
    controllerRouter.addControllers(scannedClasses);
  }
}
