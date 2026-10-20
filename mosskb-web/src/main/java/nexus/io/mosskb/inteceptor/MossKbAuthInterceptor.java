package nexus.io.mosskb.inteceptor;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

import nexus.io.db.activerecord.Db;
import nexus.io.db.activerecord.Row;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.ApiKeyAuth;
import nexus.io.mosskb.service.MossKbAuthService;
import nexus.io.mosskb.service.kb.ApplicationAccess;
import nexus.io.mosskb.service.kb.DatasetAccess;
import nexus.io.mosskb.service.kb.ModelAccess;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;
import nexus.io.tio.http.common.HttpResponseStatus;
import nexus.io.tio.http.common.RequestLine;
import nexus.io.tio.http.server.intf.HttpRequestInterceptor;
import nexus.io.tio.utils.hutool.StrUtil;
import nexus.io.tio.utils.jwt.JwtUtils;

public class MossKbAuthInterceptor implements HttpRequestInterceptor {

  /** Administrator-only prefixes: account management, mail settings and team management. */
  private static final String[] ADMIN_ONLY_PREFIXES = {"/api/user_manage", "/api/email_setting", "/api/team"};

  /** Paths a token without a local account may still reach, for shared chat links. */
  private static final String[] PUBLIC_PATHS = {"/api/application/profile"};

  /** Paths a token without a local account may still reach, for shared chat links. */
  private static final Pattern[] PUBLIC_PATH_PATTERNS = {
      Pattern.compile("/api/application/\\d+/chat/open"),
      Pattern.compile("/api/application/chat_message/\\d+"),
      Pattern.compile("/api/application/\\d+/chat/\\d+/context(/compact)?"),
      Pattern.compile("/api/application/\\d+/chat/client/\\d+(/\\d+)?"),
      Pattern.compile("/api/application/\\d+/chat/\\d+/chat_record/\\d+/\\d+"),
      Pattern.compile("/api/application/\\d+/chat/\\d+/chat_record/\\d+(/vote)?"),
      Pattern.compile("/api/application/\\d+/document/\\d+/preview"),
      // 小程序访客令牌：智能提示资料、建会话与提问，应用范围在服务层核对。
      // 管理端小程序码接口不在其中，仍然只对已登录的后台账号开放。
      Pattern.compile("/api/miniapp/application/\\d+"),
      Pattern.compile("/api/miniapp/chat/open/\\d+"),
      Pattern.compile("/api/miniapp/chat/\\d+/message")};

  /** 函数图标：文件名是随机串，列表页和第三方嵌入页都要直接引用，取图不要求登录。 */
  private static final Pattern FUNCTION_ICON_PATH = Pattern
      .compile("/api/function_lib/icon/[0-9a-f]{32}\\.(png|jpg|jpeg|gif|webp|bmp)");

  private static final Pattern RESOURCE_PATH = Pattern.compile("^/api/(dataset|application|model)/(\\d+)(/.*)?$");

  /**
   * 文档全文预览与下载原文件：预览链接不需要登录，按分享链接对待，
   * 能否看到内容由服务层按「文档是否属于该应用关联的知识库」判断。
   */
  private static final Pattern DOCUMENT_PREVIEW_PATH = Pattern
      .compile("/api/application/\\d+/document/\\d+/(preview_content|file)");

  /** Paths that carry an application id directly under /api/application. */
  private static final Pattern APPLICATION_PATH = Pattern.compile("^/api/application/(\\d+)(/.*)?$");

  /** Nested ids that must belong to the same dataset as the path. */
  private static final String[] NESTED_TYPES = {"document", "paragraph", "problem"};

  private static final String ACCOUNT_STATE = """
      select role, is_active, deleted, token_version
      from moss_kb_user
      where id = ?
      """;

  private static final String COUNT_DOCUMENT = """
      select count(*)
      from moss_kb_document
      where id = ?
        and dataset_id = ?
      """;

  private static final String COUNT_PARAGRAPH = """
      select count(*)
      from moss_kb_paragraph
      where id = ?
        and dataset_id = ?
      """;

  private static final String COUNT_PROBLEM = """
      select count(*)
      from moss_kb_problem
      where id = ?
        and dataset_id = ?
      """;

  private Object body = null;

  public MossKbAuthInterceptor() {
  }

  public MossKbAuthInterceptor(Object body) {
    this.body = body;
  }

  @Override
  public HttpResponse doBeforeHandler(HttpRequest request, RequestLine requestLine, HttpResponse responseFromCache) {
    String authorization = request.getHeader("authorization");
    String rawToken = authorization == null ? null : authorization.replaceFirst("(?i)^Bearer\\s+", "");

    // API keys are opaque secrets, so they never reach the JWT checks below.
    if (ApiKeyAuth.isApiKey(rawToken)) {
      return doBeforeApiKeyHandler(request, requestLine, rawToken);
    }

    MossKbAuthService authService = Aop.get(MossKbAuthService.class);
    Long userId = authService.getIdByToken(authorization);
    String path = requestLine.getPath();

    // 文档预览按分享链接处理：没有登录令牌也放行，登录与否得到的结果一致。
    // 带了有效令牌时仍然记下身份，方便日志与审计。
    if (isDocumentPreviewPath(path)) {
      if (userId != null) {
        TioRequestContext.setUserId(userId);
      }
      return null;
    }

    // 函数图标同理：文件名是随机串，列表页和嵌入页都要能直接取图。
    if (FUNCTION_ICON_PATH.matcher(path).matches()) {
      if (userId != null) {
        TioRequestContext.setUserId(userId);
      }
      return null;
    }

    if (userId == null) {
      HttpResponse response = TioRequestContext.getResponse();
      response.setStatus(HttpResponseStatus.C401);

      if (body != null) {
        response.setJson(body);
      }
      return response;
    }

    Row account = Db.findFirst(ACCOUNT_STATE, userId);
    boolean member = account != null;
    if (member && (!Boolean.TRUE.equals(account.getBoolean("is_active")) || account.getInt("deleted") != 0)) {
      return deny(HttpResponseStatus.C401);
    }
    if (member) {
      Object revision = JwtUtils.getPayload(rawToken).get("token_version");
      long tokenVersion = revision == null ? 0 : Long.parseLong(revision.toString());
      if (tokenVersion != account.getLong("token_version")) {
        return deny(HttpResponseStatus.C401);
      }
    }

    if (requiresAdministrator(path) && (!member || !"ADMIN".equalsIgnoreCase(account.getStr("role")))) {
      return deny(HttpResponseStatus.C403);
    }
    if (!member && !isPublicPath(path)) {
      return deny(HttpResponseStatus.C403);
    }
    if (member && userId != 1L && !ownsRequestedResource(userId, path)) {
      return deny(HttpResponseStatus.C403);
    }

    TioRequestContext.setUserId(userId);
    return null;
  }

  /**
   * API key requests: the key owner becomes the request identity, and the key itself decides
   * which application may be reached and which origins may call it.
   */
  private HttpResponse doBeforeApiKeyHandler(HttpRequest request, RequestLine requestLine, String rawToken) {
    ApiKeyAuth.ApiKeyPrincipal principal = ApiKeyAuth.resolve(rawToken);
    if (principal == null || !principal.active()) {
      return deny(HttpResponseStatus.C401);
    }
    Row account = Db.findFirst(ACCOUNT_STATE, principal.userId());
    if (account == null || !Boolean.TRUE.equals(account.getBoolean("is_active")) || account.getInt("deleted") != 0) {
      return deny(HttpResponseStatus.C401);
    }
    String path = requestLine.getPath();
    if (!withinKeyScope(principal, path) || !acceptsCaller(principal, request)) {
      return deny(HttpResponseStatus.C403);
    }
    TioRequestContext.setUserId(principal.userId());
    return null;
  }

  /** An application key only reaches its own application; an account key reaches the whole account. */
  private boolean withinKeyScope(ApiKeyAuth.ApiKeyPrincipal principal, String path) {
    if (!principal.applicationKey()) {
      return true;
    }
    if (!path.startsWith("/api/application/")) {
      return false;
    }
    Matcher application = APPLICATION_PATH.matcher(path);
    return !application.matches() || principal.applicationId().equals(Long.valueOf(application.group(1)));
  }

  /** Cross-origin settings only gate key callers: same-origin and server-to-server calls pass through. */
  private boolean acceptsCaller(ApiKeyAuth.ApiKeyPrincipal principal, HttpRequest request) {
    String origin = request.getOrigin();
    if (StrUtil.isBlank(origin)) {
      return true;
    }
    String host = request.getHost();
    if (host != null && origin.contains(host)) {
      return true;
    }
    if (!principal.allowCrossDomain()) {
      return false;
    }
    String[] allowed = principal.crossDomainList();
    if (allowed == null || allowed.length == 0) {
      return true;
    }
    for (String item : allowed) {
      if ("*".equals(item) || origin.equalsIgnoreCase(item)) {
        return true;
      }
    }
    return false;
  }

  /** 文档预览与下载原文件的路径，这两个路径不要求登录。 */
  private boolean isDocumentPreviewPath(String path) {
    return DOCUMENT_PREVIEW_PATH.matcher(path).matches();
  }

  private boolean requiresAdministrator(String path) {
    for (String prefix : ADMIN_ONLY_PREFIXES) {
      if (path.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  private boolean isPublicPath(String path) {
    for (String allowed : PUBLIC_PATHS) {
      if (path.equals(allowed)) {
        return true;
      }
    }
    for (Pattern allowed : PUBLIC_PATH_PATTERNS) {
      if (allowed.matcher(path).matches()) {
        return true;
      }
    }
    return false;
  }

  /** Checks ownership of /api/{dataset|application|model}/{id} and of nested document, paragraph and problem ids. */
  private boolean ownsRequestedResource(Long userId, String path) {
    Matcher resource = RESOURCE_PATH.matcher(path);
    if (!resource.matches()) {
      return true;
    }
    String type = resource.group(1);
    String suffix = resource.group(3);
    Long id = Long.valueOf(resource.group(2));
    boolean page = !"model".equals(type) && suffix != null && suffix.matches("/\\d+");
    boolean chat = "application".equals(type) && suffix != null && suffix.startsWith("/chat/");
    boolean owns = page || chat || ("dataset".equals(type) ? DatasetAccess.owns(userId, id)
        : "application".equals(type) ? ApplicationAccess.owns(userId, id) : ModelAccess.owns(userId, id));
    if (!owns || !"dataset".equals(type) || suffix == null) {
      return owns;
    }
    return nestedIdsBelongToDataset(id, suffix);
  }

  private boolean nestedIdsBelongToDataset(Long datasetId, String suffix) {
    for (String child : NESTED_TYPES) {
      Matcher childId = Pattern.compile("/" + child + "/(\\d+)(?=/[a-z_]|$)").matcher(suffix);
      if (childId.find() && countChild(child, Long.valueOf(childId.group(1)), datasetId) == 0) {
        return false;
      }
    }
    return true;
  }

  private long countChild(String child, Long childId, Long datasetId) {
    String sql = switch (child) {
      case "document" -> COUNT_DOCUMENT;
      case "paragraph" -> COUNT_PARAGRAPH;
      default -> COUNT_PROBLEM;
    };
    return Db.queryLong(sql, childId, datasetId);
  }

  private HttpResponse deny(HttpResponseStatus status) {
    HttpResponse denied = TioRequestContext.getResponse();
    denied.setStatus(status);
    return denied;
  }

  @Override
  public void doAfterHandler(HttpRequest request, RequestLine requestLine, HttpResponse response, long cost) throws Exception {
  }
}
