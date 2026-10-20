package nexus.io.mosskb.vo.miniapp;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 小程序里的智能提示资料，只暴露分享页需要的字段。 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Accessors(chain = true)
public class MiniAppApplicationVo {
  private String id;
  private String name;
  private String description;
  /** 开场白，进入会话时作为助手的第一条消息。 */
  private String prologue;
  private Integer dialogue_number;
  private String icon;
  private Boolean show_source;
}
