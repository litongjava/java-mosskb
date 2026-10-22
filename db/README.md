# 数据库初始化与安装

完整环境配置、前后端构建和启动见 [项目 README](../readme.md#配置与初始化)。Windows/Linux 的 PostgreSQL 与 pgvector 安装步骤见[部署章节](https://tio-boot.com/zh/knowledge-base/38)。

## 准备数据库

安装并启动 PostgreSQL，在数据库服务端安装与其版本匹配的 pgvector 和 pg_trgm。`CREATE EXTENSION` 只能启用已安装的扩展，不能安装缺失的扩展文件。

使用有建库权限的账号创建业务数据库（已有库跳过）：

```bash
createdb -h 127.0.0.1 -p 5432 -U postgres -E UTF8 moss_kb
```

执行初始化的账号需要有建表和启用扩展的权限。数据库名称可自行调整，并与 `mosskb-web/my.txt` 中的 `jdbc.url` 保持一致。

## 一个 SQL 完成初始化

在 Java 仓库根目录执行：

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d moss_kb -v ON_ERROR_STOP=1 -f db/init.sql
```

密码由 psql 提示输入。也可以在数据库客户端中连接业务库后执行 `db/init.sql`。

`init.sql` 在同一个事务中执行建表和初始数据写入，失败则整体回滚。包含扩展、31 张业务表、索引、外键、旧库缺失列、管理员账号、默认模型、12 个平台接入信息、模型目录快照与内置函数模板。无需再分别执行 schema.sql 和 seed.sql。

初始登录账号：`admin`，密码：`Kimi@2024`。首次登录后修改密码。

## 使用初始化脚本

先按项目 README 配置 `mosskb-web/my.txt`，再运行以下任一命令；脚本会读取数据库连接并执行同一个 `db/init.sql`：

```powershell
# Windows
.\scripts\Initialize-Database.ps1
```

```bash
# Linux / WSL
./scripts/Initialize-Database.sh
```

## 升级与清空重建

`init.sql` 可重复执行，补齐结构和初始数据，保留已有的平台图标更新、默认模型修正和失效模型清理逻辑。升级已有数据库前先备份，在测试库验证。

`reset.sql` 是独立的清空脚本，会删除业务表及其中数据，保留数据库和扩展。仅需要清空重建时使用：

```powershell
.\scripts\Initialize-Database.ps1 -Reset
```

```bash
./scripts/Initialize-Database.sh --reset
```

顺序为 `reset.sql -> init.sql`。正常初始化不执行 reset。

31 张表中，29 张以 `moss_kb_` 开头，另外两张为 `system_setting` 和 `libre_office_converted_mapping`。

## 更新模型目录

SQL 中的平台模型列表是历史快照，不代表所有模型当前可用。管理员可刷新目录：

```bash
python scripts/Sync-ModelCatalog.py --source openrouter --token-file <管理员令牌文件>
```

刷新 Gitee 时将来源改为 `gitee`，并先在当前进程环境中设置 `GITEE_API_KEY`。
