package nexus.io.mosskb.model;

import lombok.Data;

@Data
public class TeamEmailSettings {
  private String email_host;
  private String email_port;
  private String email_host_user;
  private String email_host_password;
  private String from_email;
  private boolean email_use_ssl;
  private boolean email_use_tls;
}
