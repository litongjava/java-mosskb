package nexus.io.mosskb.controller;

import nexus.io.annotation.Get;
import nexus.io.annotation.RequestPath;
import nexus.io.db.activerecord.Db;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.boot.http.TioRequestContext;

@RequestPath("/api/valid")
public class ApiValidController {

  /** Active-account lookup used by the "create user" entry check. */
  private static final String ACTIVE_ROLE = """
      select role
      from moss_kb_user
      where id = ?
        and deleted = 0
        and is_active = true
      """;

  @Get("/user/{size}")
  public ResultVo users(Integer size) {
    Long userId = TioRequestContext.getUserIdLong();
    String role = Db.queryStr(ACTIVE_ROLE, userId);
    if ("ADMIN".equalsIgnoreCase(role) || "SUPER_ADMIN".equalsIgnoreCase(role)) {
      return ResultVo.ok(true);
    }
    return ResultVo.fail("仅管理员可以创建用户");
  }

  /**
   * 社区版最多支持 50 个知识库,我这里设置为无限
   * @return
   */
  @Get("/dataset/{size}")
  public ResultVo dataset50(Integer size) {
    return ResultVo.ok(true);
  }

  @Get("/application/{size}")
  public ResultVo applicaiton5(Integer size) {
    return ResultVo.ok(true);
  }
}
