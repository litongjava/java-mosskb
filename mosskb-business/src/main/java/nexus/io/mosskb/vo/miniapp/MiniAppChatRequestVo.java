package nexus.io.mosskb.vo.miniapp;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 小程序提问请求，字段固定因此使用实体类。 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Accessors(chain = true)
public class MiniAppChatRequestVo {
  private String message;
  /** 指定模型名称，留空表示按应用配置处理。 */
  private String model;
}
