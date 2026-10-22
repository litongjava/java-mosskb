package nexus.io.mosskb.vo;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

//{"username":"admin","password":"123456"}
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserLoginReqVo {
  private String username, password;
}
