package nexus.io.mosskb.service.kb;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import com.alibaba.fastjson2.JSONObject;

import lombok.extern.slf4j.Slf4j;
import nexus.io.tio.utils.json.FastJson2Utils;

/**
 * 一次性返回的通道：调用方发起提问后等待回答结束，再统一取结果。
 * 回答正文仍以数据库记录为准，这里收集的文本只作为写入延迟时的兜底。
 */
@Slf4j
public class BlockingChatEventSink implements ChatEventSink {

  private final CountDownLatch finished = new CountDownLatch(1);
  private final StringBuilder answer = new StringBuilder();
  private volatile String error;

  /** 等待回答结束，超时返回 false，由调用方决定如何回话。 */
  public boolean await(long timeoutMillis) {
    try {
      return finished.await(timeoutMillis, TimeUnit.MILLISECONDS);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return false;
    }
  }

  public String answer() {
    return answer.toString();
  }

  public String error() {
    return error;
  }

  public boolean hasError() {
    return error != null;
  }

  @Override
  public void event(String name, String payload) {
    if ("error".equals(name)) {
      error = payload;
    }
  }

  @Override
  public void chunk(String payload) {
    JSONObject json = parse(payload);
    if (json == null) {
      return;
    }
    String content = json.getString("content");
    if (content != null && !content.isEmpty()) {
      answer.append(content);
    }
  }

  @Override
  public void finish() {
    finished.countDown();
  }

  private JSONObject parse(String payload) {
    try {
      return FastJson2Utils.parseObject(payload);
    } catch (Exception e) {
      log.warn("ignore unexpected chat chunk: {}", payload);
      return null;
    }
  }
}
