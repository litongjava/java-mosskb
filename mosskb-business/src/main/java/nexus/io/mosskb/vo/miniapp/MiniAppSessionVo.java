package nexus.io.mosskb.vo.miniapp;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 新建会话的结果。 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Accessors(chain = true)
public class MiniAppSessionVo {
  private String chat_id;
  private String application_id;
}
