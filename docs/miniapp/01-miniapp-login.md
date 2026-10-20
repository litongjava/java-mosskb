# 微信小程序：扫码登录与 scene 解析

小程序没有账号体系，用户扫到某个智能提示的小程序码后应当直接进入该智能提示的对话。这篇文档说明服务端如何把「小程序码 -> 智能提示 -> 访客令牌」串起来。

## 设计思路

- 每个智能提示在后台都有一条公开访问记录，记录里的 `access_token` 就是分享链接用的短令牌。
- 小程序码的 `scene` 直接写入这个短令牌，扫码等价于打开分享链接，不需要额外维护一套映射表。
- 访客令牌沿用分享页的签发逻辑：第一次进入登记一个访客并签发长期令牌，同一设备再次进入复用原令牌。
- 因此公开访问设置的启停、每日次数限制、重置令牌，对小程序和网页分享链接同时生效。

scene 采用短令牌还有一个好处：微信要求 scene 不超过 32 个字符，而短令牌本身就是一个不超过 19 位的十进制数字，天然满足限制。

## 涉及的角色

| 角色 | 职责 |
| --- | --- |
| 场景服务 | 按 scene 找到智能提示，返回应用标识与公开访问令牌 |
| 微信客户端 | 用 `wx.login` 的 code 换取 openid，生成小程序码 |
| 登录服务 | 校验 scene 与 code，登记访客并签发令牌 |
| 登录接口 | 一个接口一个处理器，只做参数装配与响应输出 |

## 接口

### POST /api/miniapp/auth/login

请求体字段固定，因此使用实体类承载：

```json
{
  "code": "wx.login 返回的临时登录凭证",
  "scene": "小程序码里的 scene",
  "token": "设备上已有的令牌，可选"
}
```

响应体是统一的 `RespBodyVo`：

```json
{
  "code": 1,
  "msg": null,
  "data": {
    "token": "长期令牌",
    "client_id": "访客标识",
    "application_id": "智能提示标识",
    "application_name": "智能提示名称",
    "expires_in": 604800,
    "dev_mode": false
  }
}
```

失败时 `code` 为 `0`，`msg` 是可以直接展示给用户的中文原因，例如 `小程序码无效，或该智能提示已停止对外访问`。

## 请求实体

字段已知，用实体类而不是散落的 Map：

```java
package nexus.io.mosskb.vo.miniapp;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 小程序登录请求：code 来自 wx.login，scene 来自小程序码。 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Accessors(chain = true)
public class MiniAppLoginRequestVo {
  private String code;
  private String scene;
  private String token;
}
```

## 处理器

一个接口对应一个处理器，处理器只负责取参数、调用服务、写响应。参数校验交给统一工具类，令牌校验交给拦截器，处理器里看不到这两件事的实现细节：

```java
package nexus.io.mosskb.handler.miniapp;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.miniapp.MiniAppAuthService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.miniapp.MiniAppLoginRequestVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;

/** POST /api/miniapp/auth/login 小程序访客登录。 */
public class MiniAppLoginHandler {

  public HttpResponse handle(HttpRequest request) {
    MiniAppLoginRequestVo input = ParameterValidationUtils.body(request, MiniAppLoginRequestVo.class);
    RespBodyVo body = Aop.get(MiniAppAuthService.class).login(input);
    return TioRequestContext.getResponse().respond(body);
  }
}
```

路由注册使用 `HttpRequestRouter#post`：

```java
package nexus.io.mosskb.config;

import nexus.io.mosskb.handler.miniapp.MiniAppLoginHandler;
import nexus.io.tio.boot.server.TioBootServer;
import nexus.io.tio.http.server.router.HttpRequestRouter;

public class MiniAppHandlerConfiguration {

  public void config() {
    HttpRequestRouter router = TioBootServer.me().getRequestRouter();
    if (router == null) {
      return;
    }
    MiniAppLoginHandler loginHandler = new MiniAppLoginHandler();
    router.post("/api/miniapp/auth/login", loginHandler::handle);
  }
}
```

## 服务实现要点

```java
package nexus.io.mosskb.service.miniapp;

import com.alibaba.fastjson2.JSONObject;

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

public class MiniAppAuthService {

  private final MiniAppWeChatClient wechatClient = new MiniAppWeChatClient();

  public RespBodyVo login(MiniAppLoginRequestVo input) {
    if (input == null || StrUtil.isBlank(input.getScene())) {
      return RespBodyVo.fail("缺少 scene，请从小程序码进入");
    }
    SceneApplication scene = Aop.get(MiniAppSceneService.class).resolve(input.getScene());
    if (scene == null) {
      return RespBodyVo.fail("小程序码无效，或该智能提示已停止对外访问");
    }
    // 校验微信凭证（配置了小程序凭据时），随后复用公开访问链接的登记逻辑
    ResultVo auth = Aop.get(MossKbApplicationAccessTokenService.class)
        .authentication(scene.accessToken(), input.getToken());
    if (auth.getCode() != 200 || auth.getData() == null) {
      return RespBodyVo.fail(auth.getMessage() == null ? "登录失败" : auth.getMessage());
    }
    String token = String.valueOf(auth.getData());
    Long clientId = Aop.get(MossKbAuthService.class).getIdByToken(token);
    if (clientId == null) {
      return RespBodyVo.fail("登录失败，请重试");
    }
    MiniAppLoginVo data = new MiniAppLoginVo()
        .setToken(token)
        .setClient_id(String.valueOf(clientId))
        .setApplication_id(String.valueOf(scene.applicationId()));
    return RespBodyVo.ok(data);
  }
}
```

几个刻意的选择：

- 应用标识一律以字符串返回。智能提示标识是雪花 id，超过前端安全整数范围，用字符串传输可以避免精度丢失。
- 访客登记复用公开访问链接已有逻辑，因此同一台设备重复进入不会不断产生新访客，每日次数限制也不会被绕过。
- 服务返回 `RespBodyVo` 而不是抛异常表达业务失败，调用方能直接把它写成响应体。

## 本地开发与生产环境的差别

| 场景 | 行为 |
| --- | --- |
| 已配置小程序凭据 | 必须携带 `code`，服务端调用微信接口换取 openid 后才签发令牌 |
| 未配置小程序凭据且开启本地直登 | 允许只带 `scene` 登录，方便本地联调 |
| 未配置小程序凭据且未开启本地直登 | 直接返回失败，避免把未鉴权的入口带到线上 |

本地直登由配置项 `wechat.miniapp.dev-login` 控制，默认只在本地开发运行（源码目录直接启动）时放行；打包后的运行环境必须显式打开该配置才会生效，正式环境请保持关闭。

## 拦截器配置

首次进入小程序时没有任何令牌，因此登录接口需要放行：

```java
package nexus.io.mosskb.config;

import nexus.io.tio.boot.http.interceptor.HttpInteceptorConfigure;
import nexus.io.tio.boot.http.interceptor.HttpInterceptorModel;
import nexus.io.mosskb.inteceptor.MossKbAuthInterceptor;
import nexus.io.tio.boot.server.TioBootServer;

public class MossKbInterceptorConfiguration {

  public void config() {
    MossKbAuthInterceptor authTokenInterceptor = new MossKbAuthInterceptor();
    HttpInterceptorModel model = new HttpInterceptorModel();
    model.setInterceptor(authTokenInterceptor);
    model.addBlockUrl("/**");
    // 小程序首次进入还没有令牌，只放行换取令牌这一步
    model.addAllowUrls("/api/miniapp/auth/login");
    HttpInteceptorConfigure configure = new HttpInteceptorConfigure();
    configure.add(model);
    TioBootServer.me().setHttpInteceptorConfigure(configure);
  }
}
```

其余小程序接口需要携带访客令牌，令牌校验统一在拦截器里完成，处理器不再各自判断登录状态。

## 一次完整的扫码登录

1. 用户用微信扫描智能提示的小程序码，微信打开小程序页面，并把 `scene` 交给页面。
2. 小程序调用 `uni.login` 拿到 code，连同 scene 一起请求登录接口。
3. 服务端按 scene 找到智能提示与公开访问令牌，校验微信 code，登记访客并签发令牌。
4. 小程序把令牌与 `application_id` 写入本地缓存，后续请求都带上该令牌。
5. 用户看到智能提示的名称、描述与开场白，可以直接提问。
