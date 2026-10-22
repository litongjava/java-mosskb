package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;

import com.jfinal.kit.Kv;

import lombok.extern.slf4j.Slf4j;
import nexus.io.db.TableInput;
import nexus.io.db.TableResult;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.kit.RowUtils;
import nexus.io.mosskb.constant.MossKbTableNames;
import nexus.io.mosskb.vo.MossKbUpdateDocumentRequestVo;
import nexus.io.mosskb.vo.ResultPage;
import nexus.io.mosskb.utils.JsonColumnUtils;
import nexus.io.model.page.Page;
import nexus.io.model.result.ResultVo;
import nexus.io.table.services.ApiTable;

@Slf4j
public class MossKbDocumentService {

  /** 预览一次最多返回的分段数，避免超长文档把整篇正文发给浏览器。 */
  private static final int PREVIEW_PARAGRAPH_LIMIT = 1000;

  /** 预览一次最多返回的正文字符数，达到上限后只保留前面的分段。 */
  private static final int PREVIEW_CHAR_LIMIT = 200_000;

  /**
   * 文档必须同时属于该应用关联的知识库，访客才看不到未关联文档的内容。
   */
  private static final String FIND_APPLICATION_DOCUMENT = """
      select d.id,
             d.name,
             d.type,
             d.dataset_id,
             d.char_length,
             d.paragraph_count,
             s.name as dataset_name
        from moss_kb_document d
        join moss_kb_application_dataset_mapping m on m.dataset_id = d.dataset_id
   left join moss_kb_dataset s on s.id = d.dataset_id
       where m.application_id = ?
         and d.id = ?
       limit 1
      """;

  /**
   * 分段没有单独的顺序列，主键由雪花算法递增生成，按主键升序即导入顺序。
   */
  private static final String FIND_PREVIEW_PARAGRAPHS = """
      select id,
             title,
             content,
             is_active
        from moss_kb_paragraph
       where document_id = ?
         and deleted = 0
       order by id
       limit ?
      """;

  public ResultVo page(Long userId, Long datasetId, Integer pageNo, Integer pageSize) {
    TableInput tableInput = new TableInput();
    tableInput.set("user_id", userId);

    tableInput.set("dataset_id", datasetId).setPageNo(pageNo).setPageSize(pageSize);
    TableResult<Page<Row>> tableResult = ApiTable.page(MossKbTableNames.moss_kb_document, tableInput);
    Page<Row> page = tableResult.getData();
    int totalRow = page.getTotalRow();
    List<Row> list = page.getList();
    List<Kv> kvs = RowUtils.toKv(list, false);
    for (int i = 0; i < kvs.size(); i++) {
      // Web 站点文档把来源地址放在 meta 里，前端据此显示与同步。
      kvs.get(i).set("meta", JsonColumnUtils.toJsonObject(list.get(i).get("meta")));
    }
    ResultPage<Kv> resultPage = new ResultPage<>(pageNo, pageSize, totalRow, kvs);
    return ResultVo.ok(resultPage);
  }

  public ResultVo list(Long userId, Long datasetId) {
    TableInput tableInput = new TableInput();
    tableInput.set("user_id", userId);

    tableInput.set("dataset_id", datasetId);
    TableResult<List<Row>> tableResult = ApiTable.list(MossKbTableNames.moss_kb_document, tableInput);
    List<Row> records = tableResult.getData();
    List<Kv> kvs = RowUtils.toKv(records, false);
    for (int i = 0; i < kvs.size(); i++) {
      kvs.get(i).set("meta", JsonColumnUtils.toJsonObject(records.get(i).get("meta")));
    }
    return ResultVo.ok(kvs);
  }

  public ResultVo get(Long userId, Long datasetId, Long documentId) {
    TableInput tableInput = TableInput.by("id", documentId);
    tableInput.set("user_id", userId).set("dataset_id", datasetId);


    Row data = ApiTable.get(MossKbTableNames.moss_kb_document, tableInput).getData();
    if (data == null) {
      return ResultVo.fail("文档不存在或无权访问");
    }
    Kv kv = data.toKv();
    kv.set("meta", JsonColumnUtils.toJsonObject(data.get("meta")));
    return ResultVo.ok(kv);
  }

  /**
   * 对话来源里的文档预览：按应用开放，返回该文档的全部有效分段。
   *
   * @param clientId      请求身份，应用所有者或分享链接访客
   * @param applicationId 应用 id，用于校验文档所属知识库是否与该应用关联
   * @param documentId    文档 id
   * @param paragraphId   本次回答命中的分段 id，仅回传给前端做高亮定位
   */
  public ResultVo preview(Long clientId, Long applicationId, Long documentId, Long paragraphId) {
    if (applicationId == null || documentId == null) {
      return ResultVo.fail("缺少应用或文档标识");
    }
    if (!ApplicationAccess.owns(clientId, applicationId) && !ApplicationAccess.canChat(clientId, applicationId)) {
      return ResultVo.fail("应用不存在或无权访问");
    }
    Row document = Db.findFirst(FIND_APPLICATION_DOCUMENT, applicationId, documentId);
    if (document == null) {
      return ResultVo.fail("文档不存在或不属于该应用的知识库");
    }

    // 多取一条用于判断是否被分段数上限截断。
    List<Row> records = Db.find(FIND_PREVIEW_PARAGRAPHS, documentId, PREVIEW_PARAGRAPH_LIMIT + 1);
    List<Kv> paragraphs = new ArrayList<>();
    boolean truncated = records.size() > PREVIEW_PARAGRAPH_LIMIT;
    int charLength = 0;
    for (Row record : records) {
      if (paragraphs.size() >= PREVIEW_PARAGRAPH_LIMIT || charLength >= PREVIEW_CHAR_LIMIT) {
        truncated = true;
        break;
      }
      String content = record.getStr("content");
      paragraphs.add(Kv.by("id", record.getLong("id"))
          //
          .set("title", record.getStr("title"))
          //
          .set("content", content)
          //
          .set("is_active", record.getBoolean("is_active")));
      if (content != null) {
        charLength += content.length();
      }
    }

    Kv data = Kv.by("document_id", document.getLong("id"))
        //
        .set("document_name", document.getStr("name"))
        //
        .set("document_type", document.getStr("type"))
        //
        .set("dataset_id", document.getLong("dataset_id"))
        //
        .set("dataset_name", document.getStr("dataset_name"))
        //
        .set("paragraph_count", document.getInt("paragraph_count"))
        //
        .set("preview_paragraph_count", paragraphs.size())
        //
        .set("char_length", document.getInt("char_length"))
        //
        .set("hit_paragraph_id", paragraphId)
        //
        .set("truncated", truncated)
        //
        .set("paragraphs", paragraphs);
    return ResultVo.ok(data);
  }

  public ResultVo delete(Long userId, Long datasetId, Long documentId) {
    if (!DatasetAccess.ownsDocument(userId, datasetId, documentId)) {
      return ResultVo.fail("文档不存在或无权访问");
    }
    Row row = Row.by("id", documentId).set("user_id", userId).set("dataset_id", datasetId);
    Db.delete(MossKbTableNames.moss_kb_document, row);
    row = Row.by("document_id", documentId).set("dataset_id", datasetId);
    Db.delete(MossKbTableNames.moss_kb_paragraph, row);
    return ResultVo.ok();
  }

  public ResultVo update(Long userId, Long datasetId, Long documentId, MossKbUpdateDocumentRequestVo vo) {
    if (!DatasetAccess.ownsDocument(userId, datasetId, documentId)) {
      return ResultVo.fail("文档不存在或无权访问");
    }
    Row row = Row.by("id", documentId);
    if (vo.getName() != null) {
      row.set("name", vo.getName());
    }
    if (vo.getIs_active() != null) {
      row.set("is_active", vo.getIs_active());
    }
    if (vo.getHit_handling_method() != null) {
      row.set("hit_handling_method", vo.getHit_handling_method());
    }
    if (vo.getDirectly_return_similarity() != null) {
      row.set("directly_return_similarity", vo.getDirectly_return_similarity());
    }
    row.set("update_time", new java.util.Date());
    Db.update(MossKbTableNames.moss_kb_document, row);
    return ResultVo.ok();
  }

}
