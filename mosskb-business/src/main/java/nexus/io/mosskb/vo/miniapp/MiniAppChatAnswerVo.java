package nexus.io.mosskb.vo.miniapp;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 小程序一轮问答的结果，一次请求返回完整回答。 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Accessors(chain = true)
public class MiniAppChatAnswerVo {
  private String chat_id;
  /** 本轮问答记录标识，可用于后续点赞、查看引用。 */
  private String message_id;
  private String answer;
  private String model;
  /** 回答是否因为等待超时而未取到，true 时 answer 可能为空。 */
  private Boolean timeout;
}
