package com.litongjava.mosskb.regression;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.List;

import org.junit.BeforeClass;
import org.junit.Test;

import nexus.io.db.activerecord.Db;
import nexus.io.mosskb.constant.MossKbTableNames;

/**
 * 数据库结构回归测试。
 *
 * <p>保证代码里登记的表名和 db/init.sql 建出来的表一一对应，改名之后不残留旧品牌前缀的表，
 * 并且部署依赖的两个扩展确实装好了。
 */
public class SchemaRegressionTest {

  /** db/init.sql 建出的 public 表数量，与 db/README.md 记录的一致。 */
  private static final int EXPECTED_PUBLIC_TABLES = 31;

  /** 不带业务前缀的表，沿用上游命名约定。 */
  private static final String[] UNPREFIXED_TABLES = { "system_setting", "libre_office_converted_mapping" };

  @BeforeClass
  public static void setUp() {
    RegressionDb.init();
  }

  @Test
  public void registeredTableNamesAllExistInDatabase() {
    List<String> missing = new ArrayList<>();
    for (Field field : MossKbTableNames.class.getFields()) {
      if (!Modifier.isStatic(field.getModifiers())) {
        continue;
      }
      String table = tableName(field);
      Integer count = Db.queryInt(
          "select count(*) from information_schema.tables where table_schema = 'public' and table_name = ?", table);
      if (count == null || count == 0) {
        missing.add(field.getName() + " -> " + table);
      }
    }
    assertTrue("MossKbTableNames 里登记、但数据库里不存在的表：" + missing, missing.isEmpty());
  }

  @Test
  public void constantNameMatchesTableName() {
    List<String> mismatched = new ArrayList<>();
    for (Field field : MossKbTableNames.class.getFields()) {
      if (!Modifier.isStatic(field.getModifiers())) {
        continue;
      }
      String table = tableName(field);
      if (!field.getName().equals(table)) {
        mismatched.add(field.getName() + " -> " + table);
      }
    }
    assertTrue("常量名与表名不一致（该接口的约定是两者相同）：" + mismatched, mismatched.isEmpty());
  }

  @Test
  public void noLegacyPrefixedTableRemains() {
    String legacyPrefix = "ma" + "x_kb_";
    Integer count = Db.queryInt(
        "select count(*) from information_schema.tables where table_schema = 'public' and table_name ~ ?",
        "^" + legacyPrefix);
    assertEquals("数据库里仍然存在旧品牌前缀的表", 0, count == null ? -1 : count.intValue());
  }

  @Test
  public void publicSchemaTableCountMatchesSchemaScript() {
    Integer count = Db.queryInt(
        "select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'");
    assertEquals("public 表数量与 db/init.sql 不一致，改结构后要同步 db/README.md 与部署文档",
        EXPECTED_PUBLIC_TABLES, count == null ? -1 : count.intValue());
  }

  @Test
  public void unprefixedTablesAreTheExpectedOnes() {
    List<String> actual = Db.queryListString(
        "select table_name from information_schema.tables where table_schema = 'public' and table_name !~ ? order by 1",
        "^moss_kb_");
    List<String> expected = new ArrayList<>();
    for (String table : UNPREFIXED_TABLES) {
      expected.add(table);
    }
    expected.sort(String::compareTo);
    assertEquals("不带 moss_kb_ 前缀的表与预期不符", expected, actual);
  }

  @Test
  public void requiredExtensionsInstalled() {
    for (String extension : new String[] { "vector", "pg_trgm" }) {
      Integer count = Db.queryInt("select count(*) from pg_extension where extname = ?", extension);
      assertEquals("缺少扩展 " + extension + "，先按部署文档装好 pgvector 再初始化", 1,
          count == null ? -1 : count.intValue());
    }
  }

  private static String tableName(Field field) {
    try {
      return String.valueOf(field.get(null));
    } catch (IllegalAccessException e) {
      throw new IllegalStateException("读不到 " + field.getName(), e);
    }
  }
}
