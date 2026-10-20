package nexus.io.mosskb.vo.miniapp;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 小程序登录结果：后续接口都用 token 作为 Bearer 凭证。 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Accessors(chain = true)
public class MiniAppLoginVo {
  private String token;
  /** 访客标识，用字符串传输避免前端大整数精度丢失。 */
  private String client_id;
  private String application_id;
  private String application_name;
  /** 令牌有效期，单位秒。 */
  private Integer expires_in;
  /** 未配置微信凭据、按本地调试放行时为 true。 */
  private Boolean dev_mode;
}
