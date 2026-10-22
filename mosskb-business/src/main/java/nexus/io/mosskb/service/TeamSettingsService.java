package nexus.io.mosskb.service;

import nexus.io.db.activerecord.Db;
import nexus.io.model.body.RespBodyVo;
import nexus.io.mosskb.model.TeamEmailSettings;
import nexus.io.mosskb.utils.ParameterValidationUtils;
import nexus.io.tio.utils.json.JsonUtils;
import nexus.io.tio.utils.validator.ParameterValidator;

public class TeamSettingsService {
  public RespBodyVo read(Long team) {
    String value = Db.queryStr("""
        select value::text from moss_kb_team_setting where team_id = ? and name = 'email'
        """, team);
    TeamEmailSettings settings = value == null ? new TeamEmailSettings() : JsonUtils.parse(value, TeamEmailSettings.class);
    if (settings.getEmail_host_password() != null && !settings.getEmail_host_password().isEmpty()) {
      settings.setEmail_host_password("********");
    }
    return RespBodyVo.ok(settings);
  }

  public RespBodyVo save(Long team, TeamEmailSettings input) {
    ParameterValidator.require(input != null, "请求体不能为空");
    ParameterValidationUtils.requiredText(input.getEmail_host(), "SMTP 主机", 254);
    ParameterValidationUtils.requiredText(input.getEmail_port(), "SMTP 端口", 5);
    ParameterValidationUtils.requiredText(input.getEmail_host_user(), "SMTP 用户", 254);
    ParameterValidationUtils.requiredText(input.getFrom_email(), "发件人", 254);
    if ("********".equals(input.getEmail_host_password())) {
      String value = Db.queryStr("""
          select value::text from moss_kb_team_setting where team_id = ? and name = 'email'
          """, team);
      input.setEmail_host_password(value == null ? null : JsonUtils.parse(value, TeamEmailSettings.class).getEmail_host_password());
    }
    Db.update("""
        insert into moss_kb_team_setting(team_id, name, value) values (?, 'email', ?::jsonb)
        on conflict(team_id, name) do update set value = excluded.value
        """, team, JsonUtils.toJson(input));
    return RespBodyVo.ok();
  }
}
