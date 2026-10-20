package nexus.io.mosskb.config;

import nexus.io.mosskb.handler.miniapp.MiniAppApplicationHandler;
import nexus.io.mosskb.handler.miniapp.MiniAppChatMessageHandler;
import nexus.io.mosskb.handler.miniapp.MiniAppChatOpenHandler;
import nexus.io.mosskb.handler.miniapp.MiniAppLoginHandler;
import nexus.io.mosskb.handler.miniapp.MiniAppQrCodeHandler;
import nexus.io.tio.boot.server.TioBootServer;
import nexus.io.tio.http.server.router.HttpRequestRouter;

/**
 * 微信小程序接口的路由注册。一个接口对应一个 Handler，参数校验与鉴权都不在这里完成：
 * 令牌校验交给拦截器，参数校验交给全局异常处理器。
 */
public class MiniAppHandlerConfiguration {

  public void config() {
    HttpRequestRouter router = TioBootServer.me().getRequestRouter();
    if (router == null) {
      return;
    }
    MiniAppLoginHandler loginHandler = new MiniAppLoginHandler();
    router.post("/api/miniapp/auth/login", loginHandler::handle);

    MiniAppApplicationHandler applicationHandler = new MiniAppApplicationHandler();
    router.get("/api/miniapp/application/{applicationId}", applicationHandler::handle);

    MiniAppChatOpenHandler chatOpenHandler = new MiniAppChatOpenHandler();
    router.post("/api/miniapp/chat/open/{applicationId}", chatOpenHandler::handle);

    MiniAppChatMessageHandler chatMessageHandler = new MiniAppChatMessageHandler();
    router.post("/api/miniapp/chat/{chatId}/message", chatMessageHandler::handle);

    MiniAppQrCodeHandler qrCodeHandler = new MiniAppQrCodeHandler();
    router.post("/api/miniapp/admin/qrcode", qrCodeHandler::handle);
  }
}
