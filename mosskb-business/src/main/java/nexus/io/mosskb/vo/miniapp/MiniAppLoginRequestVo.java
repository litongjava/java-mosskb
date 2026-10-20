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
  /** wx.login 返回的临时登录凭证；未配置微信凭据的本地调试可以为空。 */
  private String code;
  /** 小程序码携带的 scene，即应用的公开访问令牌。 */
  private String scene;
  /** 设备上已有的令牌，仍绑定同一应用时直接复用，避免每次进入都新建访客。 */
  private String token;
  /** 访客自定义的昵称等附加信息，字段不固定，保留给后续扩展。 */
  private String nick_name;
}
