package com.litongjava.mosskb.regression;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.List;

import org.junit.BeforeClass;
import org.junit.Test;

import com.jfinal.kit.Kv;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.model.upload.UploadResult;
import nexus.io.mosskb.constant.MossKbTableNames;
import nexus.io.mosskb.service.kb.MossKbDocumentSplitTaskService;
import nexus.io.mosskb.vo.MossKbDocumentSplitTaskVo;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

/**
 * 分段预览任务的状态流转回归测试。
 *
 * <p>只验证任务表本身：创建、进度、成功结果、失败原因与归属校验，不调用 OCR，也不依赖任何外部服务。
 */
public class DocumentSplitTaskRegressionTest {

  /** 测试用的用户 id，和种子里的 admin 区分开，避免污染真实数据。 */
  private static final Long TEST_USER_ID = 900000000000000001L;

  private final MossKbDocumentSplitTaskService taskService = new MossKbDocumentSplitTaskService();

  @BeforeClass
  public static void setUp() {
    RegressionDb.init();
  }

  @Test
  public void taskLifecycleKeepsProgressAndResult() {
    Long taskId = startTask("report.pdf", 2048L);
    try {
      MossKbDocumentSplitTaskVo running = taskService.get(TEST_USER_ID, taskId);
      assertNotNull(running);
      assertEquals(MossKbDocumentSplitTaskService.STATUS_RUNNING, running.getStatus());
      assertEquals("running 阶段不应带结果", null, running.getResult());

      // 总页数与进度分别写入，进度按百分比节流后仍应能在最后一步落到 99。
      taskService.markTotal(taskId, 35);
      taskService.markProgress(taskId, 35, 35);
      MossKbDocumentSplitTaskVo halfway = taskService.get(TEST_USER_ID, taskId);
      assertEquals(Integer.valueOf(35), halfway.getTotal());
      assertEquals(Integer.valueOf(99), halfway.getProgress());

      taskService.complete(taskId, List.of(Kv.by("name", "report.pdf").set("id", 12345L)));
      MossKbDocumentSplitTaskVo done = taskService.get(TEST_USER_ID, taskId);
      assertEquals(MossKbDocumentSplitTaskService.STATUS_SUCCESS, done.getStatus());
      assertEquals(Integer.valueOf(100), done.getProgress());
      assertEquals(1, done.getResult().size());
      assertEquals("report.pdf", done.getResult().get(0).getStr("name"));
    } finally {
      delete(taskId);
    }
  }

  @Test
  public void failedTaskKeepsReasonAndHidesResult() {
    Long taskId = startTask("broken.pdf", 512L);
    try {
      taskService.fail(taskId, "扫描页OCR识别失败，请稍后重试");
      MossKbDocumentSplitTaskVo failed = taskService.get(TEST_USER_ID, taskId);
      assertEquals(MossKbDocumentSplitTaskService.STATUS_FAILED, failed.getStatus());
      assertEquals("扫描页OCR识别失败，请稍后重试", failed.getErrorMessage());
      assertNull("失败任务不应返回分段结果", failed.getResult());
      // 超长原因会被截断，避免把整段堆栈写进任务表。
      assertTrue(failed.getErrorMessage().length() <= 1000);
    } finally {
      delete(taskId);
    }
  }

  @Test
  public void taskIsOnlyVisibleToItsOwner() {
    Long taskId = startTask("private.pdf", 256L);
    try {
      assertNull("其他用户不应看到别人的任务", taskService.get(TEST_USER_ID + 1, taskId));
    } finally {
      delete(taskId);
    }
  }

  private Long startTask(String fileName, long fileSize) {
    UploadResult uploadResult = new UploadResult(SnowflakeIdUtils.id(), fileName, fileSize, "http://example.test/f", "md5");
    Long taskId = taskService.start(TEST_USER_ID, uploadResult, fileSize);
    assertNotNull(taskId);
    return taskId;
  }

  private void delete(Long taskId) {
    Db.update("delete from " + MossKbTableNames.moss_kb_document_split_task + " where id = ?", taskId);
  }

  /** 表结构里 result 用 JSONB，写入与读取都要经过一次类型转换。 */
  @Test
  public void resultColumnIsJsonb() {
    String dataType = Db.queryStr(
        "select data_type from information_schema.columns where table_schema='public' and table_name=? and column_name='result'",
        MossKbTableNames.moss_kb_document_split_task);
    assertEquals("result 必须是 jsonb，才能按 JSON 存取分段列表", "jsonb", dataType);
  }

  /** 任务表不需要保存密钥或正文，只保存结果与状态。 */
  @Test
  public void taskRowDoesNotStoreDocumentContent() {
    Long taskId = startTask("plain.pdf", 128L);
    try {
      Row row = Db.findFirst("select result, error_message from " + MossKbTableNames.moss_kb_document_split_task + " where id=?",
          taskId);
      assertNotNull(row);
      assertNull(row.get("result"));
      assertNull(row.getStr("error_message"));
    } finally {
      delete(taskId);
    }
  }
}
