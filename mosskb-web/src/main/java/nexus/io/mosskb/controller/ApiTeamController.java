package nexus.io.mosskb.controller;

import nexus.io.annotation.RequestPath;
import nexus.io.model.result.ResultVo;


public class ApiTeamController {

  @RequestPath("/member")
  public ResultVo member() {
    return ResultVo.ok();
  }
}
