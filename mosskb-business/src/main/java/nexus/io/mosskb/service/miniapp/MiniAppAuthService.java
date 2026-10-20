package nexus.io.mosskb.service.miniapp;

import com.alibaba.fastjson2.JSONObject;

import lombok.extern.slf4j.Slf4j;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.MossKbAuthService;
import nexus.io.mosskb.service.kb.MossKbApplicationAccessTokenService;
import nexus.io.mosskb.service.miniapp.MiniAppSceneService.SceneApplication;
import nexus.io.mosskb.vo.miniapp.MiniAppLoginRequestVo;
import nexus.io.mosskb.vo.miniapp.MiniAppLoginVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.utils.environment.EnvUtils;
import nexus.io.tio.utils.hutool.StrUtil;

/**
 * 小程序访客登录。小程序没有账号体系，进入即按公开访问链接的规则登记访客，
 * 拿到的是与分享页同一套长期令牌，因此应用侧的停用、次数限制都自动生效。
 */
@Slf4j
public class MiniAppAuthService {

  /** 令牌有效期沿用后台配置，返回给前端用于展示与续期判断。 */
  private static final int DEFAULT_EXPIRES_IN = 604800;

  private final MiniAppWeChatClient wechatClient = new MiniAppWeChatClient();

  public RespBodyVo login(MiniAppLoginRequestVo input) {
    if (input == null || StrUtil.isBlank(input.getScene())) {
      return RespBodyVo.fail("缺少 scene，请从小程序码进入");
    }
    SceneApplication scene = Aop.get(MiniAppSceneService.class).resolve(input.getScene());
    if (scene == null) {
      return RespBodyVo.fail("小程序码无效，或该智能提示已停止对外访问");
    }

    boolean devMode = false;
    if (MiniAppWeChatClient.configured()) {
      if (StrUtil.isBlank(input.getCode())) {
        return RespBodyVo.fail("缺少微信登录凭证");
      }
      try {
        JSONObject session = wechatClient.codeToSession(input.getCode());
        log.info("miniapp login openid={} application={}", session.getString("openid"), scene.applicationId());
      } catch (MiniAppWeChatException e) {
        return RespBodyVo.fail(e.getMessage());
      }
    } else {
      if (!devLoginEnabled()) {
        return RespBodyVo.fail("服务端未配置微信小程序凭据，暂时无法登录");
      }
      devMode = true;
      log.warn("miniapp dev login application={}, configure wechat.miniapp.appid/secret before release",
          scene.applicationId());
    }

    // 复用公开访问链接的登记逻辑：设备已有令牌且仍属于该应用时原样返回
    ResultVo auth = Aop.get(MossKbApplicationAccessTokenService.class).authentication(scene.accessToken(), input.getToken());
    if (auth.getCode() != 200 || auth.getData() == null) {
      return RespBodyVo.fail(auth.getMessage() == null ? "登录失败" : auth.getMessage());
    }
    String token = String.valueOf(auth.getData());
    Long clientId = Aop.get(MossKbAuthService.class).getIdByToken(token);
    if (clientId == null) {
      return RespBodyVo.fail("登录失败，请重试");
    }

    MiniAppLoginVo data = new MiniAppLoginVo().setToken(token).setClient_id(String.valueOf(clientId))
        //
        .setApplication_id(String.valueOf(scene.applicationId())).setApplication_name(scene.applicationName())
        //
        .setExpires_in(DEFAULT_EXPIRES_IN).setDev_mode(devMode);
    return RespBodyVo.ok(data);
  }

  /** 未配置微信凭据时是否允许本地直登：默认只在本地开发运行（target/classes）放行。 */
  private boolean devLoginEnabled() {
    return EnvUtils.getBoolean("wechat.miniapp.dev-login", EnvUtils.isDevMode());
  }
}
