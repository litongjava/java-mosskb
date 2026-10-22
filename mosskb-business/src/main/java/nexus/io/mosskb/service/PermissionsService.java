package nexus.io.mosskb.service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.mosskb.constant.MossKbTableNames;

public class PermissionsService {

  public static final String APPLICATION = "APPLICATION";
  public static final String DATASET = "DATASET";

  public static final String MANAGE = "MANAGE";
  public static final String USE = "USE";
  public static final String DELETE = "DELETE";

  public static final List<String> defaultAdminPermissions = Arrays.asList("USER:READ", "USER:EDIT",
      //
      "DATASET:CREATE", "DATASET:READ", "DATASET:EDIT",
      //
      "APPLICATION:READ", "APPLICATION:CREATE", "APPLICATION:DELETE", "APPLICATION:EDIT",
      //
      "SETTING:READ",
      //
      "MODEL:READ", "MODEL:EDIT", "MODEL:DELETE", "MODEL:CREATE",
      //
      "FUNCTION:READ", "FUNCTION:CREATE");

  public List<String> getPermissionsByRole(String role) {
    return getPermissionsByRole(role, TioRequestContext.getUserIdLong());
  }

  public List<String> getPermissionsByRole(String role, Long userId) {
    Row account = TeamAccess.account(userId);
    if (account == null) {
      return new ArrayList<>();
    }
    userId = TeamAccess.teamId(account);
    // Switch-case to return the permissions based on the role
    switch (role.toLowerCase()) {
    case "super_admin":
    case "admin":
      return getAdminPermissions(userId);
    case "user":
      List<String> permissions = new ArrayList<>(Arrays.asList("DATASET:CREATE", "DATASET:READ", "APPLICATION:READ", "APPLICATION:CREATE", "MODEL:READ", "MODEL:CREATE", "FUNCTION:READ", "FUNCTION:CREATE"));
      for (String module : Arrays.asList(APPLICATION, DATASET)) {
        String table = APPLICATION.equals(module) ? "moss_kb_application" : "moss_kb_dataset";
        List<Long> ids = Db.query("select id from " + table + " where user_id=?", userId);
        permissions.addAll(genPermissions(module, MANAGE, ids));
        permissions.addAll(genPermissions(module, USE, ids));
        permissions.addAll(genPermissions(module, DELETE, ids));
      }
      return permissions;
    default:
      return new ArrayList<>();
    }
  }

  private List<String> getAdminPermissions(Long userId) {
    //dataset ids
    List<Long> datasetIds = Db.query("select id from moss_kb_dataset where user_id = ?", userId);
    //appliction id
    List<Long> applicationIds = Db.query("select id from moss_kb_application where user_id = ?", userId);

    List<String> permissions = new ArrayList<>();
    permissions.addAll(defaultAdminPermissions);

    permissions.addAll(genPermissions(APPLICATION, MANAGE, applicationIds));
    permissions.addAll(genPermissions(APPLICATION, USE, applicationIds));
    permissions.addAll(genPermissions(APPLICATION, DELETE, applicationIds));

    permissions.addAll(genPermissions(DATASET, MANAGE, datasetIds));
    permissions.addAll(genPermissions(DATASET, USE, datasetIds));
    permissions.addAll(genPermissions(DATASET, DELETE, datasetIds));

    return permissions;
  }

  public List<String> genPermissions(String moduleName, String permissionName, List<Long> targetList) {
    List<String> permissions = new ArrayList<>();
    for (Long id : targetList) {
      permissions.add(moduleName + ":" + permissionName + ":" + id);
    }
    return permissions;
  }
}
