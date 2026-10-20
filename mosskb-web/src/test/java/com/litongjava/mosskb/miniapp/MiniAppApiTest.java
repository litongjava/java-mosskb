package com.litongjava.mosskb.miniapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.config.MossKbDbConfig;
import nexus.io.mosskb.service.MossKbAuthService;
import nexus.io.mosskb.service.kb.MossKbApplicationAccessTokenService;
import nexus.io.mosskb.service.miniapp.MiniAppChatService;
import nexus.io.mosskb.service.miniapp.MiniAppQrCodeService;
import nexus.io.mosskb.service.miniapp.MiniAppSceneService;
import nexus.io.mosskb.service.miniapp.MiniAppSceneService.SceneApplication;
import nexus.io.mosskb.service.miniapp.MiniAppWeChatClient;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.miniapp.MiniAppApplicationVo;
import nexus.io.mosskb.vo.miniapp.MiniAppChatRequestVo;
import nexus.io.mosskb.vo.miniapp.MiniAppQrCodeRequestVo;
import nexus.io.mosskb.vo.miniapp.MiniAppSessionVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpMethod;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;
import nexus.io.tio.http.common.RequestLine;
import nexus.io.tio.utils.environment.EnvUtils;
import nexus.io.tio.utils.validator.ParameterValidationException;

/**
 * 小程序链路的联调测试：scene 解析、访客令牌、会话与参数校验都走真实数据库，
 * 提问部分只验证到参数与权限校验，避免测试依赖外部推理服务。
 */
public class MiniAppApiTest {

  private static boolean databaseReady;

  /** 只初始化数据库配置，不启动 HTTP 服务。 */
  private static void prepareDatabase() {
    if (databaseReady) {
      return;
    }
    EnvUtils.load();
    new MossKbDbConfig().config();
    databaseReady = true;
  }

  /** 服务层通过请求上下文取当前访客，测试里补一个最小上下文。 */
  private static void holdRequestContext(Long clientId) {
    HttpRequest request = new HttpRequest();
    RequestLine requestLine = new RequestLine();
    requestLine.setMethod(HttpMethod.POST);
    requestLine.setPath("/api/miniapp/chat/open");
    requestLine.setVersion("1.1");
    request.requestLine = requestLine;
    request.setUserId(clientId);
    TioRequestContext.hold(request, new HttpResponse(request));
  }

  /** 取一个启用公开访问的智能提示，库中没有数据时跳过断言。 */
  private static final String FIND_SCENE = """
      select t.application_id, t.access_token
      from moss_kb_application_access_token t
      join moss_kb_application a on a.id = t.application_id
      where t.deleted = 0
        and t.is_active = true
        and a.deleted = 0
      order by t.update_time desc
      limit 1
      """;

  @Test
  public void sceneResolvesToApplication() {
    prepareDatabase();
    Row row = Db.findFirst(FIND_SCENE);
    if (row == null) {
      return;
    }
    String scene = row.getLong("access_token").toString();
    SceneApplication resolved = Aop.get(MiniAppSceneService.class).resolve(scene);
    assertNotNull(resolved);
    assertEquals(row.getLong("application_id"), resolved.applicationId());
    assertNull(Aop.get(MiniAppSceneService.class).resolve("not-a-real-scene"));
  }

  @Test
  public void guestTokenCanReadProfileAndOpenChat() {
    prepareDatabase();
    Row row = Db.findFirst(FIND_SCENE);
    if (row == null) {
      return;
    }
    ResultVo auth = Aop.get(MossKbApplicationAccessTokenService.class).authentication(row.getLong("access_token"), null);
    assertEquals(200, auth.getCode());
    Long clientId = Aop.get(MossKbAuthService.class).getIdByToken(String.valueOf(auth.getData()));
    assertNotNull(clientId);

    Long applicationId = row.getLong("application_id");
    RespBodyVo profile = Aop.get(MiniAppChatService.class).profile(applicationId, clientId);
    assertTrue(profile.isOk());
    MiniAppApplicationVo application = (MiniAppApplicationVo) profile.getData();
    assertEquals(String.valueOf(applicationId), application.getId());

    holdRequestContext(clientId);
    RespBodyVo opened = Aop.get(MiniAppChatService.class).openChat(applicationId, clientId);
    assertTrue(opened.isOk());
    MiniAppSessionVo session = (MiniAppSessionVo) opened.getData();
    assertNotNull(session.getChat_id());

    // 空问题必须被参数校验拦住，而不是把请求送进推理流程
    try {
      Aop.get(MiniAppChatService.class).chat(Long.valueOf(session.getChat_id()), clientId, new MiniAppChatRequestVo());
      throw new AssertionError("空问题应当触发参数校验异常");
    } catch (ParameterValidationException expected) {
      assertTrue(expected.getMessage().contains("message"));
    }
  }

  @Test
  public void unboundClientCannotReadProfileOrChat() {
    prepareDatabase();
    Row row = Db.findFirst(FIND_SCENE);
    if (row == null) {
      return;
    }
    Long applicationId = row.getLong("application_id");
    assertFalse(Aop.get(MiniAppChatService.class).profile(applicationId, null).isOk());
    assertFalse(Aop.get(MiniAppChatService.class).openChat(applicationId, null).isOk());
    RespBodyVo unknownChat = Aop.get(MiniAppChatService.class).chat(-1L, 1L,
        new MiniAppChatRequestVo().setMessage("你好"));
    assertFalse(unknownChat.isOk());
  }

  @Test
  public void qrCodeRequestIsValidatedBeforeCallingWeChat() {
    if (MiniAppWeChatClient.configured()) {
      // 配置了微信凭据时不在这里调用外部接口
      return;
    }
    RespBodyVo body = Aop.get(MiniAppQrCodeService.class).generate(1L, new MiniAppQrCodeRequestVo());
    assertFalse(body.isOk());
    assertTrue(body.getMsg().contains("未配置"));
  }

  @Test
  public void parameterValidationRejectsMissingText() {
    try {
      ParameterValidationUtils.requiredText(null, "message", 10);
      throw new AssertionError("必填文本为空时应当抛出参数校验异常");
    } catch (ParameterValidationException expected) {
      assertTrue(expected.getMessage().contains("message"));
    }
  }
}
