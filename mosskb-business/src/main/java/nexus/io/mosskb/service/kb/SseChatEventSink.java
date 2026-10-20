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
