set -euo pipefail
umask 077
APP=/srv/apps/java-mosskb
mkdir -p "$APP" /usr/java/jdk-21.0.6 /srv/workspaces/mosskb-backend
if [ ! -x /usr/java/jdk-21.0.6/bin/java ]; then
 curl -fL -C - --retry 3 --connect-timeout 20 --max-time 600 https://gitcode.com/ppnt/oracle-jdk/releases/download/21.0.6/jdk-21_linux-x64_bin.tar.gz -o /srv/workspaces/mosskb-backend/oracle-jdk-21.0.6.tar.gz
 tar -xzf /srv/workspaces/mosskb-backend/oracle-jdk-21.0.6.tar.gz -C /usr/java/jdk-21.0.6 --strip-components=1
fi
/usr/java/jdk-21.0.6/bin/java -version
export JAVA_HOME=/usr/java/jdk-21.0.6
export PATH="$JAVA_HOME/bin:$PATH"
if ! command -v mvn >/dev/null; then
 apt-get update
 DEBIAN_FRONTEND=noninteractive apt-get install -y maven
fi
cd /srv/workspaces/java-mosskb
cat build.txt
mvn clean package -DskipTests -Dgpg.skip=true -Pproduction
BACKUP="$APP/backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP"
if [ -f "$APP/app.jar" ]; then
 cp -p "$APP/app.jar" "$BACKUP/app.jar"
fi
install -m 600 mosskb-web/target/mosskb-web-1.0.4.jar "$APP/app.jar"
install -m 600 db/init.sql "$APP/init.sql"
install -m 700 scripts/setup-python-host-sandbox.sh "$APP/sandbox.sh"
cd "$APP"
if [ ! -f my.txt ] || [ ! -f secrets.txt ]; then
 echo 'Place my.txt and secrets.txt in /srv/apps/java-mosskb before deployment.' >&2
 exit 1
fi
chmod 600 my.txt secrets.txt
export PGPASSWORD=$(sed -n 's/^jdbc.pswd=//p' my.txt)
if ! psql -h 127.0.0.1 -U postgres -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='mosskb'" | grep -q 1; then
 createdb -h 127.0.0.1 -U postgres -E UTF8 mosskb
fi
pg_dump -h 127.0.0.1 -U postgres -d mosskb -Fc -f "$BACKUP/mosskb.dump"
pg_restore --list "$BACKUP/mosskb.dump" > "$BACKUP/contents.txt"
echo "Backup saved: $BACKUP"
git -C /srv/workspaces/java-mosskb rev-parse HEAD
psql -X -h 127.0.0.1 -U postgres -d mosskb -v ON_ERROR_STOP=1 -f init.sql > database-init.log 2>&1
psql -h 127.0.0.1 -U postgres -d mosskb -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'; SELECT model_name FROM moss_kb_model WHERE id=1001;"
unset PGPASSWORD
bash sandbox.sh mosskb-sandbox /var/lib/java-mosskb/sandbox /usr/bin/python3
cat > /etc/systemd/system/java-mosskb.service <<'UNIT'
[Unit]
Description=Java MossKB Backend
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
WorkingDirectory=/srv/apps/java-mosskb
ExecStart=/usr/java/jdk-21.0.6/bin/java -Xms256m -Xmx2g -jar /srv/apps/java-mosskb/app.jar
Restart=on-failure
RestartSec=5
UMask=0077
Environment=TZ=Asia/Shanghai
Environment=LANG=C.UTF-8
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable java-mosskb.service
systemctl restart java-mosskb.service
for i in $(seq 1 60); do
 if curl -fsS http://127.0.0.1:10060/api/display/info -o /srv/workspaces/mosskb-backend/health.json; then
  cat /srv/workspaces/mosskb-backend/health.json
  systemctl is-active java-mosskb.service
  exit 0
 fi
 sleep 2
done
journalctl -u java-mosskb.service -n 80 --no-pager
exit 1
