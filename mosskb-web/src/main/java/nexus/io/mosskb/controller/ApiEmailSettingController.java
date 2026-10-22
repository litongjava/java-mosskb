package nexus.io.mosskb.controller;

import nexus.io.annotation.Get;
import nexus.io.annotation.RequestPath;
import nexus.io.model.result.ResultVo;


public class ApiEmailSettingController {

  @Get("")
  public ResultVo index() {
    return ResultVo.ok();
  }
}
