# 微信小程序接入

MossKB 的每个智能提示都可以生成一张独立的微信小程序码，用户用微信扫码后直接打开小程序，与该智能提示对话，不需要注册账号。

## 功能一览

| 功能 | 说明 | 文档 |
| --- | --- | --- |
| 扫码登录 | 小程序码里的 scene 定位智能提示，扫码即登记访客并签发令牌 | [扫码登录与 scene 解析](01-miniapp-login.md) |
| 小程序码生成 | 管理端为每个智能提示生成独立小程序码 | [智能提示小程序码](02-miniapp-qrcode.md) |
| 对话接口 | 小程序一次性拿到完整回答，与网页分享页共用同一条检索推理流程 | [对话接口](03-miniapp-chat-api.md) |
| 本地调试 | 未配置微信凭据时可以在本地直登联调 | [本地开发与调试](04-miniapp-local-debug.md) |
| 验证记录 | 编译、联调测试与真实服务请求的结果 | [验证记录](05-verification.md) |

## 整体链路

```
微信扫码 -> 小程序读取 scene -> 换取访客令牌 -> 读取智能提示资料
        -> 创建会话 -> 提问 -> 服务端检索知识库并调用模型 -> 返回回答
```

## 接口总表

| 方法 | 路径 | 鉴权 | 说明 |
| --- | --- | --- | --- |
| POST | `/api/miniapp/auth/login` | 无需令牌 | 用 scene 与微信 code 换取访客令牌 |
| GET | `/api/miniapp/application/{applicationId}` | 访客令牌 | 智能提示资料 |
| POST | `/api/miniapp/chat/open/{applicationId}` | 访客令牌 | 创建会话 |
| POST | `/api/miniapp/chat/{chatId}/message` | 访客令牌 | 提问并等待回答 |
| POST | `/api/miniapp/admin/qrcode` | 后台账号令牌 | 生成小程序码 |

## 为什么这样设计

- **不需要新的授权体系**：scene 直接使用智能提示的公开访问令牌，扫码等价于打开分享链接，公开访问的启停、每日次数限制、重置令牌同时生效。
- **不需要新的访客表**：访客登记复用公开访问链接已有逻辑，同一台设备重复进入只登记一次。
- **只有一套问答流程**：网页分享页与小程序共用检索、上下文压缩、模型调用与落库，历史记录互通。
- **一个接口一个处理器**：令牌校验在拦截器完成，参数校验由统一工具类与全局异常处理器完成，处理器只做参数装配与响应输出。

## 配置项

| 配置项 | 说明 |
| --- | --- |
| `wechat.miniapp.appid` | 小程序 appid |
| `wechat.miniapp.secret` | 小程序 secret，建议只通过环境变量注入 |
| `wechat.miniapp.page` | 扫码后进入的页面，默认 `pages/index/index` |
| `wechat.miniapp.env-version` | 生成小程序码的运行环境，`release`、`trial` 或 `develop` |
| `wechat.miniapp.dev-login` | 未配置微信凭据时是否允许本地直登，仅用于联调 |
| `wechat.miniapp.chat-timeout-ms` | 小程序等待回答的上限，单位毫秒 |

## 小程序工程

`mosskb-miniapp` 目录下是基于 uni-app 与 wot-design-uni 的微信小程序工程，扫码入口、资料展示、会话与聊天界面都在其中，构建与使用方式见该目录下的文档。
