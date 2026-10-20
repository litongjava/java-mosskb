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
  /** 扫码后进入的小程序页面，留空时使用配置里的默认页面。 */
  private String page;
  /** 是否校验页面已发布：开发阶段传 false，才能扫开发版/体验版。 */
  private Boolean check_path;
  /** release、trial 或 develop，留空时使用配置里的默认环境。 */
  private String env_version;
  /** 二维码边长，微信支持 280 到 1280。 */
  private Integer width;
}
