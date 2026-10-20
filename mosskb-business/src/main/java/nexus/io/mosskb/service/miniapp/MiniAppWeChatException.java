package nexus.io.mosskb.service.miniapp;

/**
 * 微信小程序接口调用失败。原因已经整理成可以直接回显给用户的文本，
 * 调用方捕获后转成失败响应即可。
 */
public class MiniAppWeChatException extends RuntimeException {

  private static final long serialVersionUID = 1L;

  public MiniAppWeChatException(String message) {
    super(message);
  }
}
