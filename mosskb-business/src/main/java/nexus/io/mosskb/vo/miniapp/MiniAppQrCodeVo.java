package nexus.io.mosskb.vo.miniapp;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 小程序码结果：直接给出 base64 图片，管理端不用再转发一次二进制流。 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Accessors(chain = true)
public class MiniAppQrCodeVo {
  private String application_id;
  private String application_name;
  /** 写进小程序码的 scene，扫码后由小程序读取并解析应用。 */
  private String scene;
  private String page;
  private String env_version;
  private String content_type;
  private String image_base64;
}
