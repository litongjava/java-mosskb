package nexus.io.mosskb.handler;

import lombok.extern.slf4j.Slf4j;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.boot.exception.TioBootExceptionHandler;
import nexus.io.tio.core.ChannelContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.model.exception.ParameterValidationException;
import nexus.io.tio.websocket.common.WebSocketRequest;

@Slf4j
public class GlobalExceptionHandler implements TioBootExceptionHandler {

  /** 参数校验失败的业务码，与 HTTP 语义一致，方便前端区分参数问题和系统问题。 */
  private static final int INVALID_PARAMETER_CODE = 400;

  @Override
  public ResultVo handler(HttpRequest request, Throwable e) {
    // 参数校验异常是可预期的调用方问题：只回显原因，不打印完整堆栈
    if (e instanceof ParameterValidationException) {
      return ResultVo.fail(INVALID_PARAMETER_CODE, e.getMessage());
    }
    ResultVo result = ResultVo.fail(e.getMessage());
    // 其余异常仍需保留堆栈，便于排查
    log.error("request failed: {}", request == null ? "" : request.requestLine, e);
    return result;
  }

  @Override
  public Object wsTextHandler(WebSocketRequest webSokcetRequest, String text, ChannelContext channelContext, HttpRequest httpRequest, Throwable e) {
    return null;
  }

  @Override
  public Object wsBytesHandler(WebSocketRequest webSokcetRequest, byte[] bytes, ChannelContext channelContext, HttpRequest httpRequest, Throwable e) {
    return null;
  }
}
