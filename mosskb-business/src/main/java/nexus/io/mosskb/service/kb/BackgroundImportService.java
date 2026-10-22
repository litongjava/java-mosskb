package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;
import com.jfinal.kit.Kv;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.model.body.RespBodyVo;
import nexus.io.model.result.ResultVo;
import nexus.io.mosskb.model.BackgroundImportRequest;
import nexus.io.mosskb.utils.ExecutorServiceUtils;
import nexus.io.mosskb.vo.Paragraph;
import nexus.io.mosskb.vo.ParagraphBatchVo;
import nexus.io.tio.utils.json.JsonUtils;
import nexus.io.tio.utils.validator.ParameterValidator;

public class BackgroundImportService {
  public RespBodyVo submit(Long owner, Long dataset, BackgroundImportRequest input) {
    ParameterValidator.require(DatasetAccess.owns(owner, dataset), "知识库不存在或无权访问");
    ParameterValidator.require(input != null && input.getTaskIds() != null
        && !input.getTaskIds().isEmpty() && input.getTaskIds().size() <= 100, "请选择已上传的文档");
    List<Long> ids = input.getTaskIds().stream().distinct().sorted().toList();
    Db.tx(() -> {
      for (Long id : ids) {
        Row task = Db.findFirst("""
            select * from moss_kb_document_split_task where id = ? and user_id = ? and deleted = 0 for update
            """, id, owner);
        ParameterValidator.require(task != null, "解析任务不存在或无权访问");
        ParameterValidator.require(!"failed".equals(task.getStr("status")), "文档解析失败，请重新上传");
        Long target = task.getLong("import_dataset_id");
        ParameterValidator.require(target == null || target.equals(dataset), "任务已提交至其他知识库");
        if (target == null) {
          Db.update("""
              update moss_kb_document_split_task set import_dataset_id = ?, import_status = 'queued', update_time = now()
              where id = ?
              """, dataset, id);
        }
      }
      return true;
    });
    for (Long id : ids) {
      dispatch(id);
    }
    return RespBodyVo.ok();
  }

  public void dispatch(Long id) {
    ExecutorServiceUtils.getDocumentParseExecutor().execute(() -> run(id));
  }

  public void run(Long id) {
    int claimed = Db.update("""
        update moss_kb_document_split_task set import_status = 'importing', update_time = now()
        where id = ? and status = 'success' and import_status = 'queued'
        """, id);
    if (claimed == 0) {
      return;
    }
    try {
      Row task = Db.findFirst("""
          select user_id, import_dataset_id, result::text as payload
          from moss_kb_document_split_task where id = ?
          """, id);
      List<Kv> files = JsonUtils.parseArray(task.getStr("payload"), Kv.class);
      List<ParagraphBatchVo> documents = new ArrayList<>();
      for (Kv file : files) {
        List<Paragraph> paragraphs = JsonUtils.parseArray(JsonUtils.toJson(file.get("content")), Paragraph.class);
        String name = file.getStr("name");
        documents.add(new ParagraphBatchVo().setId(file.getLong("id"))
            .setName(name.length() > 128 ? name.substring(0, 128) : name).setParagraphs(paragraphs));
      }
      ResultVo result = importDocuments(task.getLong("user_id"),
          task.getLong("import_dataset_id"), documents);
      if (result.getCode() != 200) {
        throw new IllegalStateException(result.getMessage());
      }
      Db.update("""
          update moss_kb_document_split_task set import_status = 'success', import_error = null, update_time = now() where id = ?
          """, id);
    } catch (Exception e) {
      String error = e.getMessage() == null ? "导入失败，请重新上传" : e.getMessage();
      Db.update("""
          update moss_kb_document_split_task set import_status = 'failed', import_error = ?, update_time = now() where id = ?
          """, error.substring(0, Math.min(1000, error.length())), id);
    }
  }

  protected ResultVo importDocuments(Long owner, Long dataset, List<ParagraphBatchVo> documents) {
    return Aop.get(MossKbParagraphSplitService.class).batch(owner, dataset, documents);
  }

  /** On a single-instance restart, never leave interrupted work displayed as running. */
  public void recover() {
    Db.update("""
        update moss_kb_document_split_task
        set import_status = 'failed', import_error = '服务重启中断了任务，请重新上传', update_time = now()
        where import_status = 'importing' or (import_status = 'queued' and status = 'running')
        """);
    for (Long id : Db.<Long>query("""
        select id from moss_kb_document_split_task where import_status = 'queued' and status = 'success'
        """)) {
      dispatch(id);
    }
  }

  public RespBodyVo list(Long owner, Long dataset) {
    ParameterValidator.require(DatasetAccess.owns(owner, dataset), "知识库不存在或无权访问");
    List<Kv> tasks = new ArrayList<>();
    for (Row row : Db.find("""
        select id::text, file_name, status as parse_status, progress, import_status,
               coalesce(import_error, error_message) as error_message
        from moss_kb_document_split_task
        where user_id = ? and import_dataset_id = ? and deleted = 0
        order by create_time desc limit 100
        """, owner, dataset)) {
      tasks.add(row.toKv());
    }
    return RespBodyVo.ok(tasks);
  }
}
