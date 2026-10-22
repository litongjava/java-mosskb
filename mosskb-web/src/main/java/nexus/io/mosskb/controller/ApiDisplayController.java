package nexus.io.mosskb.controller;

import nexus.io.annotation.RequestPath;
import nexus.io.mosskb.vo.MossKbUiTheme;
import nexus.io.model.result.ResultVo;

@RequestPath("/api/display")
public class ApiDisplayController {

  public ResultVo info() {
    String title = "MossKB";
    String slogan = "欢迎使用 MossKB 智能知识库问答系统";
    String userManualUrl = "https://docs.mosskb.cn/";
    String forumUrl = "https://github.com/litongjava/java-mosskb/discussions";
    String projectUrl = "https://github.com/litongjava/java-mosskb";
    MossKbUiTheme mossKbUiTheme = new MossKbUiTheme("#3370FF", "", "", "", title, slogan, true, userManualUrl, true,
        forumUrl, true, projectUrl);
    return ResultVo.ok(mossKbUiTheme);
  }
}
