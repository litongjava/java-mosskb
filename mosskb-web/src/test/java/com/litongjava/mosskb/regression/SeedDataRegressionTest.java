package com.litongjava.mosskb.regression;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.BeforeClass;
import org.junit.Test;

import nexus.io.db.activerecord.Db;
import nexus.io.mosskb.service.UserPassword;

/**
 * 种子数据回归测试。
 *
 * <p>db/init.sql 写死的管理员账号、默认模型、平台接入、模型目录与内置函数模板是首次部署能否登录
 * 的前提，这些凭据和条目一旦被改坏，界面会直接不可用。
 *
 * <p>其它测试会往同一个库里写数据（例如新增模型），所以这里只断言种子里的具体条目存在、数量不少于
 * 预期，不锁死总数。
 */
public class SeedDataRegressionTest {

  /** 与 db/init.sql 和数据库设计章节记录一致。 */
  private static final String ADMIN_USERNAME = "admin";
  private static final String ADMIN_DEFAULT_PASSWORD = "123456";

  /** db/init.sql 写入的两条默认模型。 */
  private static final String DEFAULT_LLM = "Gitee DeepSeek V4.1 Flash";
  private static final String DEFAULT_EMBEDDING = "Gitee Qwen3 Embedding 8B";

  /** db/init.sql 写入的平台接入与内置函数模板数量下限。 */
  private static final int EXPECTED_PROVIDERS = 12;
  private static final int EXPECTED_INTERNAL_FUNCTIONS = 5;

  @BeforeClass
  public static void setUp() {
    RegressionDb.init();
  }

  @Test
  public void adminAccountSeededWithDocumentedDefaultPassword() {
    assertEquals(ADMIN_USERNAME, Db.queryStr("select username from moss_kb_user where id = 1"));
    assertEquals("SUPER_ADMIN", Db.queryStr("select role from moss_kb_user where id = 1"));
    assertEquals(Boolean.TRUE, Db.queryBoolean("select is_active from moss_kb_user where id = 1"));

    String stored = Db.queryStr("select password from moss_kb_user where id = 1");
    assertTrue("admin 的初始密码与数据库设计章节记录的不一致", UserPassword.matches(ADMIN_DEFAULT_PASSWORD, stored));
  }

  @Test
  public void defaultInferenceAndEmbeddingModelSeeded() {
    assertEquals(DEFAULT_LLM,
        Db.queryStr("select name from moss_kb_model where name = ? and model_type = 'LLM'", DEFAULT_LLM));
    assertEquals(DEFAULT_EMBEDDING,
        Db.queryStr("select name from moss_kb_model where name = ? and model_type = 'EMBEDDING'", DEFAULT_EMBEDDING));
    assertTrue("缺少可用的推理模型", count("select count(*) from moss_kb_model where model_type = 'LLM'") >= 1);
    assertTrue("缺少可用的向量模型", count("select count(*) from moss_kb_model where model_type = 'EMBEDDING'") >= 1);
  }

  @Test
  public void platformProvidersSeeded() {
    int providers = count("select count(*) from moss_kb_model_provider");
    assertTrue("平台接入少于 " + EXPECTED_PROVIDERS + " 个，实际 " + providers, providers >= EXPECTED_PROVIDERS);
    assertTrue("缺少 Gitee 平台接入，默认模型会没有可用的 provider",
        count("select count(*) from moss_kb_model_provider where provider = 'model_gitee_provider'") == 1);
  }

  @Test
  public void modelCatalogSnapshotSeeded() {
    assertTrue("平台模型目录快照为空，模型选择列表会没有候选",
        count("select count(*) from moss_kb_model_catalog") > 0);
  }

  @Test
  public void internalFunctionTemplatesSeeded() {
    int byTemplateId = count("select count(*) from moss_kb_function_lib where template_id is null");
    int byType = count("select count(*) from moss_kb_function_lib where function_type = 'INTERNAL'");
    assertTrue("内置函数模板少于 " + EXPECTED_INTERNAL_FUNCTIONS + " 个，实际 " + byTemplateId,
        byTemplateId >= EXPECTED_INTERNAL_FUNCTIONS);
    assertTrue("function_type = INTERNAL 的内置函数模板少于 " + EXPECTED_INTERNAL_FUNCTIONS + " 个，实际 " + byType,
        byType >= EXPECTED_INTERNAL_FUNCTIONS);
  }

  private static int count(String sql) {
    Integer value = Db.queryInt(sql);
    return value == null ? -1 : value.intValue();
  }
}
