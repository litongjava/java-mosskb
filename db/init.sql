-- Java MossKB 数据库初始化与升级（结构 + 初始数据）
-- 在已创建的业务数据库中执行；数据库服务端需先安装 pgvector 和 pg_trgm。
-- psql -h 127.0.0.1 -p 5432 -U <数据库用户> -d <数据库名> -v ON_ERROR_STOP=1 -f db/init.sql
-- 可重复执行：补齐结构及初始数据，保留原有的平台图标更新和失效模型清理逻辑。
-- 管理员初始账号 admin / Kimi@2024，首次登录后修改密码。
-- 清空重建需单独执行 reset.sql；本文件不执行清空业务表操作。

BEGIN;

-- 第一部分：数据库结构
-- 扩展 ---------------------------------------------------------------------
-- vector 提供向量列与余弦距离算子，pg_trgm 提供关键词检索用的文本相似度。
-- 扩展以数据库为单位注册，需要数据库服务端已经安装扩展文件。
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 系统设置 -----------------------------------------------------------------
-- 按类型保存单条系统级配置：type=0 是邮箱设置，type=1 是 RSA 私钥与公钥。
-- 这张表沿用上游项目的命名约定，不带 moss_kb_ 前缀。
CREATE TABLE IF NOT EXISTS "public"."system_setting" (
  "type" INTEGER NOT NULL PRIMARY KEY,
  "meta" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 用户、令牌与密钥 ---------------------------------------------------------
-- 平台用户。token_version 用于让改密、停用后签发的旧令牌立即失效。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_user" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "email" VARCHAR,
  "phone" VARCHAR NOT NULL,
  "nick_name" VARCHAR NOT NULL,
  "username" VARCHAR NOT NULL,
  "password" VARCHAR NOT NULL,
  "role" VARCHAR NOT NULL,
  "is_active" BOOLEAN NOT NULL,
  "source" VARCHAR NOT NULL,
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0,
  "token_version" BIGINT NOT NULL DEFAULT 0,
  -- 界面语言，取 zh-CN / zh-Hant / en-US，为空表示跟随浏览器语言（与公开分享链接的 language 同义）。
  "language" VARCHAR(16)
);

CREATE INDEX IF NOT EXISTS "user_email_index_like" ON "public"."moss_kb_user" USING btree (
  "email" varchar_pattern_ops
);
CREATE INDEX IF NOT EXISTS "user_username_index_like" ON "public"."moss_kb_user" USING btree (
  "username" varchar_pattern_ops
);

-- 登录令牌。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_user_token" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "token" VARCHAR NOT NULL,
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

-- 账号级开放接口密钥。只保存明文前缀加随机串，删除为逻辑删除，停用后立即失效。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_user_api_key" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "secret_key" VARCHAR(128) NOT NULL,
  "user_id" BIGINT NOT NULL,
  "is_active" BOOLEAN NOT NULL DEFAULT TRUE,
  "allow_cross_domain" BOOLEAN NOT NULL DEFAULT FALSE,
  "cross_domain_list" VARCHAR[] NOT NULL DEFAULT '{}',
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS "moss_kb_user_api_key_secret_key"
  ON "public"."moss_kb_user_api_key" ("secret_key");
CREATE INDEX IF NOT EXISTS "moss_kb_user_api_key_user_id"
  ON "public"."moss_kb_user_api_key" ("user_id");

-- 模型与模型目录 -----------------------------------------------------------
-- 平台接入信息：接口地址、协议、能力与表单定义。模型目录以平台为单位挂在下面。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_model_provider" (
  "provider" VARCHAR(128) NOT NULL PRIMARY KEY,
  "name" VARCHAR(200) NOT NULL,
  "icon" TEXT NOT NULL DEFAULT '',
  "api_base" TEXT NOT NULL DEFAULT '',
  "protocol" VARCHAR(40) NOT NULL DEFAULT 'OPENAI_COMPATIBLE',
  "model_types" JSONB NOT NULL,
  "credential_form" JSONB NOT NULL,
  "params_form" JSONB NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT TRUE,
  "sort_order" INT NOT NULL DEFAULT 0,
  "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 平台候选模型目录：管理员选择或同步得到的模型 ID。目录不代表模型一定可用。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_model_catalog" (
  "provider" VARCHAR(128) NOT NULL,
  "model_type" VARCHAR(30) NOT NULL,
  "model_id" VARCHAR(256) NOT NULL,
  "description" TEXT,
  "source" TEXT NOT NULL DEFAULT 'seed',
  "enabled" BOOLEAN NOT NULL DEFAULT TRUE,
  "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  PRIMARY KEY ("provider", "model_type", "model_id")
);

-- 用户创建的模型实例：平台、模型 ID、凭据和参数表单。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_model" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "name" VARCHAR NOT NULL,
  "model_type" VARCHAR NOT NULL,
  "model_name" VARCHAR NOT NULL,
  "provider" VARCHAR NOT NULL,
  "credential" VARCHAR NOT NULL,
  "user_id" BIGINT NOT NULL,
  "meta" JSONB,
  "status" VARCHAR,
  "permission_type" VARCHAR NOT NULL,
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0,
  "model_params_form" JSONB NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS "idx_user_id" ON "public"."moss_kb_model" USING btree ("user_id");

-- 应用与访问凭据 -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."moss_kb_application" (
  "id" BIGINT PRIMARY KEY,
  "code" INT,
  "course_name" VARCHAR,
  "owner_name" VARCHAR,
  "state" INT,
  "name" VARCHAR NOT NULL,
  "desc" VARCHAR NOT NULL,
  "prompt" VARCHAR,
  "prologue" VARCHAR NOT NULL,
  "dialogue_number" INT NOT NULL,
  "dataset_setting" JSONB NOT NULL,
  "model_setting" JSONB NOT NULL,
  "problem_optimization" BOOLEAN NOT NULL,
  "model_id" BIGINT,
  "user_id" BIGINT NOT NULL,
  "icon" VARCHAR,
  "type" VARCHAR NOT NULL,
  "work_flow" JSONB,
  "show_source" BOOLEAN DEFAULT TRUE,
  "multiple_rounds_dialogue" BOOLEAN DEFAULT TRUE,
  "model_params_setting" JSONB NOT NULL,
  "stt_model_id" BIGINT,
  "stt_model_enable" BOOLEAN NOT NULL,
  "tts_model_id" BIGINT,
  "tts_model_enable" BOOLEAN NOT NULL,
  "tts_type" VARCHAR NOT NULL,
  "problem_optimization_prompt" VARCHAR,
  "tts_model_params_setting" JSONB,
  "clean_time" INT,
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS "application_model_id" ON "public"."moss_kb_application" USING btree ("model_id");
CREATE INDEX IF NOT EXISTS "application_stt_model_id" ON "public"."moss_kb_application" USING btree ("stt_model_id");
CREATE INDEX IF NOT EXISTS "application_tts_model_id" ON "public"."moss_kb_application" USING btree ("tts_model_id");
CREATE INDEX IF NOT EXISTS "application_user_id" ON "public"."moss_kb_application" USING btree ("user_id");

-- 公开分享链接。language 为空表示跟随访客浏览器语言。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_application_access_token" (
  "application_id" BIGINT PRIMARY KEY,
  "access_token" BIGINT NOT NULL,
  "is_active" BOOLEAN NOT NULL,
  "access_num" INT NOT NULL,
  "white_active" BOOLEAN NOT NULL,
  "white_list" VARCHAR[] NOT NULL,
  "show_source" BOOLEAN NOT NULL,
  "language" VARCHAR(16),
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS "moss_kb_application_access_token_access_token" ON "public"."moss_kb_application_access_token" USING btree ("access_token");

COMMENT ON COLUMN "public"."moss_kb_application_access_token"."language" IS '公开分享链接的对话语言，为空表示跟随浏览器语言';

-- 应用级开放接口密钥。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_application_api_key" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "secret_key" VARCHAR(128) NOT NULL,
  "application_id" BIGINT NOT NULL,
  "user_id" BIGINT NOT NULL,
  "is_active" BOOLEAN NOT NULL DEFAULT TRUE,
  "allow_cross_domain" BOOLEAN NOT NULL DEFAULT FALSE,
  "cross_domain_list" VARCHAR[] NOT NULL DEFAULT '{}',
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS "moss_kb_application_api_key_secret_key"
  ON "public"."moss_kb_application_api_key" ("secret_key");
CREATE INDEX IF NOT EXISTS "moss_kb_application_api_key_application_id"
  ON "public"."moss_kb_application_api_key" ("application_id");

-- 文件、知识库与文档 -------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."moss_kb_file" (
  "id" BIGINT PRIMARY KEY,
  "md5" VARCHAR(32) NOT NULL,
  "filename" TEXT NOT NULL,
  "file_size" BIGINT NOT NULL,
  "user_id" BIGINT,
  "platform" VARCHAR(64) NOT NULL,
  "region_name" VARCHAR(32),
  "bucket_name" VARCHAR(64) NOT NULL,
  "file_id" VARCHAR(64),
  "target_name" VARCHAR(255) NOT NULL,
  "tags" JSON,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT NOT NULL DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "public"."moss_kb_dataset" (
  "id" BIGINT PRIMARY KEY,
  "name" VARCHAR NOT NULL,
  "desc" VARCHAR,
  "type" VARCHAR,
  "embedding_mode_id" BIGINT,
  "llm_mode_id" BIGINT,
  "meta" JSONB,
  "user_id" BIGINT,
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "public"."moss_kb_application_dataset_mapping" (
  "id" BIGINT PRIMARY KEY,
  "application_id" BIGINT NOT NULL,
  "dataset_id" BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS "public"."moss_kb_document" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "file_id" BIGINT,
  "user_id" BIGINT,
  "title" VARCHAR,
  "name" VARCHAR NOT NULL,
  "type" VARCHAR NOT NULL,
  "url" VARCHAR,
  "content" TEXT,
  "char_length" INT,
  "status" VARCHAR,
  "is_active" BOOLEAN,
  "meta" JSONB,
  "dataset_id" BIGINT NOT NULL,
  "hit_handling_method" VARCHAR,
  "directly_return_similarity" FLOAT8,
  "paragraph_count" INT,
  "files" JSON,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT NOT NULL DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

-- 解析任务进度。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_task" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "file_id" BIGINT,
  "file_name" VARCHAR NOT NULL,
  "file_size" BIGINT,
  "dataset_id" BIGINT NOT NULL,
  "document_id" BIGINT,
  "progress" SMALLINT DEFAULT 0,
  "status" VARCHAR NOT NULL,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT NOT NULL DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

-- 分段预览任务：上传后立刻返回 task_id，解析在后台线程里按页推进，
-- 前端轮询这个表拿到进度或最终分段。result 直接存前端要用的分段列表。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_document_split_task" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "user_id" BIGINT,
  "file_id" BIGINT,
  "file_name" VARCHAR NOT NULL,
  "file_size" BIGINT,
  "status" VARCHAR(16) NOT NULL DEFAULT 'running',
  "progress" SMALLINT NOT NULL DEFAULT 0,
  "total" INT NOT NULL DEFAULT 0,
  "result" JSONB,
  "error_message" TEXT,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT NOT NULL DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS "moss_kb_document_split_task_user_id" ON "public"."moss_kb_document_split_task" USING btree ("user_id");

-- 分段与向量。embedding 与 title_embedding 使用知识库选定的同一个向量空间。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_paragraph" (
  "id" BIGINT PRIMARY KEY,
  "source_id" BIGINT,
  "source_type" VARCHAR,
  "title" VARCHAR,
  "content" VARCHAR NOT NULL,
  "md5" VARCHAR NOT NULL,
  "status" VARCHAR,
  "hit_num" INT,
  "is_active" BOOLEAN,
  "dataset_id" BIGINT NOT NULL,
  "document_id" BIGINT NOT NULL,
  "embedding" VECTOR,
  "title_embedding" VECTOR,
  "meta" JSONB,
  "search_vector" TSVECTOR,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "public"."moss_kb_sentence" (
  "id" BIGINT PRIMARY KEY,
  "type" INT,
  "content" VARCHAR NOT NULL,
  "md5" VARCHAR NOT NULL,
  "hit_num" INT NOT NULL,
  "dataset_id" BIGINT NOT NULL,
  "document_id" BIGINT NOT NULL,
  "paragraph_id" BIGINT NOT NULL,
  "embedding" VECTOR,
  "meta" JSONB,
  "search_vector" TSVECTOR,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

-- 问题库与问题分段映射。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_problem" (
  "id" BIGINT PRIMARY KEY,
  "content" VARCHAR NOT NULL,
  "hit_num" INT NOT NULL,
  "dataset_id" BIGINT NOT NULL,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS "moss_kb_problem_dataset_id" ON "public"."moss_kb_problem" USING btree ("dataset_id");

CREATE TABLE IF NOT EXISTS "public"."moss_kb_problem_paragraph_mapping" (
  "id" BIGINT PRIMARY KEY,
  "dataset_id" BIGINT NOT NULL,
  "document_id" BIGINT NOT NULL,
  "paragraph_id" BIGINT NOT NULL,
  "problem_id" BIGINT NOT NULL,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS "moss_kb_problem_paragraph_mapping_dataset_id"   ON "public"."moss_kb_problem_paragraph_mapping" USING btree ("dataset_id");
CREATE INDEX IF NOT EXISTS "moss_kb_problem_paragraph_mapping_document_id"  ON "public"."moss_kb_problem_paragraph_mapping" USING btree ("document_id");
CREATE INDEX IF NOT EXISTS "moss_kb_problem_paragraph_mapping_paragraph_id" ON "public"."moss_kb_problem_paragraph_mapping" USING btree ("paragraph_id");
CREATE INDEX IF NOT EXISTS "moss_kb_problem_paragraph_mapping_problem_id"   ON "public"."moss_kb_problem_paragraph_mapping" USING btree ("problem_id");

-- 缓存 ---------------------------------------------------------------------
-- 向量缓存：m 记录模型标识和维度，md5 是内容摘要，避免跨模型复用向量。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_embedding_cache" (
  "id" BIGINT PRIMARY KEY,
  "t" TEXT,
  "m" VARCHAR,
  "v" VECTOR,
  "md5" VARCHAR
);

CREATE INDEX IF NOT EXISTS "idx_moss_kb_embedding_cache_md5" ON "public"."moss_kb_embedding_cache" USING btree ("md5");
CREATE INDEX IF NOT EXISTS "idx_moss_kb_embedding_cache_md5_m" ON "public"."moss_kb_embedding_cache" USING btree ("md5", "m");

CREATE TABLE IF NOT EXISTS "public"."moss_kb_document_markdown_cache" (
  "id" VARCHAR PRIMARY KEY,
  "target" VARCHAR,
  "content" TEXT
);

CREATE TABLE IF NOT EXISTS "public"."moss_kb_document_markdown_page_cache" (
  "id" VARCHAR PRIMARY KEY,
  "target" VARCHAR,
  "content" TEXT,
  "elapsed" BIGINT,
  "model" VARCHAR,
  "system_fingerprint" VARCHAR,
  "completion_tokens" INT,
  "prompt_tokens" INT,
  "total_tokens" INT
);

CREATE TABLE IF NOT EXISTS "public"."moss_kb_paragraph_summary_cache" (
  "id" BIGINT PRIMARY KEY,
  "md5" VARCHAR,
  "src" TEXT,
  "content" TEXT,
  "elapsed" BIGINT,
  "model" VARCHAR,
  "system_fingerprint" VARCHAR,
  "completion_tokens" INT,
  "prompt_tokens" INT,
  "total_tokens" INT
);

-- 会话与多轮上下文 ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."moss_kb_application_chat" (
  "id" BIGINT PRIMARY KEY,
  "abstract" VARCHAR,
  "application_id" BIGINT NOT NULL,
  "client_id" BIGINT,
  "chat_type" INT NOT NULL,
  "is_deleted" BOOLEAN NOT NULL DEFAULT FALSE,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS "moss_kb_application_chat_application_id" ON "public"."moss_kb_application_chat" USING btree ("application_id");

CREATE TABLE IF NOT EXISTS "public"."moss_kb_application_chat_record" (
  "id" BIGINT PRIMARY KEY,
  "vote_status" VARCHAR NOT NULL DEFAULT '-1',
  "problem_text" VARCHAR NOT NULL,
  "answer_text" VARCHAR,
  "message_tokens" INT NOT NULL,
  "answer_tokens" INT,
  "const" INT NOT NULL DEFAULT 0,
  "details" JSONB,
  "improve_paragraph_id_list" BIGINT[],
  "run_time" FLOAT8,
  "index" INT,
  "chat_id" BIGINT NOT NULL,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS "moss_kb_application_chat_record_chat_id" ON "public"."moss_kb_application_chat_record" USING btree ("chat_id");

-- 会话持久摘要：只有历史 token 超出预算时才压缩，压缩水位记录在 through_record_id。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_chat_context" (
  "chat_id" BIGINT NOT NULL PRIMARY KEY,
  "summary" TEXT NOT NULL DEFAULT '',
  "through_record_id" BIGINT NOT NULL DEFAULT 0,
  "compacted_rounds" INT NOT NULL DEFAULT 0,
  "revision" INT NOT NULL DEFAULT 0,
  "update_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_chat_record_context" ON "public"."moss_kb_application_chat_record" USING btree ("chat_id", "id") WHERE "answer_text" IS NOT NULL;

-- 调试配置按会话保存，避免多个调试窗口互相覆盖。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_application_temp_setting" (
  "id" BIGINT PRIMARY KEY,
  "setting" JSONB
);

-- 公开访问的访客计数。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_application_public_access_client" (
  "id" BIGINT PRIMARY KEY,
  "access_num" INT NOT NULL,
  "intraday_access_num" INT NOT NULL,
  "application_id" BIGINT NOT NULL,
  "client_id" BIGINT,
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

-- 函数库与文档转换 ---------------------------------------------------------
-- 函数库：内置模板与用户函数共用一张表，function_type 区分 PUBLIC 内置模板和 INTERNAL 用户函数。
CREATE TABLE IF NOT EXISTS "public"."moss_kb_function_lib" (
  "id" BIGINT PRIMARY KEY,
  "user_id" BIGINT NOT NULL,
  "name" VARCHAR(128) NOT NULL,
  "desc" TEXT NOT NULL DEFAULT '',
  "code" TEXT NOT NULL,
  "input_field_list" JSONB NOT NULL DEFAULT '[]',
  "init_field_list" JSONB NOT NULL DEFAULT '[]',
  "init_params" JSONB NOT NULL DEFAULT '{}',
  "permission_type" VARCHAR(16) NOT NULL DEFAULT 'PRIVATE',
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "deleted" BOOLEAN NOT NULL DEFAULT false,
  "create_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
  "update_time" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
  "function_type" VARCHAR(16) NOT NULL DEFAULT 'PUBLIC',
  "icon" VARCHAR(256) NOT NULL DEFAULT '/ui/favicon.ico',
  "template_id" BIGINT,
  CONSTRAINT moss_kb_function_lib_function_type_check CHECK (function_type IN ('PUBLIC', 'INTERNAL'))
);

CREATE INDEX IF NOT EXISTS "idx_function_owner" ON "public"."moss_kb_function_lib" USING btree ("user_id") WHERE "deleted" = false;
CREATE INDEX IF NOT EXISTS "idx_function_type" ON "public"."moss_kb_function_lib" USING btree ("function_type") WHERE "deleted" = false;

CREATE TABLE IF NOT EXISTS "public"."libre_office_converted_mapping" (
  "id" BIGINT NOT NULL PRIMARY KEY,
  "input_file_id" BIGINT,
  "input_md5" VARCHAR,
  "output_file_id" BIGINT,
  "output_md5" VARCHAR,
  "remark" VARCHAR(256),
  "creator" VARCHAR(64) DEFAULT '',
  "create_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updater" VARCHAR(64) DEFAULT '',
  "update_time" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted" SMALLINT DEFAULT 0,
  "tenant_id" BIGINT NOT NULL DEFAULT 0
);

-- 外键 ---------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'moss_kb_chat_context_chat_id_fkey') THEN
    ALTER TABLE "public"."moss_kb_chat_context"
      ADD CONSTRAINT "moss_kb_chat_context_chat_id_fkey"
      FOREIGN KEY ("chat_id") REFERENCES "public"."moss_kb_application_chat"("id") ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'moss_kb_model_catalog_provider_fkey') THEN
    ALTER TABLE "public"."moss_kb_model_catalog"
      ADD CONSTRAINT "moss_kb_model_catalog_provider_fkey"
      FOREIGN KEY ("provider") REFERENCES "public"."moss_kb_model_provider"("provider");
  END IF;
END $$;

-- 旧库补齐 -----------------------------------------------------------------
-- 下面语句让早期版本的数据库补齐后来新增的列。全新初始化时它们是空操作。
ALTER TABLE "public"."moss_kb_dataset" ADD COLUMN IF NOT EXISTS "llm_mode_id" BIGINT;
ALTER TABLE "public"."moss_kb_user" ADD COLUMN IF NOT EXISTS "token_version" BIGINT NOT NULL DEFAULT 0;
-- 界面语言，为空表示跟随浏览器语言：老账号升级后语言不变，直到用户自己切换一次。
ALTER TABLE "public"."moss_kb_user" ADD COLUMN IF NOT EXISTS "language" VARCHAR(16);
ALTER TABLE "public"."moss_kb_model" ADD COLUMN IF NOT EXISTS "model_params_form" JSONB NOT NULL DEFAULT '[]';
ALTER TABLE "public"."moss_kb_application_access_token" ADD COLUMN IF NOT EXISTS "language" VARCHAR(16);
ALTER TABLE "public"."moss_kb_function_lib" ADD COLUMN IF NOT EXISTS "function_type" VARCHAR(16) NOT NULL DEFAULT 'PUBLIC';
ALTER TABLE "public"."moss_kb_function_lib" ADD COLUMN IF NOT EXISTS "icon" VARCHAR(256) NOT NULL DEFAULT '/ui/favicon.ico';
ALTER TABLE "public"."moss_kb_function_lib" ADD COLUMN IF NOT EXISTS "template_id" BIGINT;

-- 文件名保存完整描述性名称，早期版本使用的是较短的类型。
ALTER TABLE "public"."moss_kb_file" ALTER COLUMN "filename" TYPE TEXT;

-- 第二部分：初始数据

-- 管理员账号：用户名 admin，初始密码见数据库设计章节，登录后应立即修改。
INSERT INTO "public"."moss_kb_user" (id, email, phone, nick_name, username, password, role,
  is_active, source, remark, creator, create_time, updater, update_time, deleted, tenant_id)
VALUES (
  1,
  '',
  '',
  '系统管理员',
  'admin',
  '608fd4367502762e76a77ee348c9f1c7',
  'ADMIN',
  TRUE,
  'LOCAL',
  '',
  '',
  CURRENT_TIMESTAMP,
  '',
  CURRENT_TIMESTAMP,
  0,
  0
) ON CONFLICT DO NOTHING;

-- 默认模型：默认推理模型与默认远程向量模型，向量维度 1024。
INSERT INTO moss_kb_model(id,name,model_type,model_name,provider,credential,user_id,status,permission_type,meta)
VALUES (1001,'Gitee DeepSeek V4.1 Flash','LLM','DeepSeek-V4.1-Flash-1017','model_openai_provider','{}',1,'SUCCESS','PUBLIC','{}'),
(1002,'Gitee Qwen3 Embedding 8B','EMBEDDING','Qwen3-Embedding-8B','model_openai_provider','{}',1,'SUCCESS','PUBLIC','{}')
ON CONFLICT (id) DO NOTHING;

-- 平台接入信息：接口地址、协议、能力与表单定义；目录项回填已安装模型。
-- icon 统一为 32×32、圆角 8、品牌色底 + 白色标记：展示尺寸由前端统一压到 18×18，
-- 因此 SVG 必须自带 width/height/viewBox，且标记要留在 32×32 的安全区内。
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_default_provider','OpenAI 兼容 / 自定义中转','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','','[{"key":"大语言模型","value":"LLM"},{"key":"向量模型","value":"EMBEDDING"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,0) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_openai_provider','OpenAI','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://api.openai.com/v1','[{"key":"大语言模型","value":"LLM"},{"key":"向量模型","value":"EMBEDDING"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://api.openai.com/v1","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,1) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_gitee_provider','Gitee AI','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://ai.gitee.com/v1','[{"key":"大语言模型","value":"LLM"},{"key":"向量模型","value":"EMBEDDING"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://ai.gitee.com/v1","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,2) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_openrouter_provider','OpenRouter（含 Claude / GPT / Gemini）','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://openrouter.ai/api/v1','[{"key":"大语言模型","value":"LLM"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://openrouter.ai/api/v1","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,3) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_siliconflow_provider','硅基流动','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://api.siliconflow.cn/v1','[{"key":"大语言模型","value":"LLM"},{"key":"向量模型","value":"EMBEDDING"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://api.siliconflow.cn/v1","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,4) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_deepseek_provider','DeepSeek','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://api.deepseek.com','[{"key":"大语言模型","value":"LLM"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://api.deepseek.com","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,5) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_qwen_provider','阿里云百炼','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://dashscope.aliyuncs.com/compatible-mode/v1','[{"key":"大语言模型","value":"LLM"},{"key":"向量模型","value":"EMBEDDING"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://dashscope.aliyuncs.com/compatible-mode/v1","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,6) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_kimi_provider','Kimi','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://api.moonshot.cn/v1','[{"key":"大语言模型","value":"LLM"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://api.moonshot.cn/v1","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,7) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_zhipu_provider','智谱 AI','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://open.bigmodel.cn/api/paas/v4','[{"key":"大语言模型","value":"LLM"},{"key":"向量模型","value":"EMBEDDING"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://open.bigmodel.cn/api/paas/v4","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,8) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_gemini_provider','Gemini（OpenAI 兼容）','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://generativelanguage.googleapis.com/v1beta/openai','[{"key":"大语言模型","value":"LLM"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://generativelanguage.googleapis.com/v1beta/openai","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,9) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_volcanic_engine_provider','火山方舟','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','https://ark.cn-beijing.volces.com/api/v3','[{"key":"大语言模型","value":"LLM"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"https://ark.cn-beijing.volces.com/api/v3","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,10) ON CONFLICT(provider) DO NOTHING;
INSERT INTO moss_kb_model_provider(provider,name,icon,api_base,model_types,credential_form,params_form,sort_order) VALUES('model_newapi_provider','New API / One API 中转','<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#3370ff"/><path d="M8 23V9l8 10 8-10v14" stroke="white" stroke-width="2" fill="none"/></svg>','','[{"key":"大语言模型","value":"LLM"},{"key":"向量模型","value":"EMBEDDING"}]'::jsonb,'[{"input_type":"TextInput","label":"API 域名","required":true,"default_value":"","relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_base"},{"input_type":"PasswordInput","label":"API Key","required":true,"default_value":null,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{},"props_info":{},"field":"api_key"}]'::jsonb,'[{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"温度","attrs":{"tooltip":"较高的数值会使输出更加随机，而较低的数值会使其更加集中和确定"},"props_info":{}},"required":true,"default_value":0.7,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":0.1,"max":1.0,"step":0.01,"precision":2,"show-input-controls":false,"show-input":true},"props_info":{},"field":"temperature"},{"input_type":"Slider","label":{"input_type":"TooltipLabel","label":"输出最大Tokens","attrs":{"tooltip":"指定模型可生成的最大token个数"},"props_info":{}},"required":true,"default_value":800,"relation_show_field_dict":{},"relation_trigger_field_dict":{},"trigger_type":"OPTION_LIST","attrs":{"min":1,"max":100000,"step":1,"precision":0,"show-input-controls":false,"show-input":true},"props_info":{},"field":"max_tokens"}]'::jsonb,11) ON CONFLICT(provider) DO NOTHING;
-- 集中覆写品牌图标：对已存在的库同样生效（上面的 INSERT 带 ON CONFLICT DO NOTHING，不会更新 icon）。
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#4b5563"/><path d="M9 12h9a4 4 0 0 1 0 8H9" stroke="#fff" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 8 8 12l4 4" stroke="#fff" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>' WHERE provider='model_default_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#0f9d78"/><path d="M16 5.5 25 10.75v10.5L16 26.5 7 21.25v-10.5z" fill="none" stroke="#fff" stroke-width="2.2" stroke-linejoin="round"/><path d="M16 16 25 10.75M16 16v10.5M16 16 7 10.75" stroke="#fff" stroke-width="2.2" stroke-linejoin="round"/></svg>' WHERE provider='model_openai_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#c71d23"/><path d="M22.5 11.5h-8a1.5 1.5 0 0 0-1.5 1.5v6a1.5 1.5 0 0 0 1.5 1.5h2v-3.75H14" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/><path d="M9.5 9.5h13" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/></svg>' WHERE provider='model_gitee_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#6467f2"/><circle cx="9" cy="16" r="2.6" fill="#fff"/><circle cx="23" cy="10" r="2.6" fill="#fff"/><circle cx="23" cy="22" r="2.6" fill="#fff"/><path d="M11.4 14.9 20.6 11M11.4 17.1l9.2 3.9" stroke="#fff" stroke-width="2" stroke-linecap="round"/></svg>' WHERE provider='model_openrouter_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#6d28d9"/><rect x="8" y="16" width="4" height="8" rx="2" fill="#fff"/><rect x="14" y="10" width="4" height="14" rx="2" fill="#fff" opacity=".85"/><rect x="20" y="13" width="4" height="11" rx="2" fill="#fff" opacity=".7"/></svg>' WHERE provider='model_siliconflow_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#4d6bfe"/><path d="M16 6c1.6 3.4 4 5.8 7.4 7.4-3.4 1.6-5.8 4-7.4 7.4-1.6-3.4-4-5.8-7.4-7.4C12 11.8 14.4 9.4 16 6z" fill="#fff"/><circle cx="22" cy="23.5" r="2.5" fill="#fff" opacity=".8"/></svg>' WHERE provider='model_deepseek_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#7c3aed"/><path d="M16 7.5 24.5 12v8L16 24.5 7.5 20v-8z" fill="#fff"/><path d="M16 13.5 20.5 16v4L16 22.5 11.5 20v-4z" fill="#7c3aed"/></svg>' WHERE provider='model_qwen_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#111827"/><path d="M11 9v14M11 16.5 20 9M11 16.5 20.5 23" stroke="#fff" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>' WHERE provider='model_kimi_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#2f5bea"/><path d="M9 10h14l-9.5 12H23" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>' WHERE provider='model_zhipu_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#4285f4"/><path d="M16 5c1.9 4.3 4.7 7.1 9 9-4.3 1.9-7.1 4.7-9 9-1.9-4.3-4.7-7.1-9-9 4.3-1.9 7.1-4.7 9-9z" fill="#fff"/></svg>' WHERE provider='model_gemini_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#1664ff"/><path d="M16 5.5 24.5 20h-17z" fill="#fff"/><path d="M16 14.5 21.5 24h-11z" fill="#ff7a45"/></svg>' WHERE provider='model_volcanic_engine_provider';
UPDATE moss_kb_model_provider SET icon='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#0ea5e9"/><path d="M9 23V9l14 14V9" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>' WHERE provider='model_newapi_provider';

UPDATE moss_kb_model SET provider='model_gitee_provider' WHERE id IN (1001,1002) AND provider='model_openai_provider' AND credential::jsonb='{}'::jsonb;

-- 更新已有默认模型的旧 ID，保留用户选择的其他模型。
UPDATE moss_kb_model SET model_name='DeepSeek-V4.1-Flash-1017'
WHERE id=1001 AND model_name='deepseek-v4.1-flash';

-- 清理平台已失效的模型：这类历史脏数据（例如测试直接写库留下的 provider='provider'）
-- 无法用于创建知识库，却会在选择列表里挂到空分组并和其它模型重名。
-- 平台先归位再清理，避免把默认模型当成悬空数据删掉。
DELETE FROM moss_kb_model m
WHERE NOT EXISTS (
  SELECT 1 FROM moss_kb_model_provider p WHERE p.provider = m.provider AND p.enabled = true
);

INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source)
 SELECT DISTINCT provider,model_type,model_name,model_name,'installed'
 FROM moss_kb_model m WHERE EXISTS(SELECT 1 FROM moss_kb_model_provider p WHERE p.provider=m.provider)
 ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES
 ('model_gitee_provider','LLM','deepseek-v4.1-flash','默认 Gitee 推理模型','installed'),
 ('model_gitee_provider','EMBEDDING','Qwen3-Embedding-8B','默认远程向量模型，1024 维','installed') ON CONFLICT DO NOTHING;

-- 平台模型目录快照：候选模型 ID，不代表当前密钥一定可用。
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inclusionai/ling-3.1-flash','inclusionAI: Ling 3.1 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','apodex/apodex-1.1-mini:free','Apodex: Apodex 1.1 Mini (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','unbiased/pareto-26.10-preview','Pareto 26.10 Preview（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-6.1-sol-pro','OpenAI: GPT-6.1 Sol Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-6.1-sol','OpenAI: GPT-6.1 Sol（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-sonnet-5.5','Anthropic: Claude Sonnet 5.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','typesafe/jev-router','TypeSafe: Jev Router（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','perceptron/perceptron-mk1.5','Perceptron: Perceptron Mk1.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','fireworks/ember-1','Fireworks: Ember-1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5.3-prime','Z.ai: GLM 5.3 Prime（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.8-max-prime','Qwen: Qwen3.8 Max Prime（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','stealth/space-bunny-alpha','Space Bunny Alpha（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','aion-labs/aion-3.5-mini','AionLabs: Aion 3.5 Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','aion-labs/aion-3.5','AionLabs: Aion 3.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','upstage/solar-mini4','Upstage: Solar Mini 4（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','cohere/command-a-plus','Cohere: Command A+（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-6-luna-pro','OpenAI: GPT-6 Luna Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-6-luna','OpenAI: GPT-6 Luna（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-6-sol-pro','OpenAI: GPT-6 Sol Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-6-sol','OpenAI: GPT-6 Sol（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-opus-5.5','Anthropic: Claude Opus 5.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/switchyard','NVIDIA: Switchyard（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','xiaomi/mimo-v2.6-pro-ultraspeed','Xiaomi: MiMo-V2.6-Pro-UltraSpeed（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','xiaomi/mimo-v2.6-flash','Xiaomi: MiMo-V2.6-Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','xiaomi/mimo-v2.6-pro','Xiaomi: MiMo-V2.6-Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','x-ai/grok-4.7','SpaceXAI: Grok 4.7（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.8-omni-flash','Qwen: Qwen3.8 Omni Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','prism-ml/ternary-bonsai-2-27b','PrismML: Ternary Bonsai 2 27B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5.3-flashx','Z.ai: GLM 5.3 FlashX（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','unbiased/pareto','Pareto（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~deepseek/deepseek-pro-latest','DeepSeek: DeepSeek Pro Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~deepseek/deepseek-flash-latest','DeepSeek: DeepSeek Flash Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inference-net/schematron-v2-turbo','Inference.net: Schematron V2 Turbo（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inference-net/schematron-v2-small','Inference.net: Schematron V2 Small（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~openai/gpt-astra-latest','OpenAI: GPT Astra Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~openai/gpt-sol-latest','OpenAI: GPT Sol Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~openai/gpt-terra-latest','OpenAI: GPT Terra Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~openai/gpt-luna-latest','OpenAI: GPT Luna Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','sakana/fugu-ultra-v2','Sakana: Fugu Ultra v2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','sakana/fugu-max','Sakana: Fugu Max（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inclusionai/ling-3.0-flash-vl','inclusionAI: Ling 3.0 Flash VL（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v4.1-flash','DeepSeek: DeepSeek V4.1 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inception/mercury-2.5','Inception: Mercury 2.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nex-agi/nex-n2.5-mini','Nex AGI: Nex-N2.5-Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nex-agi/nex-n2.5-pro','Nex AGI: Nex-N2.5-Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-6-astra','OpenAI: GPT-6 Astra（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-6-astra-pro','OpenAI: GPT-6 Astra Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inclusionai/ling-3.0-flash-sante:free','inclusionAI: Ling 3.0 Flash Sante (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.8-max-0902','Qwen: Qwen3.8 Max (0902)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta/muse-spark-1.3-contributor','Meta: Muse Spark 1.3 Contributor（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta/muse-spark-1.3','Meta: Muse Spark 1.3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.8-flash','Google: Gemini 3.8 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-fable-5.1','Anthropic: Claude Fable 5.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','ibm-granite/granite-4.2-8b','IBM: Granite 4.2 8B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','tencent/hy4-preview','Tencent: Hy4 preview（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inclusionai/ling-3.0-flash-fin','inclusionAI: Ling 3.0 Flash Fin（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~z-ai/glm-flash-latest','Z.ai: GLM Flash Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.8-flash','Qwen: Qwen3.8 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5.3-flash','Z.ai: GLM 5.3 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta/muse-spark-1.2-contributor','Meta: Muse Spark 1.2 Contributor（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v4-flash-vision-exp','DeepSeek: DeepSeek V4 Flash Vision Exp（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','tencent/hy-mt2-1.8b','Tencent: Hy-MT2-1.8B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','tencent/hy-mt2-30b-a3b','Tencent: Hy-MT2-30B-A3B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~z-ai/glm-latest','Z.ai: GLM Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','tencent/hy-mt2-7b','Tencent: Hy-MT2-7B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5.3','Z.ai: GLM 5.3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.8-27b','Qwen: Qwen3.8 27B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.8-27b:free','Qwen: Qwen3.8 27B (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','dots-studio/dots-3-note-preview:free','Dots Studio: Dots3-Note Preview (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.7-flash','Google: Gemini 3.7 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','bytedance-seed/seed-2-1-turbo','ByteDance Seed: Seed 2.1 Turbo（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.8-2.4t-a95b','Qwen: Qwen3.8 2.4T A95B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','bytedance-seed/seed-2.0-code','ByteDance Seed: Seed-2.0-Code（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v4-pro-0813','DeepSeek: DeepSeek V4 Pro 0813（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','x-ai/grok-4.6','SpaceXAI: Grok 4.6（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','liquid/lfm-2.5-2.6b:free','LiquidAI: LFM2.5-2.6B (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3.5-lightning','NVIDIA: Nemotron 3.5 Lightning（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3.5-lightning:free','NVIDIA: Nemotron 3.5 Lightning (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','sakana/sakana-namazu','Sakana: Sakana Namazu（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','upstage/solar-pro4','Upstage: Solar Pro 4（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta/muse-glimmer-30b','Meta: Muse Glimmer 30B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta/muse-spark-1.2','Meta: Muse Spark 1.2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~deepseek/deepseek-v4-flash-latest','DeepSeek: DeepSeek V4 Flash Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v4-flash-0731','DeepSeek: DeepSeek V4 Flash 0731（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','thinkingmachines/inkling-small','Thinking Machines: Inkling Small（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','thinkingmachines/inkling-small:free','Thinking Machines: Inkling Small (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.7-flash','Qwen: Qwen3.7 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-opus-5','Anthropic: Claude Opus 5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inclusionai/ling-3.0-flash','inclusionAI: Ling 3.0 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','poolside/laguna-s-2.1','Poolside: Laguna S 2.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','poolside/laguna-s-2.1:free','Poolside: Laguna S 2.1 (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.6-flash','Google: Gemini 3.6 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.5-flash-lite','Google: Gemini 3.5 Flash Lite（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meituan/longcat-2.0','Meituan: LongCat 2.0（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','thinkingmachines/inkling','Thinking Machines: Inkling（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','thinkingmachines/inkling:free','Thinking Machines: Inkling (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','moonshotai/kimi-k3','MoonshotAI: Kimi K3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta/muse-spark-1.1','Meta: Muse Spark 1.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','kwaipilot/kat-coder-pro-v2.5','Kwaipilot: KAT-Coder-Pro V2.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.6-luna-pro','OpenAI: GPT-5.6 Luna Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.6-luna','OpenAI: GPT-5.6 Luna（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.6-terra-pro','OpenAI: GPT-5.6 Terra Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.6-terra','OpenAI: GPT-5.6 Terra（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.6-sol-pro','OpenAI: GPT-5.6 Sol Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.6-sol','OpenAI: GPT-5.6 Sol（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','x-ai/grok-4.5','SpaceXAI: Grok 4.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~x-ai/grok-latest','xAI: Grok Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','aion-labs/aion-3.0-mini','AionLabs: Aion-3.0-Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','aion-labs/aion-3.0','AionLabs: Aion-3.0（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','tencent/hy3','Tencent: Hy3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','poolside/laguna-xs-2.1','Poolside: Laguna XS 2.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','poolside/laguna-xs-2.1:free','Poolside: Laguna XS 2.1 (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-sonnet-5','Anthropic: Claude Sonnet 5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','sakana/fugu-ultra','Sakana: Fugu Ultra（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','cohere/north-mini-code:free','Cohere: North Mini Code (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5.2','Z.ai: GLM 5.2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openrouter/fusion','OpenRouter: Fusion（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','moonshotai/kimi-k2.7-code','MoonshotAI: Kimi K2.7 Code（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~anthropic/claude-fable-latest','Anthropic: Claude Fable Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-fable-5','Anthropic: Claude Fable 5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3.5-content-safety','NVIDIA: Nemotron 3.5 Content Safety（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3.5-content-safety:free','NVIDIA: Nemotron 3.5 Content Safety (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3-ultra-550b-a55b','NVIDIA: Nemotron 3 Ultra（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3-ultra-550b-a55b:free','NVIDIA: Nemotron 3 Ultra (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.7-plus','Qwen: Qwen3.7 Plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','minimax/minimax-m3','MiniMax: MiniMax M3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','stepfun/step-3.7-flash','StepFun: Step 3.7 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-opus-4.8','Anthropic: Claude Opus 4.8（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.7-max','Qwen: Qwen3.7 Max（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','x-ai/grok-build-0.1','SpaceXAI: Grok Build 0.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.5-flash','Google: Gemini 3.5 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','perceptron/perceptron-mk1','Perceptron: Perceptron Mk1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.1-flash-lite','Google: Gemini 3.1 Flash Lite（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-chat-latest','OpenAI: GPT Chat Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','x-ai/grok-4.3','SpaceXAI: Grok 4.3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-medium-3-5','Mistral: Mistral Medium 3.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free','NVIDIA: Nemotron 3 Nano Omni (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~anthropic/claude-haiku-latest','Anthropic: Claude Haiku Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~openai/gpt-mini-latest','OpenAI: GPT Mini Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~google/gemini-pro-latest','Google: Gemini Pro Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~moonshotai/kimi-latest','MoonshotAI: Kimi Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~google/gemini-flash-latest','Google: Gemini Flash Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~anthropic/claude-sonnet-latest','Anthropic: Claude Sonnet Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.5-plus-20260420','Qwen: Qwen3.5 Plus 2026-04-20（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.6-flash','Qwen: Qwen3.6 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.6-35b-a3b','Qwen: Qwen3.6 35B A3B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.6-max-preview','Qwen: Qwen3.6 Max Preview（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.6-27b','Qwen: Qwen3.6 27B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.5-pro','OpenAI: GPT-5.5 Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.5','OpenAI: GPT-5.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v4-pro','DeepSeek: DeepSeek V4 Pro 0423（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v4-flash','DeepSeek: DeepSeek V4 Flash 0423（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','tencent/hy3-preview','Tencent: Hy3 preview（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','xiaomi/mimo-v2.5-pro','Xiaomi: MiMo-V2.5-Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','xiaomi/mimo-v2.5','Xiaomi: MiMo-V2.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','~anthropic/claude-opus-latest','Anthropic: Claude Opus Latest（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openrouter/pareto-code','Pareto Code Router（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','moonshotai/kimi-k2.6','MoonshotAI: Kimi K2.6（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-opus-4.7','Anthropic: Claude Opus 4.7（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5.1','Z.ai: GLM 5.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemma-4-26b-a4b-it','Google: Gemma 4 26B A4B （平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemma-4-26b-a4b-it:free','Google: Gemma 4 26B A4B  (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemma-4-31b-it','Google: Gemma 4 31B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemma-4-31b-it:free','Google: Gemma 4 31B (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.6-plus','Qwen: Qwen3.6 Plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5v-turbo','Z.ai: GLM 5V Turbo（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','arcee-ai/trinity-large-thinking','Arcee AI: Trinity Large Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','x-ai/grok-4.20-multi-agent','SpaceXAI: Grok 4.20 Multi-Agent（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','x-ai/grok-4.20','SpaceXAI: Grok 4.20（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','rekaai/reka-edge','Reka Edge（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','minimax/minimax-m2.7','MiniMax: MiniMax M2.7（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.4-nano','OpenAI: GPT-5.4 Nano（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.4-mini','OpenAI: GPT-5.4 Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-small-2603','Mistral: Mistral Small 4（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5-turbo','Z.ai: GLM 5 Turbo（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3-super-120b-a12b','NVIDIA: Nemotron 3 Super（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3-super-120b-a12b:free','NVIDIA: Nemotron 3 Super (free)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','bytedance-seed/seed-2.0-lite','ByteDance Seed: Seed-2.0-Lite（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.5-9b','Qwen: Qwen3.5-9B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.4-pro','OpenAI: GPT-5.4 Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.4','OpenAI: GPT-5.4（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','inception/mercury-2','Inception: Mercury 2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.1-flash-lite-preview','Google: Gemini 3.1 Flash Lite Preview（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','bytedance-seed/seed-2.0-mini','ByteDance Seed: Seed-2.0-Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.5-35b-a3b','Qwen: Qwen3.5-35B-A3B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.5-27b','Qwen: Qwen3.5-27B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.5-122b-a10b','Qwen: Qwen3.5-122B-A10B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.5-flash-02-23','Qwen: Qwen3.5-Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.1-pro-preview-customtools','Google: Gemini 3.1 Pro Preview Custom Tools（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.3-codex','OpenAI: GPT-5.3-Codex（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','aion-labs/aion-2.0','AionLabs: Aion-2.0（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3.1-pro-preview','Google: Gemini 3.1 Pro Preview（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-sonnet-4.6','Anthropic: Claude Sonnet 4.6（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.5-plus-02-15','Qwen: Qwen3.5 Plus 2026-02-15（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3.5-397b-a17b','Qwen: Qwen3.5 397B A17B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','minimax/minimax-m2.5','MiniMax: MiniMax M2.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-5','Z.ai: GLM 5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-max-thinking','Qwen: Qwen3 Max Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-opus-4.6','Anthropic: Claude Opus 4.6（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-coder-next','Qwen: Qwen3 Coder Next（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openrouter/free','Free Models Router（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','stepfun/step-3.5-flash','StepFun: Step 3.5 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','moonshotai/kimi-k2.5','MoonshotAI: Kimi K2.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','upstage/solar-pro-3','Upstage: Solar Pro 3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','minimax/minimax-m2-her','MiniMax: MiniMax M2-her（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','writer/palmyra-x5','Writer: Palmyra X5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-4.7-flash','Z.ai: GLM 4.7 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.2-codex','OpenAI: GPT-5.2-Codex（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','bytedance-seed/seed-1.6-flash','ByteDance Seed: Seed 1.6 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','bytedance-seed/seed-1.6','ByteDance Seed: Seed 1.6（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','minimax/minimax-m2.1','MiniMax: MiniMax M2.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-4.7','Z.ai: GLM 4.7（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-3-flash-preview','Google: Gemini 3 Flash Preview（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nvidia/nemotron-3-nano-30b-a3b','NVIDIA: Nemotron 3 Nano 30B A3B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.2-chat','OpenAI: GPT-5.2 Chat（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.2-pro','OpenAI: GPT-5.2 Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.2','OpenAI: GPT-5.2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/devstral-2512','Mistral: Devstral 2 2512（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','relace/relace-search','Relace: Relace Search（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-4.6v','Z.ai: GLM 4.6V（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openrouter/bodybuilder','Body Builder (beta)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.1-codex-max','OpenAI: GPT-5.1-Codex-Max（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','amazon/nova-2-lite-v1','Amazon: Nova 2 Lite（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/ministral-14b-2512','Mistral: Ministral 3 14B 2512（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/ministral-8b-2512','Mistral: Ministral 3 8B 2512（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/ministral-3b-2512','Mistral: Ministral 3 3B 2512（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-large-2512','Mistral: Mistral Large 3 2512（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v3.2','DeepSeek: DeepSeek V3.2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-opus-4.5','Anthropic: Claude Opus 4.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.1','OpenAI: GPT-5.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.1-codex','OpenAI: GPT-5.1-Codex（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5.1-codex-mini','OpenAI: GPT-5.1-Codex-Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','moonshotai/kimi-k2-thinking','MoonshotAI: Kimi K2 Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','amazon/nova-premier-v1','Amazon: Nova Premier 1.0（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','perplexity/sonar-pro-search','Perplexity: Sonar Pro Search（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/voxtral-small-24b-2507','Mistral: Voxtral Small 24B 2507（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-oss-safeguard-20b','OpenAI: gpt-oss-safeguard-20b（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','minimax/minimax-m2','MiniMax: MiniMax M2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-vl-32b-instruct','Qwen: Qwen3 VL 32B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','ibm-granite/granite-4.0-h-micro','IBM: Granite 4.0 Micro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-haiku-4.5','Anthropic: Claude Haiku 4.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-vl-8b-thinking','Qwen: Qwen3 VL 8B Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-vl-8b-instruct','Qwen: Qwen3 VL 8B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-vl-30b-a3b-thinking','Qwen: Qwen3 VL 30B A3B Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-vl-30b-a3b-instruct','Qwen: Qwen3 VL 30B A3B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5-pro','OpenAI: GPT-5 Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-4.6','Z.ai: GLM 4.6（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-sonnet-4.5','Anthropic: Claude Sonnet 4.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v3.2-exp','DeepSeek: DeepSeek V3.2 Exp（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','thedrummer/cydonia-24b-v4.1','TheDrummer: Cydonia 24B V4.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','relace/relace-apply-3','Relace: Relace Apply 3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-vl-235b-a22b-thinking','Qwen: Qwen3 VL 235B A22B Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-vl-235b-a22b-instruct','Qwen: Qwen3 VL 235B A22B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-max','Qwen: Qwen3 Max（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-coder-plus','Qwen: Qwen3 Coder Plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-v3.1-terminus','DeepSeek: DeepSeek V3.1 Terminus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-coder-flash','Qwen: Qwen3 Coder Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-next-80b-a3b-thinking','Qwen: Qwen3 Next 80B A3B Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-next-80b-a3b-instruct','Qwen: Qwen3 Next 80B A3B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen-plus-2025-07-28','Qwen: Qwen Plus 0728（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','moonshotai/kimi-k2-0905','MoonshotAI: Kimi K2 0905（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-30b-a3b-thinking-2507','Qwen: Qwen3 30B A3B Thinking 2507（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nousresearch/hermes-4-405b','Nous: Hermes 4 405B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-chat-v3.1','DeepSeek: DeepSeek V3.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-medium-3.1','Mistral: Mistral Medium 3.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-4.5v','Z.ai: GLM 4.5V（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5','OpenAI: GPT-5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5-mini','OpenAI: GPT-5 Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-5-nano','OpenAI: GPT-5 Nano（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-oss-120b','OpenAI: gpt-oss-120b（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-oss-20b','OpenAI: gpt-oss-20b（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-opus-4.1','Anthropic: Claude Opus 4.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/codestral-2508','Mistral: Codestral 2508（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-coder-30b-a3b-instruct','Qwen: Qwen3 Coder 30B A3B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-30b-a3b-instruct-2507','Qwen: Qwen3 30B A3B Instruct 2507（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-4.5','Z.ai: GLM 4.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','z-ai/glm-4.5-air','Z.ai: GLM 4.5 Air（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-235b-a22b-thinking-2507','Qwen: Qwen3 235B A22B Thinking 2507（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-coder','Qwen: Qwen3 Coder 480B A35B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','bytedance/ui-tars-1.5-7b','ByteDance: UI-TARS 7B （平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-2.5-flash-lite','Google: Gemini 2.5 Flash Lite（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-235b-a22b-2507','Qwen: Qwen3 235B A22B Instruct 2507（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','moonshotai/kimi-k2','MoonshotAI: Kimi K2 0711（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','cognitivecomputations/dolphin-mistral-24b-venice-edition','Venice: Uncensored（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','tencent/hunyuan-a13b-instruct','Tencent: Hunyuan A13B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','morph/morph-v3-large','Morph: Morph V3 Large（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','morph/morph-v3-fast','Morph: Morph V3 Fast（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','baidu/ernie-4.5-vl-424b-a47b','Baidu: ERNIE 4.5 VL 424B A47B （平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-small-3.2-24b-instruct','Mistral: Mistral Small 3.2 24B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','minimax/minimax-m1','MiniMax: MiniMax M1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-2.5-flash','Google: Gemini 2.5 Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-2.5-pro','Google: Gemini 2.5 Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/o3-pro','OpenAI: o3 Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemini-2.5-pro-preview','Google: Gemini 2.5 Pro Preview 06-05（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-r1-0528','DeepSeek: R1 0528（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthropic/claude-sonnet-4','Anthropic: Claude Sonnet 4（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-medium-3','Mistral: Mistral Medium 3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta-llama/llama-guard-4-12b','Meta: Llama Guard 4 12B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-30b-a3b','Qwen: Qwen3 30B A3B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-8b','Qwen: Qwen3 8B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-14b','Qwen: Qwen3 14B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-32b','Qwen: Qwen3 32B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen3-235b-a22b','Qwen: Qwen3 235B A22B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/o4-mini-high','OpenAI: o4 Mini High（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/o3','OpenAI: o3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/o4-mini','OpenAI: o4 Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4.1','OpenAI: GPT-4.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4.1-mini','OpenAI: GPT-4.1 Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4.1-nano','OpenAI: GPT-4.1 Nano（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta-llama/llama-4-maverick','Meta: Llama 4 Maverick（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta-llama/llama-4-scout','Meta: Llama 4 Scout（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-chat-v3-0324','DeepSeek: DeepSeek V3 0324（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/o1-pro','OpenAI: o1-pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-small-3.1-24b-instruct','Mistral: Mistral Small 3.1 24B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemma-3-4b-it','Google: Gemma 3 4B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemma-3-12b-it','Google: Gemma 3 12B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','cohere/command-a','Cohere: Command A（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','rekaai/reka-flash-3','Reka Flash 3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemma-3-27b-it','Google: Gemma 3 27B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','thedrummer/skyfall-36b-v2','TheDrummer: Skyfall 36B V2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','perplexity/sonar-reasoning-pro','Perplexity: Sonar Reasoning Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','perplexity/sonar-pro','Perplexity: Sonar Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','perplexity/sonar-deep-research','Perplexity: Sonar Deep Research（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-saba','Mistral: Saba（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/o3-mini-high','OpenAI: o3 Mini High（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','aion-labs/aion-rp-llama-3.1-8b','AionLabs: Aion-RP 1.0 (8B)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen2.5-vl-72b-instruct','Qwen: Qwen2.5 VL 72B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen-plus','Qwen: Qwen-Plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/o3-mini','OpenAI: o3 Mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-small-24b-instruct-2501','Mistral: Mistral Small 3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','perplexity/sonar','Perplexity: Sonar（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-r1','DeepSeek: R1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','minimax/minimax-01','MiniMax: MiniMax-01（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','microsoft/phi-4','Microsoft: Phi 4（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','deepseek/deepseek-chat','DeepSeek: DeepSeek V3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','sao10k/l3.3-euryale-70b','Sao10K: Llama 3.3 Euryale 70B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/o1','OpenAI: o1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','cohere/command-r7b-12-2024','Cohere: Command R7B (12-2024)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta-llama/llama-3.3-70b-instruct','Meta: Llama 3.3 70B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','amazon/nova-lite-v1','Amazon: Nova Lite 1.0（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','amazon/nova-micro-v1','Amazon: Nova Micro 1.0（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','amazon/nova-pro-v1','Amazon: Nova Pro 1.0（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4o-2024-11-20','OpenAI: GPT-4o (2024-11-20)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-large-2407','Mistral Large 2407（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen-2.5-coder-32b-instruct','Qwen2.5 Coder 32B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','thedrummer/unslopnemo-12b','TheDrummer: UnslopNemo 12B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','anthracite-org/magnum-v4-72b','Magnum v4 72B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen-2.5-7b-instruct','Qwen: Qwen2.5 7B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta-llama/llama-3.2-1b-instruct','Meta: Llama 3.2 1B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta-llama/llama-3.2-3b-instruct','Meta: Llama 3.2 3B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','qwen/qwen-2.5-72b-instruct','Qwen2.5 72B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','cohere/command-r-08-2024','Cohere: Command R (08-2024)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','cohere/command-r-plus-08-2024','Cohere: Command R+ (08-2024)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','sao10k/l3.1-euryale-70b','Sao10K: Llama 3.1 Euryale 70B v2.2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nousresearch/hermes-3-llama-3.1-70b','Nous: Hermes 3 70B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','nousresearch/hermes-3-llama-3.1-405b','Nous: Hermes 3 405B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','sao10k/l3-lunaris-8b','Sao10K: Llama 3 8B Lunaris（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4o-2024-08-06','OpenAI: GPT-4o (2024-08-06)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta-llama/llama-3.1-70b-instruct','Meta: Llama 3.1 70B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','meta-llama/llama-3.1-8b-instruct','Meta: Llama 3.1 8B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-nemo','Mistral: Mistral Nemo（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4o-mini','OpenAI: GPT-4o-mini（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4o-mini-2024-07-18','OpenAI: GPT-4o-mini (2024-07-18)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','google/gemma-2-27b-it','Google: Gemma 2 27B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4o','OpenAI: GPT-4o（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4o-2024-05-13','OpenAI: GPT-4o (2024-05-13)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mixtral-8x22b-instruct','Mistral: Mixtral 8x22B Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','microsoft/wizardlm-2-8x22b','WizardLM-2 8x22B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4-turbo','OpenAI: GPT-4 Turbo（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mistralai/mistral-large','Mistral Large（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-3.5-turbo-0613','OpenAI: GPT-3.5 Turbo (older v0613)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-3.5-turbo-instruct','OpenAI: GPT-3.5 Turbo Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-3.5-turbo-16k','OpenAI: GPT-3.5 Turbo 16k（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','mancer/weaver','Mancer: Weaver (alpha)（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','undi95/remm-slerp-l2-13b','ReMM SLERP 13B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','gryphe/mythomax-l2-13b','MythoMax 13B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-3.5-turbo','OpenAI: GPT-3.5 Turbo（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_openrouter_provider','LLM','openai/gpt-4','OpenAI: GPT-4（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','MiniMax-H3','MiniMax-H3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','deepseek-v4.1-flash','deepseek-v4.1-flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen3.8-max-0902','qwen3.8-max-0902（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','WeMM-Embedding-9B','WeMM-Embedding-9B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','WeMM-Embedding-4B','WeMM-Embedding-4B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','WeMM-Embedding-2B','WeMM-Embedding-2B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-5.3-Flash','GLM-5.3-Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen3.8-flash','qwen3.8-flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-5.3','GLM-5.3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen3.8-27b','qwen3.8-27b（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','DeepSeek-V4-Pro-0813','DeepSeek-V4-Pro-0813（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','deepseek-v4-flash-0731','deepseek-v4-flash-0731（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen3.8-max','qwen3.8-max（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen-image-2.0-pro','qwen-image-2.0-pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','kimi-k3','kimi-k3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen-image-2.0','qwen-image-2.0（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Kimi-K2.7-Code','Kimi-K2.7-Code（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-5.2','GLM-5.2（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.5-Plus','Qwen3.5-Plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-VL-32B-Thinking','Qwen3-VL-32B-Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-VL-32B-Instruct','Qwen3-VL-32B-Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-VL-8B-Thinking','Qwen3-VL-8B-Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-VL-235B-A22B-Thinking','Qwen3-VL-235B-A22B-Thinking（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-VL-235B-A22B-Instruct','Qwen3-VL-235B-A22B-Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-Coder-Flash','Qwen3-Coder-Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','MiniMax-M3','MiniMax-M3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.7-Plus','Qwen3.7-Plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.6-Flash','Qwen3.6-Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.5-Flash','Qwen3.5-Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.7-Max','Qwen3.7-Max（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen3-coder-plus','qwen3-coder-plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen-mt-plus','qwen-mt-plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen-mt-flash','qwen-mt-flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen-mt-lite','qwen-mt-lite（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen-max','qwen-max（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen3-vl-plus','qwen3-vl-plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen-plus-2025-12-01','qwen-plus-2025-12-01（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','qwen-flash','qwen-flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.6-27B','Qwen3.6-27B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.6-35B-A3B','Qwen3.6-35B-A3B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','DeepSeek-V4-Flash','DeepSeek-V4-Flash（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','DeepSeek-V4-Pro','DeepSeek-V4-Pro（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.6-Plus','Qwen3.6-Plus（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Kimi-K2.6','Kimi-K2.6（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','MiniMax-M2.7','MiniMax-M2.7（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','gemma-4-26B-A4B-it','gemma-4-26B-A4B-it（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-5.1','GLM-5.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.5-122B-A10B','Qwen3.5-122B-A10B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.5-27B','Qwen3.5-27B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3.5-35B-A3B','Qwen3.5-35B-A3B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','MiniMax-M2.5','MiniMax-M2.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-5','GLM-5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-Coder-Next','Qwen3-Coder-Next（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Kimi-K2.5','Kimi-K2.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','Qwen3-VL-Embedding-2B','Qwen3-VL-Embedding-2B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','Qwen3-VL-Embedding-8B','Qwen3-VL-Embedding-8B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-Image','GLM-Image（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen-Image-2512','Qwen-Image-2512（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen-Image-Edit-2511','Qwen-Image-Edit-2511（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','MiniMax-M2.1','MiniMax-M2.1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-4.7','GLM-4.7（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-Coder-30B-A3B-Instruct','Qwen3-Coder-30B-A3B-Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-VL-30B-A3B-Instruct','Qwen3-VL-30B-A3B-Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-Next-80B-A3B-Instruct','Qwen3-Next-80B-A3B-Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen-Image-Edit','Qwen-Image-Edit（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen2.5-VL-7B-Instruct','Qwen2.5-VL-7B-Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-14B','Qwen3-14B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','jina-embeddings-v4','jina-embeddings-v4（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','Qwen3-Embedding-8B','Qwen3-Embedding-8B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','Qwen3-Embedding-4B','Qwen3-Embedding-4B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','Qwen3-Embedding-0.6B','Qwen3-Embedding-0.6B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-4-9B-0414','GLM-4-9B-0414（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','DeepSeek-Prover-V2-7B','DeepSeek-Prover-V2-7B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-4B','Qwen3-4B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-32B','Qwen3-32B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-0.6B','Qwen3-0.6B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen3-8B','Qwen3-8B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','GLM-4-32B','GLM-4-32B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','internlm3-8b-instruct','internlm3-8b-instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','DeepSeek-R1-Distill-Qwen-7B','DeepSeek-R1-Distill-Qwen-7B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','DeepSeek-R1-Distill-Qwen-14B','DeepSeek-R1-Distill-Qwen-14B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','DeepSeek-R1-Distill-Qwen-1.5B','DeepSeek-R1-Distill-Qwen-1.5B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','DeepSeek-R1-Distill-Qwen-32B','DeepSeek-R1-Distill-Qwen-32B（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','bce-embedding-base_v1','bce-embedding-base_v1（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen2.5-7B-Instruct','Qwen2.5-7B-Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','bge-m3','bge-m3（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','glm-4-9b-chat','glm-4-9b-chat（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','deepseek-coder-33B-instruct','deepseek-coder-33B-instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','LLM','Qwen2-7B-Instruct','Qwen2-7B-Instruct（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','bge-small-zh-v1.5','bge-small-zh-v1.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;
INSERT INTO moss_kb_model_catalog(provider,model_type,model_id,description,source) VALUES('model_gitee_provider','EMBEDDING','bge-large-zh-v1.5','bge-large-zh-v1.5（平台目录；实际可用性以当前密钥和保存校验为准）','snapshot-2026-10-03') ON CONFLICT DO NOTHING;

-- 内置函数模板：公开只读，普通用户在界面里复制成自己的函数后再修改。
INSERT INTO moss_kb_function_lib(id,user_id,name,"desc",code,input_field_list,init_field_list,init_params,
  permission_type,function_type,icon,template_id,is_active)
VALUES
(1001, 1, $$博查搜索$$, $$从博查搜索任何信息和网页URL$$, $$def bocha_search(query, apikey):
    import requests
    import json
    url = "https://api.bochaai.com/v1/web-search"
    payload = json.dumps({
        "query": query,
        "Boolean": "true",
        "count": 8
    })

    headers = {
        "Authorization": "Bearer " + apikey, #鉴权参数，示例：Bearer xxxxxx，API KEY请先前往博查AI开放平台（https://open.bochaai.com）> API KEY 管理中获取。
        "Content-Type": "application/json"
    }

    response = requests.request("POST", url, headers=headers, data=payload)
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"API请求失败: {response.status_code}, 错误信息: {response.text}")
        return (response.text)$$, $$[{"name": "query", "type": "string", "source": "reference", "is_required": true}]$$::jsonb, $$[{"attrs": {"type": "password", "maxlength": 200, "minlength": 1, "show-password": true, "show-word-limit": true}, "field": "apikey", "label": "API Key", "required": true, "input_type": "PasswordInput", "props_info": {"rules": [{"message": "API Key 为必填属性", "required": true}, {"max": 200, "min": 1, "message": "API Key 长度在 1 到 200 个字符", "trigger": "blur"}]}, "default_value": "x", "show_default_value": false}]$$::jsonb, '{}'::jsonb,
  'PUBLIC', 'INTERNAL', $$/ui/fx/bochaai/icon.png$$, NULL, true),
(1002, 1, $$Google Search$$, $$Google Web Search$$, $$def google_search(query, apikey, cx):
    import requests
    import json
    url = "https://customsearch.googleapis.com/customsearch/v1"
    params = {
        "q": query,
        "key": apikey,
        "cx": cx,
        "num": 10,  # 每次最多返回10条
    }

    response = requests.get(url, params=params)
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"API请求失败: {response.status_code}, 错误信息: {response.text}")
        return (response.text)$$, $$[{"name": "query", "type": "string", "source": "reference", "is_required": true}]$$::jsonb, $$[{"attrs": {"type": "password", "maxlength": 200, "minlength": 1, "show-password": true, "show-word-limit": true}, "field": "apikey", "label": "API Key", "required": true, "input_type": "PasswordInput", "props_info": {"rules": [{"message": "API Key 为必填属性", "required": true}, {"max": 200, "min": 1, "message": "API Key 长度在 1 到 200 个字符", "trigger": "blur"}]}, "default_value": "x", "show_default_value": false}, {"attrs": {"maxlength": 200, "minlength": 1, "show-word-limit": true}, "field": "cx", "label": "cx", "required": true, "input_type": "TextInput", "props_info": {"rules": [{"message": "cx 为必填属性", "required": true}, {"max": 200, "min": 1, "message": "cx长度在 1 到 200 个字符", "trigger": "blur"}]}, "default_value": "x", "show_default_value": false}]$$::jsonb, '{}'::jsonb,
  'PUBLIC', 'INTERNAL', $$/ui/fx/google_search/icon.png$$, NULL, true),
(1003, 1, $$LangSearch$$, $$A Web Search tool supporting natural language search
$$, $$def langsearch(query, apikey):
    import json
    import requests

    url = "https://api.langsearch.com/v1/web-search"
    payload = json.dumps({
        "query": query,
        "summary": True,
        "freshness": "noLimit",
        "livecrawl": True,
        "count": 20
    })
    headers = {
        "Authorization": apikey,
        "Content-Type": "application/json"
    }
    # key从官网申请 https://langsearch.com/
    response = requests.request("POST", url, headers=headers, data=payload)
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"API请求失败: {response.status_code}, 错误信息: {response.text}")
        return (response.text)$$, $$[{"name": "query", "type": "string", "source": "reference", "is_required": true}]$$::jsonb, $$[{"attrs": {"type": "password", "maxlength": 200, "minlength": 1, "show-password": true, "show-word-limit": true}, "field": "apikey", "label": "API Key", "required": true, "input_type": "PasswordInput", "props_info": {"rules": [{"message": "API Key 为必填属性", "required": true}, {"max": 200, "min": 1, "message": "API Key 长度在 1 到 200 个字符", "trigger": "blur"}]}, "default_value": "x", "show_default_value": false}]$$::jsonb, '{}'::jsonb,
  'PUBLIC', 'INTERNAL', $$/ui/fx/langsearch/icon.png$$, NULL, true),
(1004, 1, $$MySQL 查询$$, $$一个连接MySQL数据库执行SQL查询的工具$$, $$def query_mysql(host,port, user, password, database, sql):
    import pymysql
    import json
    from pymysql.cursors import DictCursor

    try:
        # 创建连接
        db = pymysql.connect(
            host=host,
            port=int(port),
            user=user,
            password=password,
            database=database,
            cursorclass=DictCursor  # 使用字典游标
        )

        # 使用 cursor() 方法创建一个游标对象 cursor
        cursor = db.cursor()

        # 使用 execute() 方法执行 SQL 查询
        cursor.execute(sql)

        # 使用 fetchall() 方法获取所有数据
        data = cursor.fetchall()

        # 处理 bytes 类型的数据
        for row in data:
            for key, value in row.items():
                if isinstance(value, bytes):
                    row[key] = value.decode("utf-8")  # 转换为字符串

        # 将数据序列化为 JSON
        json_data = json.dumps(data, ensure_ascii=False)
        return json_data

        # 关闭数据库连接
        db.close()

    except Exception as e:
        print(f"Error while connecting to MySQL: {e}")
        raise e$$, $$[{"name": "sql", "type": "string", "source": "reference", "is_required": true}]$$::jsonb, $$[{"attrs": {"maxlength": 200, "minlength": 1, "show-word-limit": true}, "field": "host", "label": "host", "required": true, "input_type": "TextInput", "props_info": {"rules": [{"message": "host 为必填属性", "required": true}, {"max": 200, "min": 1, "message": "host长度在 1 到 200 个字符", "trigger": "blur"}]}, "default_value": "x", "show_default_value": false}, {"attrs": {"maxlength": 20, "minlength": 1, "show-word-limit": true}, "field": "port", "label": "port", "required": true, "input_type": "TextInput", "props_info": {"rules": [{"message": "port 为必填属性", "required": true}, {"max": 20, "min": 1, "message": "port长度在 1 到 20 个字符", "trigger": "blur"}]}, "default_value": "3306", "show_default_value": false}, {"attrs": {"maxlength": 200, "minlength": 1, "show-word-limit": true}, "field": "user", "label": "user", "required": true, "input_type": "TextInput", "props_info": {"rules": [{"message": "user 为必填属性", "required": true}, {"max": 200, "min": 1, "message": "user长度在 1 到 200 个字符", "trigger": "blur"}]}, "default_value": "root", "show_default_value": false}, {"attrs": {"type": "password", "maxlength": 200, "minlength": 1, "show-password": true, "show-word-limit": true}, "field": "password", "label": "password", "required": true, "input_type": "PasswordInput", "props_info": {"rules": [{"message": "password 为必填属性", "required": true}, {"max": 200, "min": 1, "message": "password长度在 1 到 200 个字符", "trigger": "blur"}]}, "default_value": "x", "show_default_value": false}, {"attrs": {"maxlength": 200, "minlength": 1, "show-word-limit": true}, "field": "database", "label": "database", "required": true, "input_type": "TextInput", "props_info": {"rules": [{"message": "database 为必填属性", "required": true}, {"max": 200, "min": 1, "message": "database长度在 1 到 200 个字符", "trigger": "blur"}]}, "default_value": "x", "show_default_value": false}]$$::jsonb, '{}'::jsonb,
  'PUBLIC', 'INTERNAL', $$/ui/fx/mysql/icon.png$$, NULL, true),
(1005, 1, $$PostgreSQL 查询$$, $$一个连接PostgreSQL数据库执行SQL查询的工具$$, $$def queryPgSQL(database, user, password, host, port, query):
    import psycopg2
    import json
    from datetime import datetime

    # 自定义 JSON 序列化函数
    def default_serializer(obj):
        if isinstance(obj, datetime):
            return obj.isoformat()  # 将 datetime 转换为 ISO 格式字符串
        raise TypeError(f"Type {type(obj)} not serializable")

    # 数据库连接信息
    conn_params = {
        "dbname": database,
        "user": user,
        "password": password,
        "host": host,
        "port": port
    }
    try:
        # 建立连接
        conn = psycopg2.connect(**conn_params)
        print("连接成功！")
        # 创建游标对象
        cursor = conn.cursor()
        # 执行查询语句
        cursor.execute(query)
        # 获取查询结果
        rows = cursor.fetchall()
        # 处理 bytes 类型的数据
        columns = [desc[0] for desc in cursor.description]
        result = [dict(zip(columns, row)) for row in rows]
        # 转换为 JSON 格式
        json_result = json.dumps(result, default=default_serializer, ensure_ascii=False)
        return json_result
    except Exception as e:
        print(f"发生错误：{e}")
        raise e
    finally:
        # 关闭游标和连接
        if cursor:
            cursor.close()
        if conn:
            conn.close()$$, $$[{"name": "query", "type": "string", "source": "reference", "is_required": true}]$$::jsonb, $$[{"attrs":{"maxlength":200,"minlength":1,"show-word-limit":true},"field":"host","label":"host","required":true,"input_type":"TextInput","props_info":{"rules":[{"message":"host 为必填属性","required":true},{"max":200,"min":1,"message":"host长度在 1 到 200 个字符","trigger":"blur"}]},"default_value":"x","show_default_value":false},{"attrs":{"maxlength":20,"minlength":1,"show-word-limit":true},"field":"port","label":"port","required":true,"input_type":"TextInput","props_info":{"rules":[{"message":"port 为必填属性","required":true},{"max":20,"min":1,"message":"port长度在 1 到 20 个字符","trigger":"blur"}]},"default_value":"5432","show_default_value":false},{"attrs":{"maxlength":200,"minlength":1,"show-word-limit":true},"field":"user","label":"user","required":true,"input_type":"TextInput","props_info":{"rules":[{"message":"user 为必填属性","required":true},{"max":200,"min":1,"message":"user长度在 1 到 200 个字符","trigger":"blur"}]},"default_value":"root","show_default_value":false},{"attrs":{"type":"password","maxlength":200,"minlength":1,"show-password":true,"show-word-limit":true},"field":"password","label":"password","required":true,"input_type":"PasswordInput","props_info":{"rules":[{"message":"password 为必填属性","required":true},{"max":200,"min":1,"message":"password长度在 1 到 200 个字符","trigger":"blur"}]},"default_value":"x","show_default_value":false},{"attrs":{"maxlength":200,"minlength":1,"show-word-limit":true},"field":"database","label":"database","required":true,"input_type":"TextInput","props_info":{"rules":[{"message":"database 为必填属性","required":true},{"max":200,"min":1,"message":"database长度在 1 到 200 个字符","trigger":"blur"}]},"default_value":"x","show_default_value":false}]$$::jsonb, '{}'::jsonb,
  'PUBLIC', 'INTERNAL', $$/ui/fx/postgresql/icon.png$$, NULL, true)
ON CONFLICT (id) DO NOTHING;

-- Each existing account keeps its resources in its own team. New members inherit their administrator's team.
UPDATE moss_kb_user SET tenant_id = id WHERE tenant_id = 0;
UPDATE moss_kb_user SET role = 'SUPER_ADMIN' WHERE id = 1 AND username = 'admin';
CREATE INDEX IF NOT EXISTS moss_kb_user_team_idx ON moss_kb_user(tenant_id);

CREATE TABLE IF NOT EXISTS moss_kb_team_setting (
  team_id BIGINT NOT NULL,
  name VARCHAR(64) NOT NULL,
  value JSONB NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY(team_id, name)
);

COMMIT;
