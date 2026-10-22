package com.litongjava.mosskb.regression;

import static org.junit.Assert.*;
import java.util.ArrayList;
import java.util.List;
import org.junit.*;
import com.alibaba.fastjson2.JSONObject;
import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.mosskb.service.*;
import nexus.io.mosskb.model.TeamEmailSettings;
import nexus.io.mosskb.service.kb.ApplicationAccess;
import nexus.io.mosskb.service.kb.DatasetAccess;
import nexus.io.mosskb.service.kb.ModelAccess;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;
import nexus.io.tio.utils.snowflake.SnowflakeIdUtils;

public class TeamIsolationRegressionTest {
  private final List<Long> ids = new ArrayList<>();
  @BeforeClass public static void init() { RegressionDb.init(); }
  private long account(String role, Long team) {
    long id = SnowflakeIdUtils.id();
    Db.save("moss_kb_user", Row.by("id", id).set("username", "test_" + id)
        .set("email", "").set("phone", "").set("nick_name", "").set("source", "LOCAL").set("password", "unused").set("role", role).set("is_active", true)
        .set("deleted", 0).set("tenant_id", team == null ? id : team));
    ids.add(id);
    return id;
  }
  private void login(long id) {
    HttpRequest request = new HttpRequest();
    TioRequestContext.hold(request, null);
    TioRequestContext.setUserId(id);
  }
  @After public void cleanup() {
    for (Long id : ids) { Db.deleteById("moss_kb_user", id); }
    TioRequestContext.release();
  }
  @Test public void settingsAreStoredPerTeam() {
    long a = account("ADMIN", null);
    long b = account("ADMIN", null);
    TeamEmailSettings settings = new TeamEmailSettings();
    settings.setEmail_host("smtp.example.com");
    settings.setEmail_port("465");
    settings.setEmail_host_user("team-a");
    settings.setFrom_email("team-a@example.com");
    settings.setEmail_host_password("secret");
    try {
      new TeamSettingsService().save(a, settings);
      assertEquals(Long.valueOf(1), Db.queryLong("select count(*) from moss_kb_team_setting where team_id = ?", a));
      assertEquals(Long.valueOf(0), Db.queryLong("select count(*) from moss_kb_team_setting where team_id = ?", b));
    } finally {
      Db.update("delete from moss_kb_team_setting where team_id = ?", a);
    }
  }

  @Test public void resourceOwnershipRejectsOtherTeams() {
    long a = account("ADMIN", null);
    long b = account("ADMIN", null);
    long member = account("USER", a);
    for (String table : List.of("moss_kb_application", "moss_kb_dataset", "moss_kb_model")) {
      long resource = SnowflakeIdUtils.id();
      Db.save(table, Row.by("id", resource).set("user_id", a));
      try {
        Long team = TeamAccess.teamId(TeamAccess.account(member));
        if (table.equals("moss_kb_application")) {
          assertTrue(ApplicationAccess.owns(team, resource));
          assertFalse(ApplicationAccess.owns(b, resource));
        } else if (table.equals("moss_kb_dataset")) {
          assertTrue(DatasetAccess.owns(team, resource));
          assertFalse(DatasetAccess.owns(b, resource));
        } else {
          assertTrue(ModelAccess.canUse(team, resource));
          assertFalse(ModelAccess.canUse(b, resource));
        }
      } finally {
        Db.deleteById(table, resource);
      }
    }
  }

  @Test public void administratorCanOnlyManageOwnMembers() {
    long a = account("ADMIN", null);
    long b = account("ADMIN", null);
    long member = account("USER", a);
    long other = account("USER", b);
    login(a);
    assertTrue(TeamAccess.canManage(member));
    assertFalse(TeamAccess.canManage(other));
    assertFalse(TeamAccess.canManage(b));
    assertEquals(400, new UserManagementService().resetPassword(other,
        JSONObject.of("password", "test1234", "re_password", "test1234")).getCode());
    assertEquals(Long.valueOf(a), TeamAccess.teamId(TeamAccess.account(member)));
    login(member);
    assertFalse(TeamAccess.canManage(member));
    assertEquals(400, new UserManagementService().create(JSONObject.of("username", "ignored", "password", "test1234")).getCode());
  }
  @Test public void superAdministratorCreatesTeamAndAdministratorCreatesMember() {
    long superAdmin = account("SUPER_ADMIN", null);
    login(superAdmin);
    String name = "t" + Long.toString(SnowflakeIdUtils.id()).substring(4);
    assertEquals(200, new UserManagementService().create(JSONObject.of("username", name, "password", "test1234", "role", "SUPER_ADMIN")).getCode());
    Row admin = Db.findFirst("select * from moss_kb_user where username = ?", name);
    long team = admin.getLong("id");
    ids.add(team);
    assertEquals("ADMIN", admin.getStr("role"));
    assertEquals(Long.valueOf(team), admin.getLong("tenant_id"));
    login(team);
    String memberName = name + "m";
    assertEquals(200, new UserManagementService().create(JSONObject.of("username", memberName, "password", "test1234", "role", "ADMIN", "tenant_id", superAdmin)).getCode());
    Row member = Db.findFirst("select * from moss_kb_user where username = ?", memberName);
    ids.add(member.getLong("id"));
    assertEquals("USER", member.getStr("role"));
    assertEquals(Long.valueOf(team), member.getLong("tenant_id"));
  }
}
