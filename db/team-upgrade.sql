BEGIN;
UPDATE moss_kb_user SET tenant_id = id WHERE tenant_id = 0;
UPDATE moss_kb_user SET role = 'SUPER_ADMIN', token_version = token_version + 1
WHERE id = 1 AND username = 'admin' AND role <> 'SUPER_ADMIN';
CREATE INDEX IF NOT EXISTS moss_kb_user_team_idx ON moss_kb_user(tenant_id);
CREATE TABLE IF NOT EXISTS moss_kb_team_setting (
  team_id BIGINT NOT NULL,
  name VARCHAR(64) NOT NULL,
  value JSONB NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY(team_id, name)
);
COMMIT;
