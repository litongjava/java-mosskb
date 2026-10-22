package nexus.io.mosskb.service.kb;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.kit.RowUtils;
import nexus.io.model.result.ResultVo;

public class MossKbDatasetHitTestService {
  public ResultVo hitTest(Long user, Long datasetId, String question, Double threshold, Integer limit, String mode) {
    Row dataset = Db.findById("moss_kb_dataset", datasetId);
    if (user == null || dataset == null || (!user.equals(dataset.getLong("user_id")))) {
      return ResultVo.fail("知识库不存在或无权访问");
    }
    return ResultVo.ok(RowUtils.toKv(Aop.get(MossKbParagraphRetrieveService.class).searchRows(
        new Long[] { datasetId }, threshold == null ? 0f : threshold.floatValue(), limit, question, mode), false));
  }
}
