package nexus.io.mosskb.config;

import nexus.io.mosskb.inteceptor.MossKbAuthInterceptor;
import nexus.io.tio.boot.admin.consts.TioBootAdminUrls;
import nexus.io.tio.boot.http.interceptor.HttpInteceptorConfigure;
import nexus.io.tio.boot.http.interceptor.HttpInterceptorModel;
import nexus.io.tio.boot.server.TioBootServer;

public class MossKbInterceptorConfiguration {

  public void config() {
    MossKbAuthInterceptor authTokenInterceptor = new MossKbAuthInterceptor();
    HttpInterceptorModel model = new HttpInterceptorModel();
    model.setInterceptor(authTokenInterceptor);

    model.addBlockUrl("/**");

    model.addAllowUrls(TioBootAdminUrls.ALLLOW_URLS);
    model.addAllowUrls("", "/");
    // 前端静态资源，以及写在静态资源目录里的函数图标
    model.addAllowUrls("/ui/**");
    model.addAllowUrls("/pages/**");
    model.addAllowUrls("/sse", "/api/user/login");

    model.addAllowUrls("/api/profile", "/api/application/authentication");

    // 浮窗脚本由第三方页面直接引入，没有本地登录令牌
    model.addAllowUrls("/api/application/embed");

    // 小程序首次进入时还没有任何令牌，只能放行换取令牌这一步
    model.addAllowUrls("/api/miniapp/auth/login");

    model.addAllowUrls("/api/v1/search", "/api/display/info", "/api/auth/types", "/api/qr_type");
    //
    HttpInteceptorConfigure configure = new HttpInteceptorConfigure();
    configure.add(model);

    TioBootServer.me().setHttpInteceptorConfigure(configure);
  }
}
