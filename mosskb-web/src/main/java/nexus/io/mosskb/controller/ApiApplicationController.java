package nexus.io.mosskb.controller;

import com.alibaba.fastjson2.JSONObject;

import nexus.io.annotation.Delete;
import nexus.io.annotation.Get;
import nexus.io.annotation.Post;
import nexus.io.annotation.Put;
import nexus.io.annotation.RequestPath;
import nexus.io.db.TableInput;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.kb.MossKbApplicationAccessTokenService;
import nexus.io.mosskb.service.kb.MossKbApplicationCharRecordService;
import nexus.io.mosskb.service.kb.MossKbApplicationEmbedService;
import nexus.io.mosskb.service.kb.MossKbApplicationHitTestService;
import nexus.io.mosskb.service.kb.MossKbApplicationService;
import nexus.io.mosskb.service.kb.MossKbApplicationStatisticsService;
import nexus.io.mosskb.vo.MossKbApplicationVo;
import nexus.io.model.result.ResultVo;
import nexus.io.table.constants.Operators;
import nexus.io.tio.boot.http.TioRequestContext;
import nexus.io.tio.http.common.HttpRequest;
import nexus.io.tio.http.common.HttpResponse;
import nexus.io.tio.http.server.util.Resps;
import nexus.io.tio.utils.hutool.StrUtil;
import nexus.io.tio.utils.json.FastJson2Utils;
import nexus.io.tio.utils.json.JsonUtils;

@RequestPath("/api/application")
public class ApiApplicationController {

  @Get("/{applicationId}/chat/open")
  public ResultVo openPublished(Long applicationId) {
    return Aop.get(nexus.io.mosskb.service.kb.MossKbApplicationChatService.class).openPublished(applicationId);
  }

  @Post("")
  public ResultVo create(MossKbApplicationVo application) {
    Long userId = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationService.class).create(userId, application);
  }

  @Put("/{applicationId}")
  public ResultVo update(Long applicationId, HttpRequest request) {

    String bodyString = request.getBodyString();
    MossKbApplicationVo application = JsonUtils.parse(bodyString, MossKbApplicationVo.class);

    Long userId = TioRequestContext.getUserIdLong();
    application.setId(applicationId);
    return Aop.get(MossKbApplicationService.class).update(userId, application);
  }

  @Delete("/{applicationId}")
  public ResultVo delete(Long applicationId) {
    Long userId = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationService.class).delete(userId, applicationId);
  }

  @Get("/{applicationId}")
  public ResultVo getById(Long applicationId) {
    Long userId = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationService.class).get(userId, applicationId);
  }

  @Get("")
  public ResultVo list() {
    Long userId = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationService.class).list(userId);
  }

  @Get("/{pageNo}/{pageSize}")
  public ResultVo page(Integer pageNo, Integer pageSize, String name) {
    TableInput tableInput = new TableInput();
    tableInput.setPageNo(pageNo).setPageSize(pageSize);
    Long owner = TioRequestContext.getUserIdLong();
    tableInput.set("user_id", owner);
    //tableInput.setSearchKey(name);
    tableInput.set("name", name);
    tableInput.set("name_op", Operators.CT);
    tableInput.orderBy("name");
    return Aop.get(MossKbApplicationService.class).page(tableInput);
  }

  @Get("/{applicationId}/access_token")
  public ResultVo getAccessToken(Long applicationId) {
    if (!nexus.io.mosskb.service.kb.ApplicationAccess.owns(TioRequestContext.getUserIdLong(), applicationId)) {
      return ResultVo.fail("无权访问应用");
    }
    return Aop.get(MossKbApplicationAccessTokenService.class).getById(applicationId);
  }

  /** 公开访问链接配置：启停、重置短令牌、访问次数、白名单与对话语言。 */
  @Put("/{applicationId}/access_token")
  public ResultVo updateAccessToken(Long applicationId, HttpRequest request) {
    return Aop.get(MossKbApplicationAccessTokenService.class).update(TioRequestContext.getUserIdLong(), applicationId,
        body(request));
  }

  @Get("/{applicationId}/document/{documentId}/preview")
  public ResultVo previewDocument(Long applicationId, Long documentId, HttpRequest request) {
    Long clientId = TioRequestContext.getUserIdLong();
    return Aop.get(nexus.io.mosskb.service.kb.MossKbDocumentService.class).preview(clientId, applicationId, documentId,
        request.getLong("paragraph_id"));
  }

  /** 文档全文预览：按文件类型返回预览方式与正文，无原文件时退回分段正文；预览链接不需要登录。 */
  @Get("/{applicationId}/document/{documentId}/preview_content")
  public ResultVo previewDocumentContent(Long applicationId, Long documentId) {
    return Aop.get(nexus.io.mosskb.service.kb.MossKbDocumentPreviewService.class).content(applicationId, documentId);
  }

  /** 文档原文件：默认按 inline 输出用于在线预览，download=true 时按附件下载。 */
  @Get("/{applicationId}/document/{documentId}/file")
  public HttpResponse previewDocumentFile(Long applicationId, Long documentId, HttpRequest request) {
    String download = request.getParam("download");
    boolean asAttachment = "true".equalsIgnoreCase(download) || "1".equals(download);
    return Aop.get(nexus.io.mosskb.service.kb.MossKbDocumentPreviewService.class).file(applicationId, documentId,
        asAttachment, request);
  }

  @Get("/{applicationId}/statistics/chat_record_aggregate_trend")
  public ResultVo statisticsOfCharRecordAggreagteTrend(Long applicationId, String start_time, String end_time) {
    return Aop.get(MossKbApplicationStatisticsService.class).chatRecordAggregateTrend(TioRequestContext.getUserIdLong(),
        applicationId, start_time, end_time);
  }

  @Get("/{applicationId}/statistics/chat_record_aggregate")
  public ResultVo statisticsOfCharRecordAggreagte(Long applicationId, String start_time, String end_time) {
    return Aop.get(MossKbApplicationStatisticsService.class).chatRecordAggregate(TioRequestContext.getUserIdLong(),
        applicationId, start_time, end_time);
  }

  @Get("/{applicationId}/statistics/customer_count")
  public ResultVo statisticsOfCustomerCount(Long applicationId, String start_time, String end_time) {
    return Aop.get(MossKbApplicationStatisticsService.class).customerCount(TioRequestContext.getUserIdLong(),
        applicationId, start_time, end_time);
  }

  @Get("/{applicationId}/statistics/customer_count_trend")
  public ResultVo statisticsOfCustomerCountTrend(Long applicationId, String start_time, String end_time) {
    return Aop.get(MossKbApplicationStatisticsService.class).customerCountTrend(TioRequestContext.getUserIdLong(),
        applicationId, start_time, end_time);
  }

  @Get("/{applicationId}/model")
  public ResultVo listApplicaionModel(Long applicationId) {
    Long userId = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationService.class).listApplicaionModel(userId, applicationId);
  }

  @Get("/{applicationId}/model_params_form/{modelId}")
  public ResultVo setModelId(Long applicationId, Long modelId) {
    Long userIdLong = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationService.class).setModelId(userIdLong, applicationId, modelId);
  }

  @Get("/{applicationId}/list_dataset")
  public ResultVo listApplicaionDataset(Long applicationId) {
    Long userId = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationService.class).listApplicaionDataset(userId, applicationId);
  }

  @Get("/{applicationId}/chat/{chatId}/chat_record/{recordId}")
  public ResultVo getRecord(Long applicationId, Long chatId, Long recordId) {
    Long userId = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationCharRecordService.class).get(userId, applicationId, chatId, recordId);
  }

  @Get("/{applicationId}/hit_test")
  public ResultVo hitTest(Long applicationId, HttpRequest request) {
    Long userId = TioRequestContext.getUserIdLong();

    String query_text = request.getParam("query_text");
    Double similarity = request.getDouble("similarity");
    Integer top_number = request.getInt("top_number");
    String search_mode = request.getParam("search_mode");
    return Aop.get(MossKbApplicationHitTestService.class).hitTest(userId, applicationId, query_text, similarity, top_number, search_mode);
  }

  /**
   * 浮窗嵌入：返回一段脚本，第三方页面引入后在右下角挂出对话入口。
   * 脚本按站点地址拼出对话页地址，并带上编排声明的接口入参。
   */
  @Get("/embed")
  public HttpResponse embed(HttpRequest request) {
    String protocol = request.getParam("protocol");
    String host = request.getParam("host");
    Long token = longParam(request, "token");
    return Resps.js(request, Aop.get(MossKbApplicationEmbedService.class).script(protocol, host, token, request.getParam()));
  }

  @Post("/authentication")
  public ResultVo authentication(HttpRequest request) {    String authorization = request.getAuthorization();
    String bodyString = request.getBodyString();
    if (StrUtil.isBlank(bodyString)) {
      return ResultVo.fail();
    }

    JSONObject parseObject = FastJson2Utils.parseObject(bodyString);
    Long access_token = parseObject.getLong("access_token");
    return Aop.get(MossKbApplicationAccessTokenService.class).authentication(access_token, authorization);
  }

  @Get("/profile")
  public ResultVo profile(HttpRequest httpRequest) {
    String referer = httpRequest.getReferer();

    Long clientId = TioRequestContext.getUserIdLong();
    return Aop.get(MossKbApplicationService.class).profile(clientId);
  }

  private JSONObject body(HttpRequest request) {
    String bodyString = request.getBodyString();
    return StrUtil.isBlank(bodyString) ? new JSONObject() : FastJson2Utils.parseObject(bodyString);
  }

  /** 查询串里的整型参数：缺省或不是数字时返回 null，由调用方给出默认行为。 */
  private Long longParam(HttpRequest request, String name) {
    String value = request.getParam(name);
    if (StrUtil.isBlank(value)) {
      return null;
    }
    try {
      return Long.valueOf(value.trim());
    } catch (NumberFormatException e) {
      return null;
    }
  }

}
