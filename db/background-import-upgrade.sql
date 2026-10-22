BEGIN;
ALTER TABLE moss_kb_document_split_task ADD COLUMN IF NOT EXISTS import_dataset_id BIGINT;
ALTER TABLE moss_kb_document_split_task ADD COLUMN IF NOT EXISTS import_status VARCHAR(16);
ALTER TABLE moss_kb_document_split_task ADD COLUMN IF NOT EXISTS import_error TEXT;
COMMIT;
