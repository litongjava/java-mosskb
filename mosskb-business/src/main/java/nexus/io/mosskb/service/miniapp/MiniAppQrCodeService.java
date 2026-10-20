package nexus.io.mosskb.service.miniapp;

import java.util.Base64;

import lombok.extern.slf4j.Slf4j;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.kb.ApplicationAccess;
import nexus.io.mosskb.vo.miniapp.MiniAppQrCodeRequestVo;
import nexus.io.mosskb.vo.miniapp.MiniAppQrCodeVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.utils.hutool.StrUtil;
import nexus.io.tio.utils.validator.ParameterValidator;

/**
 * 智能提示的小程序码。scene 直接使用应用当前的公开访问令牌，扫码等价于打开分享链接，
 * 因此小程序码不需要新的授权数据，撤销或重置分享令牌后旧码自然失效。
 */
@Slf4j
public class MiniAppQrCodeService {

  /** 微信规定 scene 最长 32 个字符且必须是可见字符。 */
  private static final int MAX_SCENE_LENGTH = 32;

  private static final int MIN_WIDTH = 280;
  private static final int MAX_WIDTH = 1280;

  private final MiniAppWeChatClient wechatClient = new MiniAppWeChatClient();

  public RespBodyVo generate(Long userId, MiniAppQrCodeRequestVo input) {
    if (!MiniAppWeChatClient.configured()) {
      return RespBodyVo.fail("未配置微信小程序凭据，无法生成小程序码");
    }
    Long applicationId = ParameterValidator.id(input.getApplication_id(), "application_id");
    if (!ApplicationAccess.owns(userId, applicationId)) {
      return RespBodyVo.fail("智能提示不存在或无权访问");
    }

    String scene = Aop.get(MiniAppSceneService.class).sceneOf(applicationId);
    if (StrUtil.isBlank(scene)) {
      return RespBodyVo.fail("该智能提示还没有公开访问链接，请先在公开访问设置里启用");
    }
    if (scene.length() > MAX_SCENE_LENGTH) {
      return RespBodyVo.fail("公开访问令牌超过 " + MAX_SCENE_LENGTH + " 个字符，无法写入小程序码");
    }

    String page = page(input.getPage());
    String envVersion = envVersion(input.getEnv_version());
    boolean checkPath = input.getCheck_path() == null ? "release".equals(envVersion) : input.getCheck_path();
    int width = width(input.getWidth());

    byte[] image;
    try {
      image = wechatClient.unlimitedQrCode(scene, page, checkPath, envVersion, width);
    } catch (MiniAppWeChatException e) {
      log.warn("generate miniapp qrcode failed applicationId={}: {}", applicationId, e.getMessage());
      return RespBodyVo.fail(e.getMessage());
    }

    String applicationName = nexus.io.db.activerecord.Db.queryStr("select name from moss_kb_application where id = ?",
        applicationId);
    MiniAppQrCodeVo data = new MiniAppQrCodeVo().setApplication_id(String.valueOf(applicationId))
        //
        .setApplication_name(applicationName).setScene(scene).setPage(page).setEnv_version(envVersion)
        //
        .setContent_type("image/png").setImage_base64(Base64.getEncoder().encodeToString(image));
    return RespBodyVo.ok(data);
  }

  /** 页面路径不能以斜杠开头，留空时用配置里的默认页面。 */
  private String page(String page) {
    String value = StrUtil.isBlank(page) ? MiniAppWeChatClient.defaultPage() : page.trim();
    ParameterValidator.require(value.length() <= 128, "page 过长");
    return value.startsWith("/") ? value.substring(1) : value;
  }

  private String envVersion(String envVersion) {
    return ParameterValidator.choice(envVersion, "env_version", MiniAppWeChatClient.defaultEnvVersion(), "release",
        "trial", "develop");
  }

  private int width(Integer width) {
    if (width == null) {
      return MiniAppWeChatClient.DEFAULT_QR_WIDTH;
    }
    ParameterValidator.require(width >= MIN_WIDTH && width <= MAX_WIDTH,
        "width 需要在 " + MIN_WIDTH + " 到 " + MAX_WIDTH + " 之间");
    return width;
  }
}
