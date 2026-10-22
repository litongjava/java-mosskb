package nexus.io.mosskb.service.kb;

import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.jfinal.kit.Kv;
import nexus.io.chat.UniChatClient;
import nexus.io.chat.ChatModelResponse;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.mosskb.vo.CredentialVo;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.utils.environment.EnvUtils;

/** Database-backed catalog; catalog membership is never a model ID whitelist. */
public class ModelCatalogService {
  public List<Kv> providers() {
    return providers(null);
  }

  /**
   * @param modelType 目录中登记的模型类型，可为空；为空时返回全部已启用平台
   */
  public List<Kv> providers(String modelType) {
    String sql = """
        select p.provider,p.name,p.icon from moss_kb_model_provider p
        where p.enabled=true
          and (cast(? as text) is null
               or exists (select 1 from jsonb_array_elements(p.model_types) t where t->>'value'=?))
        order by p.sort_order,p.name
        """;
    List<Kv> result = new ArrayList<>();
    for (Row row : Db.find(sql, modelType, modelType)) {
      result.add(row.toKv());
    }
    return result;
  }

  public Row provider(String id) {
    return Db.findFirst("select * from moss_kb_model_provider where provider=? and enabled=true", id);
  }

  public Object types(String provider) {
    Row row = provider(provider);
    return row == null ? new JSONArray() : JSON.parseArray(row.getStr("model_types"));
  }

  public Object form(String provider, String column) {
    if (!List.of("credential_form", "params_form").contains(column)) {
      throw new IllegalArgumentException("Invalid form");
    }
    Row row = provider(provider);
    return row == null ? new JSONArray() : JSON.parseArray(row.getStr(column));
  }

  public List<Kv> models(String provider, String type) {
    String sql = """
        select model_id as name,description as desc,model_type
        from moss_kb_model_catalog c
        where provider=? and model_type=? and enabled=true
          and exists(select 1 from moss_kb_model_provider p where p.provider=c.provider and p.enabled=true)
        order by model_id
        """;
    List<Kv> result = new ArrayList<>();
    for (Row row : Db.find(sql, provider, type)) {
      result.add(row.toKv());
    }
    return result;
  }

  public static String baseUrl(String value) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException("请填写 API 域名");
    }
    String base = value.trim().replaceAll("/+$", "");
    URI uri = URI.create(base);
    if ((!"https".equals(uri.getScheme()) && !"http".equals(uri.getScheme())) || uri.getHost() == null
        || uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null) {
      throw new IllegalArgumentException("API 域名须为 HTTP(S) 基础地址，不含密钥、查询参数或片段");
    }
    return base;
  }

  public static String modelId(String value) {
    if (value == null || value.isBlank() || value.length() > 256 || value.chars().anyMatch(Character::isISOControl)) {
      throw new IllegalArgumentException("请填写有效的模型 ID（最多 256 字符）");
    }
    return value.trim();
  }

  public static CredentialVo credential(Row model) {
    Object raw = model.get("credential");
    JSONObject object = raw == null ? new JSONObject() : raw instanceof java.util.Map ? (JSONObject) JSON.toJSON(raw) : JSON.parseObject(raw.toString());
    CredentialVo credential = new CredentialVo();
    credential.setApi_base(object.getString("api_base"));
    credential.setApi_key(object.getString("api_key"));
    // Only the two seeded Gitee models may use the server's Gitee credential.
    if ((Long.valueOf(1001).equals(model.getLong("id")) || Long.valueOf(1002).equals(model.getLong("id"))) && object.isEmpty()) {
      credential.setApi_base(KnowledgeModelService.baseUrl());
      credential.setApi_key(EnvUtils.get("GITEE_API_KEY"));
    }
    return credential;
  }

  public static boolean admin(Long userId) {
    return userId != null && Db.queryLong("select count(*) from moss_kb_user where id=? and role='SUPER_ADMIN' and is_active=true and deleted=0", userId) > 0;
  }

  public ResultVo discover(Long userId, JSONObject input) {
    if (!admin(userId)) {
      return ResultVo.fail(403, "仅管理员可管理共享模型目录");
    }
    try {
      String base = baseUrl(input.getString("api_base"));
      String key = input.getString("api_key");
      if (key == null || key.isBlank()) {
        return ResultVo.fail(400, "请提供该平台的 API Key；发现操作不保存凭据");
      }
      ChatModelResponse response = UniChatClient.getModels(base, key);
      if (response == null || response.getData() == null) {
        return ResultVo.fail(400, "模型发现失败，请检查平台是否支持 /models 接口及密钥权限");
      }
      return ResultVo.ok(response.getData());
    } catch (Exception e) {
      return ResultVo.fail(400, "模型发现失败，请检查 API 地址及凭据");
    }
  }

  public ResultVo saveCatalog(Long userId, JSONObject input) {
    if (!admin(userId)) {
      return ResultVo.fail(403, "仅管理员可管理共享模型目录");
    }
    try {
      String provider = input.getString("provider");
      if (provider(provider) == null) {
        return ResultVo.fail(400, "供应商不存在或已停用");
      }
      JSONArray models = input.getJSONArray("models");
      if (models == null || models.size() > 5000) {
        return ResultVo.fail(400, "models 必须是最多 5000 项的数组");
      }
      for (int i = 0; i < models.size(); i++) {
        JSONObject model = models.getJSONObject(i);
        modelId(model.getString("name"));
        if (!List.of("LLM", "EMBEDDING").contains(model.getString("model_type"))) {
          return ResultVo.fail(400, "当前支持 LLM 和 EMBEDDING 类型");
        }
      }
      String upsert = """
          insert into moss_kb_model_catalog(provider,model_type,model_id,description,source,enabled)
          values(?,?,?,?,?,?)
          on conflict(provider,model_type,model_id)
          do update set description=excluded.description,source=excluded.source,enabled=excluded.enabled,updated_at=now()
          """;
      Db.tx(() -> {
        for (int i = 0; i < models.size(); i++) {
          JSONObject model = models.getJSONObject(i);
          Db.update(upsert,
              provider, model.getString("model_type"), modelId(model.getString("name")), model.getString("desc"),
              "admin", !Boolean.FALSE.equals(model.getBoolean("enabled")));
        }
        return true;
      });
      return ResultVo.ok(Kv.by("updated", models.size()));
    } catch (IllegalArgumentException e) {
      return ResultVo.fail(400, e.getMessage());
    }
  }
}
