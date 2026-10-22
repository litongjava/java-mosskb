package nexus.io.mosskb.model;
import java.util.List;
import lombok.Data;
@Data
public class BackgroundImportRequest {
  private List<Long> taskIds;
}
