package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;

import com.jfinal.kit.Kv;

import lombok.extern.slf4j.Slf4j;
import nexus.io.db.activerecord.Db;
import nexus.io.jfinal.aop.Aop;
import nexus.io.db.activerecord.Row;
import nexus.io.mosskb.constant.MossKbTableNames;
import nexus.io.mosskb.vo.MossKbDocumentSplitTaskVo;
import nexus.io.model.upload.UploadResult;
import nexus.io.tio.utils.json.JsonUtils;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

/**
 * 文档分段任务的进度与结果。
 *
 * <p>上传接口只负责建任务，解析在后台线程里按页推进。进度写库要足够轻，所以只在整份文档完成、
 * 失败或 5% 的步进上更新一次，前端按固定间隔轮询就能看到推进过程。
 */
@Slf4j
public class MossKbDocumentSplitTaskService {

  public static final String STATUS_RUNNING = "running";
  public static final String STATUS_SUCCESS = "success";
  public static final String STATUS_FAILED = "failed";

  /** 每推进这么多页才写一次进度，避免逐页写库。 */
  private static final int PROGRESS_STEP = 5;

  /** 百分比每前进这么多点也写一次，保证页数少的文档同样能看到进度。 */
  private static final int PROGRESS_PERCENT_STEP = 5;

  private static final String FIND_TASK = """
      select id,
             file_name,
             file_size,
             status,
             progress,
             total,
             result,
             error_message
        from moss_kb_document_split_task
       where id = ?
         and user_id = ?
         and deleted = 0
      """;

  /** 创建任务，返回任务 id 供前端轮询。 */
  public Long start(Long userId, UploadResult uploadResult, long fileSize) {
    Long taskId = SnowflakeIdUtils.id();
    Row row = Row.by("id", taskId)
        //
        .set("user_id", userId)
        //
        .set("file_id", uploadResult.getId())
        //
        .set("file_name", uploadResult.getName())
        //
        .set("file_size", fileSize)
        //
        .set("status", STATUS_RUNNING)
        //
        .set("progress", 0)
        //
        .set("total", 0);
    Db.save(MossKbTableNames.moss_kb_document_split_task, row);
    return taskId;
  }

  /** 记录总页数，非分页文档按 1 页处理。 */
  public void markTotal(Long taskId, int total) {
    Db.update("update moss_kb_document_split_task set total=?, update_time=now() where id=?", Math.max(total, 1),
        taskId);
  }

  /** 记录已完成页数。 */
  public void markProgress(Long taskId, int completed, int total) {
    if (total <= 0) {
      return;
    }
    int percent = (int) Math.min(99, Math.round(completed * 100.0 / total));
    boolean lastPage = completed >= total;
    // 页数多时按页步进节流，页数少时按百分比节流，两种情况都能看到推进。
    boolean reachStep = completed % PROGRESS_STEP == 0
        || percent >= currentPercent(taskId) + PROGRESS_PERCENT_STEP;
    if (!lastPage && !reachStep) {
      return;
    }
    Db.update("update moss_kb_document_split_task set progress=?, update_time=now() where id=?", percent, taskId);
  }

  /** 读一次当前进度百分比，用于按百分比节流；按主键查询，代价可以忽略。 */
  private int currentPercent(Long taskId) {
    Integer percent = Db.queryInt("select progress from moss_kb_document_split_task where id=?", taskId);
    return percent == null ? -PROGRESS_PERCENT_STEP : percent;
  }

  /** 写入分段结果并把任务置为成功。 */
  public void complete(Long taskId, List<Kv> results) {
    String json = JsonUtils.toJson(results == null ? new ArrayList<>() : results);
    Db.update("update moss_kb_document_split_task set status=?, progress=100, result=?::jsonb, update_time=now() where id=?",
        STATUS_SUCCESS, json, taskId);
    Aop.get(BackgroundImportService.class).dispatch(taskId);
  }

  /** 记录失败原因并把任务置为失败。 */
  public void fail(Long taskId, String message) {
    String reason = message == null || message.isBlank() ? "文档解析失败" : message;
    if (reason.length() > 1000) {
      reason = reason.substring(0, 1000);
    }
    log.warn("document split task {} failed: {}", taskId, reason);
    Db.update("update moss_kb_document_split_task set status=?, error_message=?, update_time=now() where id=?",
        STATUS_FAILED, reason, taskId);
    Db.update("""
        update moss_kb_document_split_task set import_status = 'failed', import_error = ?
        where id = ? and import_status = 'queued'
        """, reason, taskId);
  }

  /** 查询任务当前状态，任务不存在或不属于该用户时返回 null。 */
  public MossKbDocumentSplitTaskVo get(Long userId, Long taskId) {
    Row row = Db.findFirst(FIND_TASK, taskId, userId);
    if (row == null) {
      return null;
    }
    MossKbDocumentSplitTaskVo vo = new MossKbDocumentSplitTaskVo();
    vo.setTask_id(row.getLong("id"));
    vo.setStatus(row.getStr("status"));
    Integer progress = row.getInt("progress");
    vo.setProgress(progress == null ? 0 : progress);
    Integer total = row.getInt("total");
    vo.setTotal(total == null ? 0 : total);
    vo.setFile_name(row.getStr("file_name"));
    vo.setFile_size(row.getLong("file_size"));
    vo.setErrorMessage(row.getStr("error_message"));
    if (STATUS_SUCCESS.equals(vo.getStatus())) {
      String result = jsonText(row.get("result"));
      if (result != null && !result.isBlank()) {
        vo.setResult(JsonUtils.parseArray(result, Kv.class));
      }
    }
    return vo;
  }

  /** jsonb 列可能以 PGobject 或 jsonb::text 返回，统一取出 JSON 字符串。 */
  private String jsonText(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof org.postgresql.util.PGobject pgObject) {
      return pgObject.getValue();
    }
    return String.valueOf(value);
  }
}
