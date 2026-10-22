package com.litongjava.mosskb.regression;
import static org.junit.Assert.*;
import java.util.List;
import org.junit.*;
import com.jfinal.kit.Kv;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.model.result.ResultVo;
import nexus.io.model.exception.ParameterValidationException;
import nexus.io.mosskb.model.BackgroundImportRequest;
import nexus.io.mosskb.service.kb.BackgroundImportService;
import nexus.io.mosskb.vo.ParagraphBatchVo;
import nexus.io.tio.utils.json.JsonUtils;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

public class BackgroundImportRegressionTest {
  private long task;
  private long dataset;
  private final long owner = 909090L;
  private int imports;
  private boolean fail;
  private final BackgroundImportService service = new BackgroundImportService() {
    @Override public void dispatch(Long id) { }
    @Override protected ResultVo importDocuments(Long user, Long target, List<ParagraphBatchVo> docs) {
      assertEquals(Long.valueOf(owner), user);
      assertEquals(Long.valueOf(dataset), target);
      assertEquals("test content", docs.get(0).getParagraphs().get(0).getContent());
      imports++;
      return fail ? ResultVo.fail("embedding unavailable") : ResultVo.ok();
    }
  };
  @BeforeClass public static void init() { RegressionDb.init(); }
  @Before public void setup() {
    task = SnowflakeIdUtils.id(); dataset = SnowflakeIdUtils.id();
    Db.save("moss_kb_dataset", Row.by("id", dataset).set("name", "background-test").set("desc", "")
        .set("type", "0").set("user_id", owner));
    Db.save("moss_kb_document_split_task", Row.by("id", task).set("user_id", owner)
        .set("file_name", "test.txt").set("status", "running"));
  }
  @After public void cleanup() {
    Db.deleteById("moss_kb_document_split_task", task);
    Db.deleteById("moss_kb_dataset", dataset);
  }
  private BackgroundImportRequest input() {
    BackgroundImportRequest input = new BackgroundImportRequest(); input.setTaskIds(List.of(task)); return input;
  }
  private void parsed() {
    String result = JsonUtils.toJson(List.of(Kv.by("id", task).set("name", "test.txt")
        .set("content", List.of(Kv.by("title", "test").set("content", "test content")))));
    Db.update("update moss_kb_document_split_task set status='success', result=?::jsonb where id=?", result, task);
  }
  @Test public void waitsForParsingAndImportsOnlyOnce() {
    service.submit(owner, dataset, input()); service.run(task); assertEquals(0, imports);
    parsed(); service.submit(owner, dataset, input()); service.run(task); service.run(task);
    assertEquals(1, imports);
    assertEquals("success", Db.queryStr("select import_status from moss_kb_document_split_task where id=?", task));
  }
  @Test public void failureIsPersisted() {
    parsed(); fail = true; service.submit(owner, dataset, input()); service.run(task);
    assertEquals("failed", Db.queryStr("select import_status from moss_kb_document_split_task where id=?", task));
    assertEquals("embedding unavailable", Db.queryStr("select import_error from moss_kb_document_split_task where id=?", task));
  }
  @Test public void otherTeamsCannotSubmit() {
    try { service.submit(owner + 1, dataset, input()); fail("expected rejection"); }
    catch (ParameterValidationException expected) { assertEquals(0, imports); }
  }
}
