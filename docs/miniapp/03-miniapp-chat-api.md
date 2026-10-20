# 微信小程序：对话接口

小程序打开后要能像网页分享页一样提问并获得回答。网页分享页用的是流式推送，小程序侧要处理连接、分片解析和断线重连，成本偏高。这篇文档说明如何在不复制一套推理流程的前提下，给小程序提供一次性返回的回答。

## 思路：把「输出通道」从流程里抽出来

提问流程本身由检索、上下文压缩、模型调用、落库组成，和「回答怎么送到客户端」无关。原先这条流程直接持有连接对象并推送 SSE 分片，导致只有流式场景能用。

改造后流程只依赖一个输出通道接口：

```java
package nexus.io.mosskb.service.kb;

/**
 * 聊天过程事件的输出通道。SSE 场景把事件实时推给浏览器，小程序等一次性返回的场景
 * 只关心「回答是否结束」，因此把推送动作从聊天流程里抽出来。
 */
public interface ChatEventSink {

  /** 具名事件，例如 agent_status（检索进度）、error（失败原因）。 */
  void event(String name, String payload);

  /** 回答正文增量或结束标记。 */
  void chunk(String payload);

  /** 回答结束，正常结束与失败都会调用，实现方在这里释放连接或唤醒等待方。 */
  void finish();
}
```

两个实现覆盖两种场景：

```java
package nexus.io.mosskb.service.kb;

import nexus.io.tio.core.ChannelContext;
import nexus.io.tio.http.server.util.SseEmitter;

/** 浏览器分享页使用的通道：事件实时写入 SSE 连接。 */
public class SseChatEventSink implements ChatEventSink {

  private final ChannelContext channelContext;

  public SseChatEventSink(ChannelContext channelContext) {
    this.channelContext = channelContext;
  }

  @Override
  public void event(String name, String payload) {
    SseEmitter.pushSSEChunk(channelContext, name, payload);
  }

  @Override
  public void chunk(String payload) {
    SseEmitter.pushSSEChunk(channelContext, payload);
  }

  @Override
  public void finish() {
    SseEmitter.closeChunkConnection(channelContext);
  }
}
```

```java
package nexus.io.mosskb.service.kb;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** 一次性返回的通道：调用方发起提问后等待回答结束，再统一取结果。 */
public class BlockingChatEventSink implements ChatEventSink {

  private final CountDownLatch finished = new CountDownLatch(1);

  /** 等待回答结束，超时返回 false，由调用方决定如何回话。 */
  public boolean await(long timeoutMillis) {
    try {
      return finished.await(timeoutMillis, TimeUnit.MILLISECONDS);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return false;
    }
  }

  @Override
  public void finish() {
    finished.countDown();
  }
}
```

这样改动的好处：

- 一套检索与推理流程同时服务网页分享页和小程序，不存在两份实现走偏的问题。
- 小程序不需要处理 SSE：发起请求后等待返回，拿到完整回答。
- 需要新的输出方式（例如企业内部系统对接）时，只需要再实现一个通道。
- 回答结束一定会调用 `finish()`，等待方不会因为异常路径而永久挂起。

## 接口

### GET /api/miniapp/application/{applicationId}

携带访客令牌，返回小程序要展示的资料。

```json
{
  "code": 1,
  "data": {
    "id": "智能提示标识",
    "name": "智能提示名称",
    "description": "简介",
    "prologue": "开场白",
    "dialogue_number": 3,
    "icon": "图标地址",
    "show_source": false
  }
}
```

### POST /api/miniapp/chat/open/{applicationId}

新建一个会话，返回会话标识：

```json
{ "code": 1, "data": { "chat_id": "会话标识", "application_id": "智能提示标识" } }
```

### POST /api/miniapp/chat/{chatId}/message

```json
{ "message": "用户问题" }
```

返回：

```json
{
  "code": 1,
  "data": {
    "chat_id": "会话标识",
    "message_id": "本轮记录标识",
    "answer": "回答正文",
    "timeout": false
  }
}
```

`timeout` 为 `true` 表示等待超过了配置的上限，此时 `answer` 可能是已经生成的部分内容，客户端可以提示用户稍后在历史记录中查看。

## 处理器

```java
package nexus.io.mosskb.handler.miniapp;

import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.miniapp.MiniAppChatService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.miniapp.MiniAppChatRequestVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;

/** POST /api/miniapp/chat/{chatId}/message 一次性返回回答的提问接口。 */
public class MiniAppChatMessageHandler {

  public HttpResponse handle(HttpRequest request) {
    Long chatId = ParameterValidationUtils.pathId(request, "chatId");
    Long clientId = TioRequestContext.getUserIdLong();
    MiniAppChatRequestVo input = ParameterValidationUtils.body(request, MiniAppChatRequestVo.class);
    RespBodyVo body = Aop.get(MiniAppChatService.class).chat(chatId, clientId, input);
    return TioRequestContext.getResponse().respond(body);
  }
}
```

## 服务实现要点

```java
package nexus.io.mosskb.service.miniapp;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.kb.ApplicationAccess;
import nexus.io.mosskb.service.kb.BlockingChatEventSink;
import nexus.io.mosskb.service.kb.MossKbApplicationChatMessageService;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.mosskb.vo.MossKbChatRequestVo;
import nexus.io.mosskb.vo.miniapp.MiniAppChatAnswerVo;
import nexus.io.mosskb.vo.miniapp.MiniAppChatRequestVo;
import nexus.io.model.body.RespBodyVo;
import nexus.io.model.result.ResultVo;

public class MiniAppChatService {

  public RespBodyVo chat(Long chatId, Long clientId, MiniAppChatRequestVo input) {
    String message = ParameterValidationUtils.requiredText(input.getMessage(), "message", 8000);
    Row chat = Db.findFirst(FIND_CHAT, chatId);
    if (chat == null || Boolean.TRUE.equals(chat.getBoolean("is_deleted"))) {
      return RespBodyVo.fail("会话不存在，请重新进入");
    }
    Long applicationId = chat.getLong("application_id");
    if (!ApplicationAccess.canReadChat(clientId, applicationId, chatId)) {
      return RespBodyVo.fail("无权访问该会话");
    }

    MossKbChatRequestVo request = new MossKbChatRequestVo().setMessage(message).setRe_chat(false);
    BlockingChatEventSink sink = new BlockingChatEventSink();
    ResultVo started = Aop.get(MossKbApplicationChatMessageService.class).ask(sink, chatId, request);
    if (started.getCode() != 200) {
      return RespBodyVo.fail(started.getMessage() == null ? "提问失败" : started.getMessage());
    }
    boolean finished = sink.await(timeoutMillis());
    return RespBodyVo.ok(answer(chatId, sink, !finished));
  }
}
```

几个关键点：

- 会话归属在服务层再校验一次：只有创建该会话的访客，或者智能提示的所有者，才能提问。
- 回答以数据库记录为准，通道里收集到的正文只作为写入延迟时的兜底，避免返回空内容。
- 单条问题限制长度，超出直接由参数校验拦下，不进入推理流程。
- 等待上限由配置控制，避免请求长时间占用连接。

## 与网页分享页共用同一条流程

| 场景 | 输出通道 | 行为 |
| --- | --- | --- |
| 网页分享页 | `SseChatEventSink` | 回答逐字推送，带检索进度事件 |
| 微信小程序 | `BlockingChatEventSink` | 等回答结束，一次性返回正文 |

两条路径的检索、上下文、模型调用、落库完全一致，因此在网页里提问产生的历史记录，小程序打开同一会话也能看到，反之亦然。

## 响应格式

所有小程序接口都返回统一的响应体：

```json
{ "code": 1, "msg": null, "data": {} }
```

- `code` 为 `1` 表示成功，`0` 表示失败。
- `msg` 是可以直接展示给用户失败原因。
- 参数错误由全局异常处理器统一转换，返回 `code` 为 `400` 与具体原因。

## 小程序侧调用建议

- 提问是长耗时请求，需要在界面上给出「正在思考」的反馈，并在这段时间内禁用发送按钮，避免重复提交。
- 服务端对同一会话并发提问做了互斥，重复提交只会拿到「当前会话正在处理上一条问题」的提示。
- 所有标识都是字符串，前端不要转成数字再拼回请求，否则会精度丢失。
- 超时或失败时保留用户输入，方便直接重试。
