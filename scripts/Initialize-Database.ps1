# 初始化或升级 Java MossKB 数据库。
#
# 读取 mosskb-web/my.txt 里的连接参数，执行 db/init.sql。
# SQL 可重复执行：空库会建好 31 张业务表并写入管理员、默认模型、平台目录和
# 内置函数模板；已有库会补齐缺失的表、列和索引，并执行内置的平台目录维护逻辑。
#
# 参数：
#   -PostgresBin  PostgreSQL 的 bin 目录。省略时使用 PATH 上的 psql。
#   -ConfigFile   连接配置文件，默认 mosskb-web/my.txt。
#   -Reset        先执行 db/reset.sql 删除全部业务表，再重建，适合本地反复验证。
#
# 示例：
#   .\scripts\Initialize-Database.ps1
#   .\scripts\Initialize-Database.ps1 -Reset
#   .\scripts\Initialize-Database.ps1 -PostgresBin 'D:\Program Files\PostgreSQL\18\bin'

param(
  [string]$PostgresBin = '',
  [string]$ConfigFile = (Join-Path $PSScriptRoot '../mosskb-web/my.txt'),
  [switch]$Reset
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path -LiteralPath $ConfigFile)) {
  throw "找不到配置文件：$ConfigFile"
}

if ($PostgresBin) {
  $psql = Join-Path $PostgresBin 'psql.exe'
} else {
  $command = Get-Command psql -ErrorAction SilentlyContinue
  if (!$command) {
    throw '找不到 psql。请把 PostgreSQL 的 bin 目录加入 PATH，或用 -PostgresBin 指定。'
  }
  $psql = $command.Source
}
if (!(Test-Path -LiteralPath $psql)) {
  throw "找不到 psql：$psql"
}

$settings = @{}
Get-Content -LiteralPath $ConfigFile | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    $settings[$matches[1].Trim()] = $matches[2].Trim()
  }
}

foreach ($key in @('jdbc.url', 'jdbc.user', 'jdbc.pswd')) {
  if (!$settings.ContainsKey($key)) {
    throw "配置文件缺少 $key：$ConfigFile"
  }
}

$databaseUri = [uri]($settings['jdbc.url'] -replace '^jdbc:', '')
$databaseName = $databaseUri.AbsolutePath.TrimStart('/')
$dbRoot = (Resolve-Path (Join-Path $PSScriptRoot '../db')).Path

$scripts = New-Object System.Collections.Generic.List[string]
if ($Reset) {
  $scripts.Add((Join-Path $dbRoot 'reset.sql'))
}
$scripts.Add((Join-Path $dbRoot 'init.sql'))

$previousPassword = $env:PGPASSWORD
$previousEncoding = $env:PGCLIENTENCODING
$previousOptions = $env:PGOPTIONS
try {
  $env:PGPASSWORD = $settings['jdbc.pswd']
  $env:PGCLIENTENCODING = 'UTF8'
  # NOTICE 走 stderr，会被 PowerShell 当成错误记录，这里只保留 warning 及以上。
  $env:PGOPTIONS = '-c client_min_messages=warning'
  foreach ($script in $scripts) {
    Write-Output "执行 $([System.IO.Path]::GetFileName($script))"
    & $psql -X -w -q -h $databaseUri.Host -p $databaseUri.Port -U $settings['jdbc.user'] -d $databaseName -v ON_ERROR_STOP=1 -f $script
    if ($LASTEXITCODE -ne 0) {
      throw "数据库脚本执行失败：$script"
    }
  }
  $tableCount = & $psql -X -w -q -h $databaseUri.Host -p $databaseUri.Port -U $settings['jdbc.user'] -d $databaseName -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';"
  if ($LASTEXITCODE -ne 0) {
    throw '读取表数量失败。'
  }
} finally {
  $env:PGPASSWORD = $previousPassword
  $env:PGCLIENTENCODING = $previousEncoding
  $env:PGOPTIONS = $previousOptions
}

Write-Output "数据库结构与初始数据已就绪，public 表 $tableCount 张。"
exit 0
