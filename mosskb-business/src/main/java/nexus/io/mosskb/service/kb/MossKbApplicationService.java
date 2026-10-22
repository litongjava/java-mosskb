package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;

import com.jfinal.kit.Kv;

import lombok.extern.slf4j.Slf4j;
import nexus.io.db.TableInput;
import nexus.io.db.TableResult;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.kit.PgObjectUtils;
import nexus.io.mosskb.constant.MossKbTableNames;
import nexus.io.mosskb.dao.MossKbApplicationDao;
import nexus.io.mosskb.model.MossKbApplication;
import nexus.io.mosskb.model.MossKbApplicationDatasetMapping;
import nexus.io.mosskb.model.MossKbApplicationPublicAccessClient;
import nexus.io.mosskb.model.MossKbModel;
import nexus.io.mosskb.vo.MossKbApplicationVo;
import nexus.io.mosskb.vo.MossKbDatasetSettingVo;
import nexus.io.mosskb.vo.MossKbModelParamsSetting;
import nexus.io.mosskb.vo.MossKbModelSetting;
import nexus.io.model.page.Page;
import nexus.io.model.result.ResultVo;
import nexus.io.table.services.ApiTable;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

@Slf4j
public class MossKbApplicationService {

  public ResultVo create(Long userId, MossKbApplicationVo application) {
    if (!ModelAccess.canUse(userId, application.getModel_id())) {
      return ResultVo.fail("无权使用模型");
    }
    Long applicationId = SnowflakeIdUtils.id();
    application.setId(applicationId);
    Row record = Row.fromBean(application);
    record.remove("dataset_id_list");
    record.set("user_id", userId);
    Db.save(MossKbApplication.tableName, record);

    Aop.get(MossKbApplicationAccessTokenService.class).create(applicationId);
    return ResultVo.ok(application);
  }

  public ResultVo update(Long userId, MossKbApplicationVo application) {
    if (!ApplicationAccess.owns(userId, application.getId())) {
      return ResultVo.fail("应用不存在或无权访问");
    }
    if (!ModelAccess.canUse(userId, application.getModel_id())) {
      return ResultVo.fail("无权使用模型");
    }
    List<Long> dataset_id_list = application.getDataset_id_list();
    List<MossKbApplicationDatasetMapping> saveRecords = new ArrayList<>();
    if (dataset_id_list != null) {
      for (Long datasetId : dataset_id_list) {
        if (!DatasetAccess.owns(userId, datasetId)) {
          return ResultVo.fail("无权关联知识库");
        }
        MossKbApplicationDatasetMapping mapping = new MossKbApplicationDatasetMapping();
        mapping.setId(SnowflakeIdUtils.id()).setDatasetId(datasetId).setApplicationId(application.getId());
        saveRecords.add(mapping);
      }
    }

    Row record = Row.fromBean(application);
    record.remove("dataset_id_list");
    record.set("user_id", userId);

    Db.tx(() -> {
      if (dataset_id_list != null) {
        Db.deleteById(MossKbApplicationDatasetMapping.tableName, "application_id", application.getId());
        if (saveRecords.size() > 0) {
          Db.batchSave(saveRecords, 2000);
        }
      }

      Db.update(MossKbApplication.tableName, record);
      return true;
    });

    return ResultVo.ok();
  }

  public ResultVo delete(Long userId, Long applicationId) {
    if (!ApplicationAccess.owns(userId, applicationId)) {
      return ResultVo.fail("无权删除应用");
    }
    boolean deleted = Db.deleteById(MossKbApplication.tableName, applicationId);
    new MossKbApplicationDatasetMapping().setApplicationId(applicationId).delete();
    Aop.get(MossKbApplicationAccessTokenService.class).delete(applicationId);
    return ResultVo.ok(deleted);
  }

  public ResultVo page(TableInput tableInput) {
    Integer pageNo = tableInput.getPageNo();
    Integer pageSize = tableInput.getPageSize();
    log.info("page:{},{}", pageNo, pageSize);
    tableInput.setFrom(MossKbTableNames.moss_kb_application);
    TableResult<Page<Row>> result = ApiTable.page(tableInput);
    Page<Row> page = result.getData();
    List<Row> records = page.getList();
    List<Kv> kvs = new ArrayList<>();
    for (Row record : records) {
      PgObjectUtils.toBean(record, "model_setting", MossKbModelSetting.class);
      PgObjectUtils.toBean(record, "model_params_setting", MossKbModelParamsSetting.class);
      PgObjectUtils.toBean(record, "dataset_setting", MossKbDatasetSettingVo.class);
      kvs.add(record.toKv());
    }
    Kv kv = Kv.by("current", pageNo).set("size", pageSize).set("total", page.getTotalRow()).set("records", kvs);
    return ResultVo.ok(kv);
  }

  public ResultVo list(Long userId) {
    Row quereyRecord = new Row();
    quereyRecord.set("user_id", userId);


    List<Row> records = Db.find(MossKbTableNames.moss_kb_application, quereyRecord);
    List<Kv> kvs = new ArrayList<>();
    for (Row record : records) {
      PgObjectUtils.toBean(record, "model_params_setting", MossKbModelParamsSetting.class);
      PgObjectUtils.toBean(record, "model_setting", MossKbModelSetting.class);
      PgObjectUtils.toBean(record, "dataset_setting", MossKbDatasetSettingVo.class);
      Kv kv = record.toKv();
      kvs.add(kv);
    }
    return ResultVo.ok(kvs);
  }

  public ResultVo get(Long userId, Long applicationId) {

    log.info("user_id:{}", userId);
    Row quereyRecord = null;
    quereyRecord = Row.by("id", applicationId).set("user_id", userId);


    Row record = Db.findFirst(MossKbApplication.tableName, quereyRecord);
    if (record == null) {
      return ResultVo.fail("应用不存在或无权访问");
    }
    PgObjectUtils.toBean(record, "model_params_setting", MossKbModelParamsSetting.class);
    PgObjectUtils.toBean(record, "dataset_setting", MossKbDatasetSettingVo.class);

    Object object = record.get("model_setting");
    if (object != null) {
      PgObjectUtils.toBean(record, "model_setting", MossKbModelSetting.class);
    } else {
      MossKbModelSetting mossKbModelSetting = new MossKbModelSetting();
      mossKbModelSetting.setSystem("你是 xxx 小助手").setPrompt("已知信息：{data}\n用户问题：{question}\n回答要求：\n - 请使用中文回答用户问题")
          //
          .setNo_references_prompt("{question}");

      record.set("model_setting", mossKbModelSetting);
    }

    Long modelId = record.getLong("model_id");

    String sql = String.format("select dataset_id from %s where application_id=?", MossKbApplicationDatasetMapping.tableName);
    List<Long> dataset_id_list = Db.queryListLong(sql, applicationId);
    record.set("dataset_id_list", dataset_id_list);
    record.set("model", modelId);
    Kv kv = record.toKv();
    return ResultVo.ok(kv);
  }

  public ResultVo listApplicaionModel(Long userId, Long applicationId) {
    Row queryRecord = Row.by("user_id", userId).set("model_type", "LLM");
    String columns = "id,name,provider,model_type,model_name,status,meta,permission_type,user_id";
    List<Row> list = Db.find("select " + columns + " from moss_kb_model where model_type='LLM' and user_id=?", userId);
    List<Kv> kvs = new ArrayList<>();
    MossKbUserService mossKbUserService = Aop.get(MossKbUserService.class);

    for (Row record : list) {
      Long user_id = record.getLong("user_id");
      String username = mossKbUserService.queryUsername(user_id);
      record.set("username", username);
      kvs.add(record.toKv());
    }

    return ResultVo.ok(kvs);
  }

  public ResultVo setModelId(Long userIdLong, Long applicationId, Long modelId) {
    if (!ApplicationAccess.owns(userIdLong, applicationId)) {
      return ResultVo.fail("无权访问应用");
    }
    return ResultVo.ok(java.util.Collections.emptyList());
  }

  public ResultVo listApplicaionDataset(Long userId, Long applicationId) {
    return Aop.get(MossKbDatasetService.class).list(userId);
  }

  public ResultVo profile(Long clientId) {
    Long applicationId = Db.queryLong("select application_id from moss_kb_application_public_access_client where client_id=? order by id desc limit 1", clientId);
    if (applicationId == null) {
      return ResultVo.fail("applicationId is null");
    }
    Row applicaiton = Aop.get(MossKbApplicationDao.class).getBasicInfoById(applicationId);
    if (!ApplicationAccess.canChat(clientId, applicationId)) {
      return ResultVo.fail("应用已停用或无权访问");
    }
    if (applicaiton == null) {
      return ResultVo.ok();
    }

    Kv profile = applicaiton.toKv();
    // 分享页的显示开关与对话语言存放在公开链接上，由应用概览的公开访问设置维护
    Row accessToken = Db.findFirst("select show_source,language from moss_kb_application_access_token where application_id=? and deleted=0",
        applicationId);
    if (accessToken != null) {
      profile.set("show_source", Boolean.TRUE.equals(accessToken.getBoolean("show_source")));
      profile.set("language", accessToken.getStr("language"));
    }
    return ResultVo.ok(profile);
  }
}
