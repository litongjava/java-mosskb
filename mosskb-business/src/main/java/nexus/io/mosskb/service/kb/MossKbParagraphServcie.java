package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;

import org.postgresql.util.PGobject;

import com.jfinal.kit.Kv;

import lombok.extern.slf4j.Slf4j;
import nexus.io.chat.PlatformInput;
import nexus.io.db.TableInput;
import nexus.io.db.TableResult;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.kit.RowUtils;
import nexus.io.mosskb.constant.MossKbTableNames;
import nexus.io.mosskb.model.MossKbParagraph;
import nexus.io.mosskb.vo.Paragraph;
import nexus.io.mosskb.vo.ResultPage;
import nexus.io.model.page.Page;
import nexus.io.model.result.ResultVo;
import nexus.io.table.services.ApiTable;
import nexus.io.tio.utils.crypto.Md5Utils;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

@Slf4j
public class MossKbParagraphServcie {
  private MossKbModelService mossKbModelService = Aop.get(MossKbModelService.class);

  public ResultVo page(Long userId, Long datasetId, Long documentId, Integer pageNo, Integer pageSize) {
    log.info("datasetId:{},documentId:{}", datasetId, documentId);
    TableInput tableInput = new TableInput();
    tableInput.setColumns("id,title,content,is_active,document_id,create_time,update_time");
    tableInput.set("dataset_id", datasetId).set("document_id", documentId);
    tableInput.setPageNo(pageNo).setPageSize(pageSize);

    TableResult<Page<Row>> tableResult = ApiTable.page(MossKbTableNames.moss_kb_paragraph, tableInput);
    Page<Row> page = tableResult.getData();
    int totalRow = page.getTotalRow();
    List<Row> records = page.getList();
    List<Kv> kvs = RowUtils.toKv(records, false);
    ResultPage<Kv> resultPage = new ResultPage<>(pageNo, pageSize, totalRow, kvs);
    return ResultVo.ok(resultPage);
  }

  public ResultVo listProblemByParagraphId(Long datasetId, Long documentId, Long paragraphId) {
    String sql = "select p.id,p.content,p.dataset_id from moss_kb_problem p JOIN moss_kb_problem_paragraph_mapping mapping on mapping.problem_id=p.id where mapping.paragraph_id=?";
    List<Row> records = Db.find(sql, paragraphId);
    List<Kv> kvs = RowUtils.toKv(records, false);
    return ResultVo.ok(kvs);
  }

  public ResultVo addProblemsById(Long datasetId, Long documentId, Long paragraphId, List<String> problems) {
    List<Row> problemRecords = new ArrayList<>();
    List<Row> mappings = new ArrayList<>();
    for (String str : problems) {
      long problemId = SnowflakeIdUtils.id();
      problemRecords.add(Row.by("id", problemId).set("dataset_id", datasetId).set("hit_num", 0).set("content", str));
      long mappingId = SnowflakeIdUtils.id();
      mappings.add(Row.by("id", mappingId).set("dataset_id", datasetId).set("document_id", documentId)
          //
          .set("paragraph_id", paragraphId).set("problem_id", problemId));
    }

    Db.tx(() -> {
      Db.batchSave(MossKbTableNames.moss_kb_problem, problemRecords, 2000);
      Db.batchSave(MossKbTableNames.moss_kb_problem_paragraph_mapping, mappings, 2000);
      return true;
    });
    return null;
  }

  public ResultVo addProblemById(Long datasetId, Long documentId, Long paragraphId, String content) {
    long problemId = SnowflakeIdUtils.id();
    Row problem = Row.by("id", problemId).set("dataset_id", datasetId).set("hit_num", 0).set("content", content);
    long mappingId = SnowflakeIdUtils.id();
    Row mapping = Row.by("id", mappingId).set("dataset_id", datasetId).set("document_id", documentId)
        //
        .set("paragraph_id", paragraphId).set("problem_id", problemId);
    ;
    Db.tx(() -> {
      Db.save(MossKbTableNames.moss_kb_problem, problem);
      Db.save(MossKbTableNames.moss_kb_problem_paragraph_mapping, mapping);
      return true;
    });
    return null;
  }

  public ResultVo create(Long userId, Long datasetId, Long documentId, Paragraph p) {
    if (!DatasetAccess.ownsDocument(userId, datasetId, documentId)) {
      return ResultVo.fail("文档不存在或无权访问");
    }
    insertParagraph(datasetId, documentId, p.getTitle(), p.getContent());
    return ResultVo.ok();
  }

  /** 插入段落并计算向量，返回段落 ID；调用方需自行完成归属校验。 */
  public Long insertParagraph(Long datasetId, Long documentId, String title, String content) {
    if (content == null || content.isBlank()) {
      throw new IllegalArgumentException("段落内容不能为空");
    }
    Row dataset = Db.findById(MossKbTableNames.moss_kb_dataset, datasetId);
    if (dataset == null) {
      throw new IllegalArgumentException("知识库不存在");
    }
    Long embedding_mode_id = dataset.getLong("embedding_mode_id");
    KbEmbeddingService mossKbEmbeddingService = Aop.get(KbEmbeddingService.class);

    PGobject contentVector = mossKbEmbeddingService.getVectorForModel(content, embedding_mode_id);
    PGobject titleVector = title == null || title.isBlank() ? null : mossKbEmbeddingService.getVectorForModel(title, embedding_mode_id);
    long id = SnowflakeIdUtils.id();
    Row record = Row.by("id", id)
        .set("source_type", "md")
        .set("title", title)
        .set("content", content)
        .set("md5", Md5Utils.md5Hex(content))
        .set("status", "2")
        .set("hit_num", 0)
        .set("is_active", true).set("dataset_id", datasetId).set("document_id", documentId)
        .set("embedding", contentVector).set(MossKbParagraph.titleEmbedding, titleVector);

    Db.save(MossKbTableNames.moss_kb_paragraph, record);
    refreshStatistics(documentId);
    return id;
  }

  /** 删除段落及其问题关联；标注删除与段落管理共用。 */
  public ResultVo delete(Long userId, Long datasetId, Long documentId, Long paragraphId) {
    if (!DatasetAccess.ownsDocument(userId, datasetId, documentId)) {
      return ResultVo.fail("文档不存在或无权访问");
    }
    deleteParagraph(datasetId, documentId, paragraphId);
    return ResultVo.ok(true);
  }

  /** 调用方需自行完成归属校验。 */
  public boolean deleteParagraph(Long datasetId, Long documentId, Long paragraphId) {
    int deleted = Db.update("delete from moss_kb_paragraph where id=? and dataset_id=? and document_id=?", paragraphId, datasetId, documentId);
    if (deleted > 0) {
      Db.update("delete from moss_kb_problem_paragraph_mapping where paragraph_id=?", paragraphId);
      refreshStatistics(documentId);
    }
    return deleted > 0;
  }

  public ResultVo update(Long userId, Long datasetId, Long documentId, Long id, Paragraph p) {
    if (!DatasetAccess.ownsDocument(userId, datasetId, documentId)) {
      return ResultVo.fail("文档不存在或无权访问");
    }
    Row previous = Db.findFirst("select * from moss_kb_paragraph where id=? and document_id=? and dataset_id=?", id, documentId, datasetId);
    if (previous == null) {
      return ResultVo.fail("分段不存在");
    }
    if (p.getContent() == null) {
      p.setContent(previous.getStr("content"));
    }
    if (p.getTitle() == null) {
      p.setTitle(previous.getStr("title"));
    }
    TableInput tableInput = new TableInput();
    tableInput.set("id", datasetId);
    tableInput.set("user_id", userId);


    TableResult<Row> result = ApiTable.get(MossKbTableNames.moss_kb_dataset, tableInput);

    Row dataset = result.getData();
    if (dataset == null) {
      return ResultVo.fail("Dataset not found.");
    }

    Long embedding_mode_id = dataset.getLong("embedding_mode_id");
    PlatformInput platformInput = mossKbModelService.getEmbeddingPlatformInput(embedding_mode_id);

    KbEmbeddingService mossKbEmbeddingService = Aop.get(KbEmbeddingService.class);

    String title = p.getTitle();
    String content = p.getContent();
    PGobject contentVector = mossKbEmbeddingService.getVectorForModel(content, embedding_mode_id);
    PGobject titleVector = title == null || title.isBlank() ? null : mossKbEmbeddingService.getVectorForModel(title, embedding_mode_id);
    Row record = Row.by("id", id)
        //
        // .set("source_id", )
        //
        .set("source_type", "md")
        //
        .set("title", title)
        //
        .set("content", content)
        //
        .set("md5", Md5Utils.md5Hex(content))
        //
        .set("status", "2")
        //
        .set("hit_num", 0)
        //
        .set("is_active", true).set("dataset_id", datasetId).set("document_id", documentId)
        //
        .set("embedding", contentVector).set(MossKbParagraph.titleEmbedding, titleVector);

    Db.update(MossKbTableNames.moss_kb_paragraph, record);
    Db.update("update moss_kb_paragraph set is_active=?,update_time=now() where id=?", p.getIs_active() == null ? previous.getBoolean("is_active") : p.getIs_active(), id);
    refreshStatistics(documentId);

    return ResultVo.ok();
  }

  void refreshStatistics(Long documentId) {
    Db.update("update moss_kb_document set paragraph_count=(select count(*) from moss_kb_paragraph where document_id=?), char_length=(select coalesce(sum(length(content)),0) from moss_kb_paragraph where document_id=?),update_time=now() where id=?", documentId, documentId, documentId);
  }

}
