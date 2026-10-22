-- Java MossKB 数据清空脚本
--
-- 删除业务表与其中的全部数据，保留数据库、扩展和账号。执行后再运行 init.sql 即可得到干净的空库，适合本地反复验证。
--
-- 只删除下面列出的 Java MossKB 业务表，不删除 schema、扩展或同库中的其他表。
--
-- 用法：
--   psql -h 127.0.0.1 -p 5432 -U <数据库用户> -d <数据库名> -v ON_ERROR_STOP=1 -f reset.sql

BEGIN;

DROP TABLE IF EXISTS
  "public"."moss_kb_chat_context",
  "public"."moss_kb_application_chat_record",
  "public"."moss_kb_application_chat",
  "public"."moss_kb_application_temp_setting",
  "public"."moss_kb_application_public_access_client",
  "public"."moss_kb_application_access_token",
  "public"."moss_kb_application_api_key",
  "public"."moss_kb_application_dataset_mapping",
  "public"."moss_kb_application",
  "public"."moss_kb_sentence",
  "public"."moss_kb_paragraph",
  "public"."moss_kb_paragraph_summary_cache",
  "public"."moss_kb_problem_paragraph_mapping",
  "public"."moss_kb_problem",
  "public"."moss_kb_document",
  "public"."moss_kb_document_markdown_page_cache",
  "public"."moss_kb_document_markdown_cache",
  "public"."moss_kb_document_split_task",
  "public"."moss_kb_task",
  "public"."moss_kb_embedding_cache",
  "public"."moss_kb_file",
  "public"."moss_kb_dataset",
  "public"."moss_kb_function_lib",
  "public"."moss_kb_model_catalog",
  "public"."moss_kb_model_provider",
  "public"."moss_kb_model",
  "public"."moss_kb_user_api_key",
  "public"."moss_kb_user_token",
  "public"."moss_kb_user",
  "public"."libre_office_converted_mapping",
  "public"."system_setting"
CASCADE;

COMMIT;
