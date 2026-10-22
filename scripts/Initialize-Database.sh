#!/usr/bin/env bash
#
# 初始化或升级 Java MossKB 数据库（Linux / WSL）。
#
# 读取 mosskb-web/my.txt 里的连接参数，执行 db/init.sql。
# SQL 可重复执行：空库会建好 31 张业务表并写入管理员、默认模型、平台目录和
# 内置函数模板；已有库会补齐缺失的表、列和索引，并执行内置的平台目录维护逻辑。
#
# 用法：
#   ./scripts/Initialize-Database.sh                 # 初始化或升级
#   ./scripts/Initialize-Database.sh --reset         # 先删除全部业务表再重建
#   ./scripts/Initialize-Database.sh --psql /usr/bin/psql
#   ./scripts/Initialize-Database.sh --config /path/to/my.txt
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/mosskb-web/my.txt"
PSQL_BIN="${PSQL:-psql}"
DO_RESET=0

usage() {
  sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset)
      DO_RESET=1
      shift
      ;;
    --config)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --psql)
      PSQL_BIN="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "找不到配置文件：${CONFIG_FILE}" >&2
  exit 1
fi

if ! command -v "${PSQL_BIN}" >/dev/null 2>&1; then
  echo "找不到 psql：${PSQL_BIN}。Ubuntu 可执行 sudo apt install -y postgresql-client。" >&2
  exit 1
fi

read_config() {
  local key="$1"
  local value
  value="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${CONFIG_FILE}" | tail -n 1 | sed -E 's/^[^=]*=[[:space:]]*//' | tr -d '\r')"
  if [[ -z "${value}" ]]; then
    echo "配置文件缺少 ${key}：${CONFIG_FILE}" >&2
    exit 1
  fi
  printf '%s' "${value}"
}

JDBC_URL="$(read_config jdbc.url)"
DB_USER="$(read_config jdbc.user)"
DB_PASSWORD="$(read_config jdbc.pswd)"

REST="${JDBC_URL#jdbc:postgresql://}"
HOST_PORT="${REST%%/*}"
DB_NAME="${REST#*/}"
DB_HOST="${HOST_PORT%%:*}"
DB_PORT="${HOST_PORT#*:}"
if [[ "${DB_PORT}" == "${DB_HOST}" ]]; then
  DB_PORT=5432
fi
if [[ -z "${DB_HOST}" || -z "${DB_NAME}" || "${DB_NAME}" == "${REST}" ]]; then
  echo "无法解析 jdbc.url：${JDBC_URL}" >&2
  exit 1
fi

SCRIPTS=()
if [[ "${DO_RESET}" -eq 1 ]]; then
  SCRIPTS+=("${PROJECT_ROOT}/db/reset.sql")
fi
SCRIPTS+=("${PROJECT_ROOT}/db/init.sql")

export PGPASSWORD="${DB_PASSWORD}"
export PGCLIENTENCODING="UTF8"

for script in "${SCRIPTS[@]}"; do
  echo "执行 $(basename "${script}")"
  "${PSQL_BIN}" -X -w -q -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
    -v ON_ERROR_STOP=1 -f "${script}"
done

TABLE_COUNT="$("${PSQL_BIN}" -X -w -q -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")"

echo "数据库结构与初始数据已就绪，public 表 ${TABLE_COUNT} 张。"
