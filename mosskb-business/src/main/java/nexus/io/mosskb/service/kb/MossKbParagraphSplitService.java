package nexus.io.mosskb.service.kb;

import java.util.ArrayList;
import java.util.List;
import com.jfinal.kit.Kv;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.vo.Paragraph;
import nexus.io.mosskb.vo.ParagraphBatchVo;
import nexus.io.model.result.ResultVo;
import nexus.io.tio.utils.crypto.Md5Utils;
import nexus.io.tio.utils.hutool.FilenameUtils;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

public class MossKbParagraphSplitService {
  public ResultVo batch(Long userId, Long datasetId, List<ParagraphBatchVo> documents) {
    Row dataset = Db.findById("moss_kb_dataset", datasetId);
    if (userId == null || dataset == null || (!userId.equals(dataset.getLong("user_id")))) {
      return ResultVo.fail("知识库不存在或无权访问");
    }
    if (documents == null || documents.isEmpty()) {
      return ResultVo.fail("请选择需要导入的文档");
    }
    List<Kv> result = new ArrayList<>();
    for (ParagraphBatchVo input : documents) {
      if (input.getId() == null || input.getParagraphs() == null || input.getParagraphs().isEmpty()) {
        return ResultVo.fail("文档需要文件ID和至少一个有效分段");
      }
      Long existingId = Db.queryLong("select id from moss_kb_document where user_id=? and file_id=? and dataset_id=?", userId, input.getId(), datasetId);
      long documentId = existingId == null ? SnowflakeIdUtils.id() : existingId;
      List<Row> paragraphs = new ArrayList<>();
      int charLength = 0;
      String type = FilenameUtils.getSuffix(input.getName());
      // Remote requests finish before publishing a document or replacing existing paragraphs.
      for (Paragraph p : input.getParagraphs()) {
        if (p.getContent() == null || p.getContent().isBlank()) {
          return ResultVo.fail("文档分段不能为空");
        }
        charLength += p.getContent().length();
        paragraphs.add(Row.by("id", SnowflakeIdUtils.id()).set("source_id", input.getId())
            .set("source_type", type).set("title", p.getTitle()).set("content", p.getContent())
            .set("md5", Md5Utils.md5Hex(p.getContent())).set("status", "2").set("hit_num", 0)
            .set("is_active", true).set("dataset_id", datasetId).set("document_id", documentId)
            .set("embedding", Aop.get(KbEmbeddingService.class).getVectorForModel(p.getContent(), dataset.getLong("embedding_mode_id"))));
      }
      Row document = Row.by("id", documentId).set("file_id", input.getId()).set("user_id", userId)
          .set("name", input.getName()).set("char_length", charLength).set("status", "2")
          .set("is_active", true).set("type", type).set("dataset_id", datasetId)
          .set("paragraph_count", paragraphs.size()).set("hit_handling_method", "optimization")
          .set("directly_return_similarity", 0.9);
      boolean saved = Db.tx(() -> {
        if (existingId == null) {
          Db.save("moss_kb_document", document);
        } else {
          Db.update("moss_kb_document", document);
          Db.update("delete from moss_kb_paragraph where document_id=?", documentId);
        }
        Db.batchSave("moss_kb_paragraph", paragraphs, 2000);
        return true;
      });
      if (!saved) {
        return ResultVo.fail("文档保存失败，请重试");
      }
      result.add(document.toKv());
    }
    return ResultVo.ok(result);
  }
}
