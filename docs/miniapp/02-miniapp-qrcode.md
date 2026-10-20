# 微信小程序：智能提示小程序码

需求是「每个智能提示都有自己的小程序码，扫码直接和它对话」。这篇文档说明小程序码的生成方式、参数含义和排查方法。

## 为什么用小程序码而不是普通二维码

- 微信小程序码由微信官方接口生成，扫码后微信直接打开指定小程序页面，不需要先跳浏览器。
- `scene` 参数可以承载我们自己的业务标识，扫码后由小程序读取，因此一张码就能定位一个智能提示。
- 每个智能提示的码互相独立，运营可以把码放进海报、课件、文档或者聊天窗口。

## 生成流程

1. 管理端选择智能提示，点击生成小程序码。
2. 服务端校验当前账号是否有该智能提示的管理权限。
3. 取该智能提示当前的公开访问令牌作为 `scene`。
4. 调用微信官方接口生成小程序码，返回 base64 图片。
5. 管理端展示、下载或复制 scene。

## 接口

### POST /api/miniapp/admin/qrcode

需要后台账号令牌，并且只能是该智能提示的所有者或管理员。

```json
{
  "application_id": "智能提示标识，字符串",
  "page": "pages/index/index",
  "env_version": "develop",
  "check_path": false,
  "width": 430
}
```

响应：

```json
{
  "code": 1,
  "data": {
    "application_id": "智能提示标识",
    "application_name": "智能提示名称",
    "scene": "写到小程序码里的场景值",
    "page": "pages/index/index",
    "env_version": "develop",
    "content_type": "image/png",
    "image_base64": "iVBORw0KGgo..."
  }
}
```

直接返回 base64 有两个好处：管理端不用再发一次二进制请求；小程序端如果要做「分享给朋友」也可以复用同一份数据。

## 请求实体

```java
package nexus.io.mosskb.vo.miniapp;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 小程序码生成请求，由管理端填写。 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Accessors(chain = true)
public class MiniAppQrCodeRequestVo {
  /** 应用标识用字符串传输，避免前端大整数精度丢失。 */
  private String application_id;
  private String page;
  /** 是否校验页面已发布：开发阶段传 false，才能扫开发版/体验版。 */
  private Boolean check_path;
  private String env_version;
  /** 二维码边长，微信支持 280 到 1280。 */
  private Integer width;
}
```

## 处理器

```java
package nexus.io.mosskb.handler.miniapp;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.miniapp.MiniAppQrCodeService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.miniapp.MiniAppQrCodeRequestVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;

/** POST /api/miniapp/admin/qrcode 管理端生成智能提示的小程序码。 */
public class MiniAppQrCodeHandler {

  public HttpResponse handle(HttpRequest request) {
    MiniAppQrCodeRequestVo input = ParameterValidationUtils.body(request, MiniAppQrCodeRequestVo.class);
    Long userId = TioRequestContext.getUserIdLong();
    RespBodyVo body = Aop.get(MiniAppQrCodeService.class).generate(userId, input);
    return TioRequestContext.getResponse().respond(body);
  }
}
```

## 服务实现要点

```java
package nexus.io.mosskb.service.miniapp;

import java.util.Base64;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.kb.ApplicationAccess;
import nexus.io.mosskb.vo.miniapp.MiniAppQrCodeRequestVo;
import nexus.io.mosskb.vo.miniapp.MiniAppQrCodeVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.utils.hutool.StrUtil;
import nexus.io.tio.utils.validator.ParameterValidator;

public class MiniAppQrCodeService {

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
    byte[] image = wechatClient.unlimitedQrCode(scene, page(input.getPage()), false, "develop", 430);
    MiniAppQrCodeVo data = new MiniAppQrCodeVo()
        .setScene(scene)
        .setContent_type("image/png")
        .setImage_base64(Base64.getEncoder().encodeToString(image));
    return RespBodyVo.ok(data);
  }
}
```

权限判断放在服务层，处理器不需要关心；参数校验用统一工具类，非法参数会被全局异常处理器转成清晰的错误响应。

## 应用凭据与令牌缓存

小程序码依赖微信的接口调用凭证，凭证由小程序的 appid 与 secret 换取。这两项只从配置读取，不写进代码：

```java
package nexus.io.mosskb.service.miniapp;

import nexus.io.tio.utils.environment.EnvUtils;
import nexus.io.tio.utils.hutool.StrUtil;

public class MiniAppWeChatClient {

  public static boolean configured() {
    return StrUtil.isNotBlank(appId()) && StrUtil.isNotBlank(secret());
  }

  public static String appId() {
    return EnvUtils.get("wechat.miniapp.appid");
  }

  public static String secret() {
    return EnvUtils.get("wechat.miniapp.secret");
  }
}
```

配置项：

| 配置项 | 说明 | 默认值 |
| --- | --- | --- |
| `wechat.miniapp.appid` | 小程序 appid，也可用同名大写下划线形式的环境变量注入 | 空 |
| `wechat.miniapp.secret` | 小程序 secret，建议只通过环境变量注入 | 空 |
| `wechat.miniapp.page` | 扫码后进入的小程序页面 | `pages/index/index` |
| `wechat.miniapp.env-version` | `release` 正式版、`trial` 体验版、`develop` 开发版 | 本地开发为 `develop`，其余为 `release` |

接口调用凭证在进程内缓存，并在过期前提前刷新，避免每次生成小程序码都请求一次凭证接口；微信对凭证获取有频率限制，缓存可以显著降低触发限制的概率。

## 参数约束

| 参数 | 约束 | 说明 |
| --- | --- | --- |
| `scene` | 最长 32 个字符 | 由公开访问令牌长度决定，短令牌天然满足 |
| `page` | 已存在的小程序页面路径，不带前导斜杠 | 留空时使用默认页面 |
| `env_version` | `release`、`trial`、`develop` | 只有正式版页面才需要开启页面校验 |
| `check_path` | 布尔值 | 开发版、体验版必须传 `false` |
| `width` | 280 到 1280 | 留空使用默认边长 |

## 常见问题

| 现象 | 原因与处理 |
| --- | --- |
| 返回「未配置微信小程序凭据」 | 缺少 appid 或 secret，检查配置与环境变量注入 |
| 返回微信错误 `41030` | 页面不存在，确认 `page` 的路径与小程序一致 |
| 返回微信错误 `40001` | 凭证无效，通常是 secret 填错或凭证被重置，重启服务后重新获取 |
| 扫码后提示页面不存在 | 页面尚未发布，把 `env_version` 改为 `develop` 或 `trial`，并确认 `check_path` 为 `false` |
| 扫码进入提示小程序码无效 | 分享令牌被重置或公开访问被停用，重新生成小程序码 |
| 管理端提示无权访问 | 当前账号不是该智能提示的所有者，也不是管理员 |

## 管理端使用

1. 进入智能提示详情，选择「微信小程序码」。
2. 按需要选择开发版、体验版或正式版，点击重新生成。
3. 下载图片或复制 scene，把图片放到需要分发的地方。
4. 重置公开访问链接后，旧的小程序码失效，需要重新生成。

## 与公开访问设置的关系

小程序码不引入新的授权数据，扫码等价于打开分享链接，因此：

- 关闭公开访问后，小程序码无法登录，也无法提问。
- 每日次数限制对扫码访客同样生效。
- 重置公开访问令牌后旧码失效，重新生成即可。
