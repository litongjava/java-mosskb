package nexus.io.mosskb.service.kb;

/**
 * 聊天过程事件的输出通道。SSE 场景把事件实时推给浏览器，小程序等一次性返回的场景
 * 只关心"回答是否结束"，因此把推送动作从聊天流程里抽出来，流程本身不再依赖连接对象。
 */
public interface ChatEventSink {

  /** 具名事件，例如 agent_status（检索进度）、error（失败原因）。 */
  void event(String name, String payload);

  /** 回答正文增量或结束标记，与前端约定的数据帧同构。 */
  void chunk(String payload);

  /** 回答结束，正常结束与失败都会调用，实现方在这里释放连接或唤醒等待方。 */
  void finish();
}
