package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;

import com.jfinal.kit.Kv;

import nexus.io.db.TableInput;
import nexus.io.db.TableResult;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.kit.RowUtils;
import nexus.io.mosskb.constant.MossKbTableNames;
import nexus.io.mosskb.dao.MossKbDatasetDao;
import nexus.io.mosskb.model.MossKbDataset;
import nexus.io.mosskb.vo.KbDatasetModel;
import nexus.io.mosskb.vo.ResultPage;
import nexus.io.mosskb.utils.JsonColumnUtils;
import nexus.io.model.page.Page;
import nexus.io.model.result.ResultVo;
import nexus.io.table.constants.Operators;
import nexus.io.table.services.ApiTable;

public class MossKbDatasetService {

  private String application_mapping_count_sql = String.format("select count(1) from %s where dataset_id=?", MossKbTableNames.moss_kb_application_dataset_mapping);
  private String document_count_sql = String.format("select count(1) from %s where dataset_id=?", MossKbTableNames.moss_kb_document);
  private String sum_char_length_sql = String.format("select sum(char_length) from %s where dataset_id=?", MossKbTableNames.moss_kb_document);

  public ResultVo page(Long userId, Integer pageNo, Integer pageSize, String name) {
    TableInput tableInput = new TableInput();
    tableInput.setPageNo(pageNo).setPageSize(pageSize);
    tableInput.set("user_id", userId);


    if (name != null) {
      tableInput.set("name", name).set("name_op", Operators.CT);
    }

    TableResult<Page<Row>> tableResult = ApiTable.page(MossKbTableNames.moss_kb_dataset, tableInput);
    Page<Row> page = tableResult.getData();
    int totalRow = page.getTotalRow();
    List<Row> list = page.getList();
    List<Kv> kvs = new ArrayList<>();
    for (Row record : list) {
      Kv kv = record.toKv();
      Long datasetId = kv.getLong("id");

      Long application_mapping_count = Db.queryLong(application_mapping_count_sql, datasetId);
      kv.set("application_mapping_count", application_mapping_count);
      Long document_count = Db.queryLong(document_count_sql, datasetId);
      kv.set("document_count", document_count);
      Long charLength = Db.queryLong(sum_char_length_sql, datasetId);
      kv.set("char_length", charLength);
      kvs.add(kv);
    }

    ResultPage<Kv> resultPage = new ResultPage<>(pageNo, pageSize, totalRow, kvs);
    return ResultVo.ok(resultPage);
  }

  public ResultVo save(Long userId, KbDatasetModel kbDatasetModel) {
    if (kbDatasetModel.getId() != null && !DatasetAccess.owns(userId, kbDatasetModel.getId())) {
      return ResultVo.fail("知识库不存在或无权访问");
    }
    Row existing = kbDatasetModel.getId() == null ? null : Db.findById(MossKbTableNames.moss_kb_dataset, kbDatasetModel.getId());
    if (existing != null) {
      // 编辑接口只提交部分字段，未提交的字段沿用原值，避免类型和 meta 被清空。
      if (kbDatasetModel.getType() == null) {
        kbDatasetModel.setType(existing.getStr("type"));
      }
      if (kbDatasetModel.getMeta() == null) {
        kbDatasetModel.setMeta(JsonColumnUtils.toJsonObject(existing.get("meta")));
      }
      if (kbDatasetModel.getName() == null) {
        kbDatasetModel.setName(existing.getStr("name"));
      }
      if (kbDatasetModel.getDesc() == null) {
        kbDatasetModel.setDesc(existing.getStr("desc"));
      }
    }
    Long embeddingId = kbDatasetModel.getEmbedding_mode_id();
    if (embeddingId == null) {
      embeddingId = existing == null ? 1002L : existing.getLong("embedding_mode_id");
      kbDatasetModel.setEmbedding_mode_id(embeddingId);
    }
    if (!ModelAccess.canUse(userId, embeddingId) || Db.queryLong("select count(*) from moss_kb_model where id=? and model_type='EMBEDDING'", embeddingId) == 0) {
      return ResultVo.fail("向量模型不存在或无权使用");
    }
    if (existing != null && !embeddingId.equals(existing.getLong("embedding_mode_id"))
        && Db.queryLong("select count(*) from moss_kb_paragraph where dataset_id=?", kbDatasetModel.getId()) > 0) {
      return ResultVo.fail("已有文档的知识库不能直接切换向量空间，请新建知识库并重新导入文档");
    }
    ResultVo resultVo = new ResultVo();
    TableResult<Kv> saveOrUpdate = Aop.get(MossKbDatasetDao.class).saveOrUpdate(userId, kbDatasetModel);
    Kv data = saveOrUpdate.getData();
    resultVo.setData(data);
    return resultVo;
  }

  public ResultVo get(Long userId, Long id) {
    ResultVo resultVo = new ResultVo();
    TableInput tableInput = new TableInput();
    tableInput.set("id", id).set("user_id", userId);

    TableResult<Row> result = ApiTable.get(MossKbTableNames.moss_kb_dataset, tableInput);
    Row row = result.getData();
    if (row == null) {
      return ResultVo.fail("知识库不存在或无权访问");
    }
    Kv kv = row.toKv();
    // meta 是 jsonb 列，直接序列化 PGobject 会得到前端无法解析的结构。
    kv.set("meta", JsonColumnUtils.toJsonObject(row.get("meta")));
    kv.set("application_id_list", applicationIdList(id));
    kv.set("document_count", Db.queryLong(document_count_sql, id));
    kv.set("char_length", Db.queryLong(sum_char_length_sql, id));
    resultVo.setData(kv);
    return resultVo;
  }

  private List<Long> applicationIdList(Long datasetId) {
    List<Long> applicationIds = new ArrayList<>();
    for (Row row : Db.find("select application_id from moss_kb_application_dataset_mapping where dataset_id=?", datasetId)) {
      applicationIds.add(row.getLong("application_id"));
    }
    return applicationIds;
  }

  public ResultVo list(Long userId) {
    Row queryRecord = new Row();
    queryRecord.set("user_id", userId);


    String columns = "id,name,\"desc\",type,meta,user_id,embedding_mode_id,create_time,update_time";
    List<Row> records = Db.find(MossKbDataset.tableName, columns, queryRecord);
    List<Kv> kvs = RowUtils.toKv(records, false);
    for (int i = 0; i < kvs.size(); i++) {
      kvs.get(i).set("meta", JsonColumnUtils.toJsonObject(records.get(i).get("meta")));
    }
    return ResultVo.ok(kvs);
  }

  public ResultVo delete(Long userId, Long id) {
    if (!DatasetAccess.owns(userId, id)) {
      return ResultVo.fail("知识库不存在或无权访问");
    }
    TableInput tableInput = null;
    tableInput = TableInput.by("id", id).set("user_id", userId);


    TableResult<Boolean> result = ApiTable.delete(MossKbTableNames.moss_kb_dataset, tableInput);
    Row deleteRecord = Row.by("dataset_id", id);
    Db.delete(MossKbTableNames.moss_kb_document, deleteRecord);
    Db.delete(MossKbTableNames.moss_kb_paragraph, deleteRecord);
    return new ResultVo(result.getData());
  }

  public ResultVo getApplicationByDatasetId(Long datasetId) {
    return ResultVo.ok();
  }
}
