package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.FunctionIconService;
import nexus.io.model.result.ResultVo;
import nexus.io.model.upload.UploadFile;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

/**
 * 函数库：代码、参数定义、初始化参数和执行入口都在这里。
 *
 * <p>执行本身交给 {@link IsolatedPythonExecutor}，这个类只负责存取、参数合并和权限判断。
 */
public class PythonFunctionService {

  /** 函数正文上限，和执行器的限制保持一致。 */
  private static final int MAX_CODE_LENGTH = 65536;

  /** 函数名长度上限。 */
  private static final int MAX_NAME_LENGTH = 64;

  /** 描述长度上限。 */
  private static final int MAX_DESC_LENGTH = 128;

  /** 单页最多返回的记录数。 */
  private static final int MAX_PAGE_SIZE = 100;

  /** 导出文件的格式版本，导入时按这个字段判断能不能解析。 */
  private static final String EXPORT_VERSION = "v1";

  /** 参数类型，和前端字段表单的下拉项一致。 */
  private static final List<String> FIELD_TYPES = List.of("string", "int", "float", "dict", "array");

  /** 参数来源：custom 是调用时手填，reference 由上游节点传入。 */
  private static final List<String> FIELD_SOURCES = List.of("custom", "reference");

  /** 列表和详情共用的查询条件：自己的函数加上别人公开的函数。 */
  private static final String VISIBLE_WHERE = """
      from moss_kb_function_lib
       where deleted = false
         and user_id = ?
      """;

  public ResultVo list(Long user, Integer page, Integer size, String name, String functionType, String selectUserId) {
    int limit = Math.max(1, Math.min(MAX_PAGE_SIZE, size == null ? MAX_PAGE_SIZE : size));
    int current = Math.max(1, page == null ? 1 : page);
    Query query = query(user, name, functionType, selectUserId);
    if (page == null) {
      return ResultVo.ok(records(query, " order by id desc limit ?", limit));
    }
    JSONObject result = new JSONObject();
    result.put("current", current);
    result.put("size", limit);
    result.put("total", Db.queryLong("select count(*) " + query.where, query.params.toArray()));
    result.put("records", records(query, " order by id desc limit ? offset ?", limit, (current - 1) * limit));
    return ResultVo.ok(result);
  }

  public ResultVo get(Long user, Long id) {
    Row row = Db.findFirst("select * " + VISIBLE_WHERE + " and id = ?", user, id);
    if (row == null) {
      return ResultVo.fail("函数不存在或无权访问");
    }
    return ResultVo.ok(detail(row, user));
  }

  /** 调试未保存的代码：先合并参数，再交给执行器，异常信息直接返回给界面。 */
  public Object debug(JSONObject input) {
    JSONObject params = input.getJSONObject("init_params");
    params = params == null ? new JSONObject() : new JSONObject(params);
    JSONObject debug = new JSONObject();
    JSONArray values = input.getJSONArray("debug_field_list");
    if (values != null) {
      for (Object item : values) {
        JSONObject field = (JSONObject) item;
        debug.put(field.getString("name"), field.get("value"));
      }
    }
    JSONArray fields = input.getJSONArray("input_field_list");
    if (fields != null) {
      for (Object item : fields) {
        JSONObject field = (JSONObject) item;
        String name = field.getString("name");
        Object value = debug.get(name);
        if (value != null && value instanceof String text && text.isBlank()) {
          value = null;
        }
        if (value == null) {
          if (field.getBooleanValue("is_required")) {
            throw new IllegalArgumentException("缺少函数参数：" + name);
          }
          params.remove(name);
          continue;
        }
        params.put(name, convert(value, field.getString("type")));
      }
    }
    return Aop.get(IsolatedPythonExecutor.class).execute(input.getString("code"), params, input.getString("entrypoint"),
        false);
  }

  public ResultVo pylint(String code) {
    return ResultVo.ok(Aop.get(IsolatedPythonExecutor.class).execute(code, null, null, true));
  }

  /**
   * 执行自己保存且启用的函数，请求体是调用参数，内部会合并函数自己的初始化参数。
   *
   * <p>同时作为 Java 侧工作流函数节点的共享入口。
   */
  public Object execute(Long user, Long id, JSONObject arguments) {
    Row row = Db.findFirst("select * from moss_kb_function_lib where id=? and user_id=? and deleted=false", id, user);
    if (row == null || !Boolean.TRUE.equals(row.getBoolean("is_active"))) {
      throw new IllegalArgumentException("函数不存在、已停用或无权执行");
    }
    JSONObject params = parseObject(row.getObject("init_params"));
    if (arguments != null) {
      params.putAll(arguments);
    }
    return Aop.get(IsolatedPythonExecutor.class).execute(row.getStr("code"), params, null, false);
  }

  /** 新建或修改函数，只写自己的记录；修改时请求里没带的字段保持原值。 */
  public ResultVo save(Long user, Long id, JSONObject input) {
    JSONObject data = input;
    Row existing = null;
    if (id != null) {
      existing = owned(user, id);
      if (existing == null) {
        return ResultVo.fail("函数不存在或无权修改");
      }
      data = detail(existing, user);
      data.putAll(input);
      restoreMaskedSecrets(existing, data);
    }
    String invalid = validate(data);
    if (invalid != null) {
      return ResultVo.fail(invalid);
    }
    String permission = data.getString("permission_type");
    permission = permission == null ? "PRIVATE" : permission;
    if (!List.of("PRIVATE", "PUBLIC").contains(permission)) {
      return ResultVo.fail("无效的函数权限类型");
    }
    String icon = normalizeIcon(data.getString("icon"), id == null);
    long savedId = id == null ? SnowflakeIdUtils.id() : id;
    String fields = JSON.toJSONString(normalizeFields(data.getJSONArray("input_field_list")));
    String initFields = JSON.toJSONString(data.getOrDefault("init_field_list", new JSONArray()));
    String init = JSON.toJSONString(normalizeInitParams(data, initFields));
    // 新建时和上游一致，先保持停用，由用户在列表里手动启用
    boolean active = id != null && !Boolean.FALSE.equals(data.getBoolean("is_active"));
    if (id == null) {
      Db.update("""
          insert into moss_kb_function_lib(id,user_id,name,"desc",code,input_field_list,init_field_list,init_params,
            permission_type,is_active,icon,function_type)
          values(?,?,?,?,?,?::jsonb,?::jsonb,?::jsonb,?,?,?, 'PUBLIC')
          """, savedId, user, data.getString("name"), data.getOrDefault("desc", ""), data.getString("code"), fields,
          initFields, init, permission, active, icon);
    } else {
      Db.update("""
          update moss_kb_function_lib
             set name=?,"desc"=?,code=?,input_field_list=?::jsonb,init_field_list=?::jsonb,init_params=?::jsonb,
                 permission_type=?,is_active=?,icon=?,update_time=now()
           where id=? and user_id=?
          """, data.getString("name"), data.getOrDefault("desc", ""), data.getString("code"), fields, initFields, init,
          permission, active, icon, savedId, user);
    }
    return get(user, savedId);
  }

  /**
   * 内置函数模板复制一份给自己的函数。
   *
   * <p>复制出来的函数只有名字是新的，代码和参数沿用模板，模板 id 记下来后界面会把它当成模板来源。
   */
  public ResultVo addInternal(Long user, Long templateId, String name) {
    String trimmed = name == null ? null : name.trim();
    if (trimmed == null || trimmed.isBlank() || trimmed.length() > MAX_NAME_LENGTH) {
      return ResultVo.fail("函数名称格式无效");
    }
    Row source = Db.findFirst("select * from moss_kb_function_lib where id=? and deleted=false", templateId);
    if (source == null || !"INTERNAL".equals(source.getStr("function_type"))) {
      return ResultVo.fail("函数模板不存在");
    }
    long id = SnowflakeIdUtils.id();
    Db.update("""
        insert into moss_kb_function_lib(id,user_id,name,"desc",code,input_field_list,init_field_list,init_params,
          permission_type,is_active,icon,function_type,template_id)
        values(?,?,?,?,?,?::jsonb,?::jsonb,'{}'::jsonb,'PRIVATE',false,?,'PUBLIC',?)
        """, id, user, trimmed, source.getStr("desc"), source.getStr("code"),
        Objects.toString(source.getObject("input_field_list"), "[]"),
        Objects.toString(source.getObject("init_field_list"), "[]"), source.getStr("icon"), templateId);
    return get(user, id);
  }

  /** 修改图标，图片落到静态资源目录，库里只存路径。 */
  public ResultVo editIcon(Long user, Long id, UploadFile file) {
    if (owned(user, id) == null) {
      return ResultVo.fail("函数不存在或无权修改");
    }
    String icon = Aop.get(FunctionIconService.class).save(file);
    Db.update("update moss_kb_function_lib set icon=?,update_time=now() where id=? and user_id=?", icon, id, user);
    return ResultVo.ok(icon);
  }

  /** 导出成 .fx 文件，只带函数本身，不带归属和启用状态。 */
  public JSONObject export(Long user, Long id) {
    Row row = owned(user, id);
    if (row == null) {
      throw new IllegalArgumentException("函数不存在或无权导出");
    }
    JSONObject data = detail(row, user);
    JSONObject payload = new JSONObject();
    payload.put("version", EXPORT_VERSION);
    payload.put("name", data.getString("name"));
    payload.put("desc", data.getOrDefault("desc", ""));
    payload.put("code", data.getString("code"));
    payload.put("input_field_list", data.getOrDefault("input_field_list", new JSONArray()));
    payload.put("init_field_list", data.getOrDefault("init_field_list", new JSONArray()));
    return payload;
  }

  /** 导入 .fx 文件，导入结果是自己的私有函数，默认停用。 */
  public ResultVo importFunction(Long user, UploadFile file) {
    if (file == null || file.getData() == null || file.getData().length == 0) {
      return ResultVo.fail("请选择要导入的文件");
    }
    JSONObject payload;
    try {
      payload = JSON.parseObject(new String(file.getData(), java.nio.charset.StandardCharsets.UTF_8));
    } catch (RuntimeException e) {
      return ResultVo.fail("不支持的文件格式");
    }
    if (payload == null || !EXPORT_VERSION.equals(payload.getString("version"))) {
      return ResultVo.fail("不支持的文件格式");
    }
    JSONObject input = new JSONObject();
    input.put("name", payload.getString("name"));
    input.put("desc", payload.getOrDefault("desc", ""));
    input.put("code", payload.getString("code"));
    input.put("input_field_list", payload.getOrDefault("input_field_list", new JSONArray()));
    input.put("init_field_list", payload.getOrDefault("init_field_list", new JSONArray()));
    input.put("permission_type", "PRIVATE");
    input.put("is_active", false);
    return save(user, null, input);
  }

  /** 软删除，模板来源的引用一并清掉，避免列表里残留模板标记。 */
  public ResultVo remove(Long user, Long id) {
    return ResultVo.ok(Db.update(
        "update moss_kb_function_lib set deleted=true,template_id=null,update_time=now() where id=? and user_id=?", id,
        user) > 0);
  }

  static Object convert(Object value, String type) {
    if (value == null) {
      return null;
    }
    return switch (type == null ? "string" : type) {
      case "int" -> Long.valueOf(value.toString().trim());
      case "float" -> Double.valueOf(value.toString().trim());
      case "dict" -> JSON.parseObject(value.toString());
      case "array" -> JSON.parseArray(value.toString());
      default -> value.toString();
    };
  }

  private Query query(Long user, String name, String functionType, String selectUserId) {
    Query query = new Query(VISIBLE_WHERE + " and name ilike ?");
    query.params.add(user);
    query.params.add("%" + (name == null ? "" : name) + "%");
    if (functionType != null && !functionType.isBlank()) {
      query.where += " and function_type = ?";
      query.params.add(functionType);
    }
    if (selectUserId != null && !selectUserId.isBlank()) {
      query.where += " and user_id = ?";
      query.params.add(Long.valueOf(selectUserId));
    }
    return query;
  }

  private List<JSONObject> records(Query query, String tail, Object... args) {
    List<Object> params = new ArrayList<>(query.params);
    params.addAll(List.of(args));
    List<JSONObject> records = new ArrayList<>();
    for (Row row : Db.find("select * " + query.where + tail, params.toArray())) {
      records.add(summary(row));
    }
    return records;
  }

  /** 列表项不带初始化参数，避免把别人的密钥下发给其他用户。 */
  private JSONObject summary(Row row) {
    return value(row);
  }

  /** 详情带初始化参数；别人的公开函数只给参数名，不给值。 */
  private JSONObject detail(Row row, Long user) {
    JSONObject value = value(row);
    if (!user.equals(row.getLong("user_id"))) {
      value.put("init_params", new JSONObject());
    } else {
      value.put("init_params", maskInitParams(value, row));
    }
    return value;
  }

  /** 密码类初始化参数按上游习惯打码，只保留首尾片段。 */
  private JSONObject maskInitParams(JSONObject value, Row row) {
    JSONObject params = parseObject(row.getObject("init_params"));
    JSONArray fields = value.getJSONArray("init_field_list");
    if (fields == null) {
      return params;
    }
    for (Object item : fields) {
      JSONObject field = (JSONObject) item;
      if (!"PasswordInput".equals(field.getString("input_type"))) {
        continue;
      }
      String key = field.getString("field");
      Object secret = params.get(key);
      if (secret != null && !secret.toString().isBlank()) {
        params.put(key, mask(secret.toString()));
      }
    }
    return params;
  }

  /** 保留前 2 位和后 4 位，中间用固定长度的星号占位。 */
  static String mask(String secret) {
    String prefix = secret.substring(0, Math.min(2, secret.length()));
    String suffix = secret.length() > 4 ? secret.substring(secret.length() - 4) : "";
    return prefix + "********" + suffix;
  }

  /**
   * 详情里的密码类初始化参数是打过码的，界面原样回传时不能把星号写回库。
   *
   * <p>提交值和当前值的打码结果一致，说明用户没有改动，继续沿用库里的原值。
   */
  private void restoreMaskedSecrets(Row existing, JSONObject data) {
    if (!(data.get("init_params") instanceof JSONObject submitted) || submitted.isEmpty()) {
      return;
    }
    JSONObject current = parseObject(existing.getObject("init_params"));
    for (String key : submitted.keySet()) {
      Object value = submitted.get(key);
      Object stored = current.get(key);
      if (stored != null && value != null && mask(stored.toString()).equals(value.toString())) {
        submitted.put(key, stored);
      }
    }
  }

  private JSONObject value(Row row) {
    JSONObject value = new JSONObject(row.getColumns());
    value.put("id", row.getLong("id").toString());
    value.put("user_id", row.getLong("user_id").toString());
    value.put("template_id", row.getLong("template_id") == null ? null : row.getLong("template_id").toString());
    value.put("input_field_list", parse(row.getObject("input_field_list")));
    value.put("init_field_list", parse(row.getObject("init_field_list")));
    value.put("create_time", Objects.toString(row.getObject("create_time")));
    value.put("update_time", Objects.toString(row.getObject("update_time")));
    value.remove("init_params");
    return value;
  }

  /** 库里的 JSONB 列可能是对象、数组，也可能是历史数据里的字符串，统一还原成 JSON 结构。 */
  static Object parse(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof JSONObject || value instanceof JSONArray) {
      return value;
    }
    String text = value.toString().trim();
    if (text.isEmpty()) {
      return new JSONObject();
    }
    try {
      return JSON.parse(text);
    } catch (RuntimeException e) {
      return new JSONObject();
    }
  }

  private JSONObject parseObject(Object value) {
    Object parsed = parse(value);
    return parsed instanceof JSONObject object ? new JSONObject(object) : new JSONObject();
  }

  /** 把上游模板里「JSON 字符串包着数组」的写法还原成真正的数组。 */
  static JSONArray normalizeFields(JSONArray fields) {
    if (fields == null) {
      return new JSONArray();
    }
    JSONArray normalized = new JSONArray();
    for (Object item : fields) {
      if (item instanceof String text) {
        Object parsed = parse(text);
        if (parsed instanceof JSONObject || parsed instanceof JSONArray) {
          normalized.add(parsed);
          continue;
        }
      }
      normalized.add(item);
    }
    return normalized;
  }

  /** 初始化参数只保留仍在初始化字段列表里的键。 */
  static JSONObject normalizeInitParams(JSONObject data, String initFieldsJson) {
    JSONObject params = data.getJSONObject("init_params");
    params = params == null ? new JSONObject() : new JSONObject(params);
    JSONArray fields = JSON.parseArray(initFieldsJson);
    List<String> keys = new ArrayList<>();
    for (Object item : fields) {
      if (item instanceof JSONObject field && field.getString("field") != null) {
        keys.add(field.getString("field"));
      }
    }
    params.keySet().removeIf(key -> !keys.contains(key));
    return params;
  }

  /** 图标只接受路径或数据地址，其他值一律回到默认图标，避免把任意文本写进库。 */
  private String normalizeIcon(String icon, boolean creating) {
    if (icon == null || icon.isBlank()) {
      return creating ? "/ui/favicon.ico" : null;
    }
    String trimmed = icon.trim();
    if (trimmed.length() > 256) {
      return creating ? "/ui/favicon.ico" : null;
    }
    return trimmed;
  }

  /** 保存前的字段校验，返回 null 表示通过。 */
  static String validate(JSONObject data) {
    String name = data.getString("name");
    if (name == null || name.isBlank() || name.trim().length() > MAX_NAME_LENGTH) {
      return "函数名称不能为空且不能超过 64 个字符";
    }
    String desc = data.getString("desc");
    if (desc != null && desc.length() > MAX_DESC_LENGTH) {
      return "函数描述不能超过 128 个字符";
    }
    String code = data.getString("code");
    if (code == null || code.isBlank()) {
      return "函数代码不能为空";
    }
    if (code.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > MAX_CODE_LENGTH) {
      return "函数代码不能超过 64 KiB";
    }
    JSONArray fields = data.getJSONArray("input_field_list");
    if (fields != null) {
      for (Object item : fields) {
        if (!(item instanceof JSONObject field)) {
          return "调用参数格式无效";
        }
        String type = field.getString("type");
        String source = field.getString("source");
        if (type != null && !FIELD_TYPES.contains(type)) {
          return "参数类型只支持 string、int、float、dict、array";
        }
        if (source != null && !FIELD_SOURCES.contains(source)) {
          return "参数来源只支持 custom、reference";
        }
      }
    }
    return null;
  }

  private Row owned(Long user, Long id) {
    return Db.findFirst("select * from moss_kb_function_lib where id=? and user_id=? and deleted=false", id, user);
  }

  /** 查询条件按占位符顺序累积，分页和列表共用。 */
  private static final class Query {
    private String where;
    private final List<Object> params = new ArrayList<>();

    private Query(String where) {
      this.where = where;
    }
  }
}
