package nexus.io.mosskb.service.kb;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;

public final class DatasetAccess {
  private DatasetAccess() {}

  public static boolean owns(Long user, Long datasetId) {
    if (user == null) {
      return false;
    }
    Row dataset = Db.findById("moss_kb_dataset", datasetId);
    return dataset != null && (user.equals(dataset.getLong("user_id")));
  }

  public static boolean ownsDocument(Long user, Long dataset, Long document) {
    return owns(user, dataset) && Db.queryLong("select count(*) from moss_kb_document where id=? and dataset_id=?", document, dataset) > 0;
  }
}
