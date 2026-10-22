# 后端原生部署

通过 deploy-server 在服务器从 `git@gitee.com:ppnt/java-mosskb.git` 的 `main` 分支拉取源码，按 `build.txt` 运行 Maven 生产构建，使用 Java 21 和 systemd 启动后端。无需 Docker，不构建或部署前端。

首次部署前按项目 README 在 `/srv/apps/java-mosskb` 放置 `my.txt` 和 `secrets.txt`，权限设为 `600`。此部署脚本使用本机 PostgreSQL、数据库 `mosskb`、账号 `postgres`，密码从 `my.txt` 读取；确保连接配置一致。缺失数据库会创建，已有库执行初始化 SQL 前应备份。

```bash
deploy --server 97 project create --file deploy/project.json --json
deploy --server 97 run java-mosskb --wait --json
```

项目已存在时直接运行，不要重复创建。脚本自动安装独立 Java 21 和系统 Maven；初次执行需要可访问下载源和 Maven 仓库。使用宿主 Python 沙箱时服务以 root 运行，Python 任务通过 runuser 切换到专用用户。

- 服务：`java-mosskb.service`
- 发布目录：`/srv/apps/java-mosskb`
- 后端端口：`10060`
- 日志：`journalctl -u java-mosskb.service`
- 健康检查：`http://127.0.0.1:10060/api/display/info`

配置文件和密钥不提交到仓库。部署前需确认端口空闲，脚本会替换该后端服务的 JAR 和 systemd 配置并重启服务。
