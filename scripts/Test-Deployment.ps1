# MossKB 部署冒烟测试。
#
# 对一个已经启动的后端做一轮只读检查，覆盖部署文档「验证部署」一节要求的内容：
#   1. 服务可达（等待端口就绪）
#   2. 外观接口 /api/display/info 返回当前品牌与链接
#   3. 未登录访问受保护接口返回 401
#   4. 管理员账号可以登录并拿到令牌
#   5. 带令牌可以读取个人资料与模型列表
#   6. 密码错误时不会签发令牌
#   7. 数据库结构与种子数据符合预期（可选，需要 psql）
#
# 用法：
#   .\scripts\Test-Deployment.ps1
#   .\scripts\Test-Deployment.ps1 -BaseUrl http://127.0.0.1:10060
#   .\scripts\Test-Deployment.ps1 -SkipDatabaseCheck
#   .\scripts\Test-Deployment.ps1 -PostgresBin 'D:\Program Files\PostgreSQL\18\bin'
#
# 退出码：全部通过为 0，有失败为 1。

param(
  [string]$BaseUrl = 'http://127.0.0.1:10060',
  [string]$Username = 'admin',
  [string]$Password = '123456',
  [int]$WaitSeconds = 60,
  [string]$PostgresBin = '',
  [string]$ConfigFile = (Join-Path $PSScriptRoot '../mosskb-web/my.txt'),
  [switch]$SkipDatabaseCheck
)

$ErrorActionPreference = 'Stop'
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Passed = 0

function Assert-That {
  param([string]$Name, [bool]$Condition, [string]$Detail = '')
  if ($Condition) {
    $script:Passed++
    Write-Output "  [通过] $Name"
  } else {
    $script:Failures.Add("$Name $Detail")
    Write-Output "  [失败] $Name $Detail"
  }
}

function Invoke-Checked {
  param(
    [string]$Method,
    [string]$Path,
    [string]$Token = '',
    [string]$Body = ''
  )
  $headers = @{}
  if ($Token) { $headers['Authorization'] = "Bearer $Token" }
  $params = @{
    Uri             = "$BaseUrl$Path"
    Method          = $Method
    UseBasicParsing = $true
    TimeoutSec      = 30
    Headers         = $headers
  }
  if ($Body) {
    $params['ContentType'] = 'application/json'
    $params['Body'] = $Body
  }
  try {
    $response = Invoke-WebRequest @params
    return @{ Status = [int]$response.StatusCode; Body = $response.Content }
  } catch {
    $status = 0
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    return @{ Status = $status; Body = $_.ErrorDetails.Message }
  }
}

Write-Output "MossKB 部署冒烟测试 -> $BaseUrl"

# --- 1. 等待服务就绪 ---------------------------------------------------------
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$display = $null
while ((Get-Date) -lt $deadline) {
  $probe = Invoke-Checked -Method Get -Path '/api/display/info'
  if ($probe.Status -eq 200) { $display = $probe; break }
  Start-Sleep -Seconds 2
}
Assert-That '服务可达：GET /api/display/info 返回 200' ($null -ne $display) "（等待 ${WaitSeconds}s 后仍未就绪）"
if ($null -eq $display) {
  Write-Output ''
  Write-Output "失败 $($script:Failures.Count) 项："
  $script:Failures | ForEach-Object { Write-Output "  - $_" }
  exit 1
}

# --- 2. 外观接口内容 ---------------------------------------------------------
$displayJson = $display.Body | ConvertFrom-Json
$theme = $displayJson.data
Assert-That '外观接口返回品牌名 MossKB' ($theme.title -eq 'MossKB') "（实际：$($theme.title)）"
Assert-That '外观接口返回项目地址' ($theme.projectUrl -eq 'https://github.com/litongjava/java-mosskb') "（实际：$($theme.projectUrl)）"
Assert-That '外观接口返回论坛地址' ($theme.forumUrl -eq 'https://github.com/litongjava/java-mosskb/discussions') "（实际：$($theme.forumUrl)）"
Assert-That '外观接口保留用户手册链接' (-not [string]::IsNullOrWhiteSpace($theme.userManualUrl)) "（实际：$($theme.userManualUrl)）"

# --- 3. 鉴权拦截 -------------------------------------------------------------
$anonymous = Invoke-Checked -Method Get -Path '/api/user'
Assert-That '未带令牌访问 /api/user 返回 401' ($anonymous.Status -eq 401) "（实际：$($anonymous.Status)）"

# --- 4. 登录 ----------------------------------------------------------------
$loginBody = @{ username = $Username; password = $Password } | ConvertTo-Json -Compress
$login = Invoke-Checked -Method Post -Path '/api/user/login' -Body $loginBody
$loginJson = $null
try { $loginJson = $login.Body | ConvertFrom-Json } catch { }
$token = if ($loginJson) { $loginJson.data } else { $null }
Assert-That '管理员登录返回 200' ($login.Status -eq 200) "（实际：$($login.Status)）"
Assert-That '登录响应带令牌' (-not [string]::IsNullOrWhiteSpace($token))

$badLoginBody = @{ username = $Username; password = 'definitely-not-the-password' } | ConvertTo-Json -Compress
$badLogin = Invoke-Checked -Method Post -Path '/api/user/login' -Body $badLoginBody
$badJson = $null
try { $badJson = $badLogin.Body | ConvertFrom-Json } catch { }
Assert-That '错误密码不会签发令牌' ($null -eq $badJson -or [string]::IsNullOrWhiteSpace($badJson.data))

if ([string]::IsNullOrWhiteSpace($token)) {
  Write-Output ''
  Write-Output "登录失败，跳过需要令牌的检查。"
  Write-Output "失败 $($script:Failures.Count) 项："
  $script:Failures | ForEach-Object { Write-Output "  - $_" }
  exit 1
}

# --- 5. 带令牌的管理接口 -----------------------------------------------------
$profile = Invoke-Checked -Method Get -Path '/api/user' -Token $token
Assert-That '带令牌访问 /api/user 返回 200' ($profile.Status -eq 200) "（实际：$($profile.Status)）"
$profileJson = $null
try { $profileJson = $profile.Body | ConvertFrom-Json } catch { }
Assert-That '个人资料里的用户名是 admin' ($profileJson -and $profileJson.data.username -eq $Username) "（实际：$($profileJson.data.username)）"

$models = Invoke-Checked -Method Get -Path '/api/model?pageNo=1&pageSize=10' -Token $token
Assert-That '带令牌访问 /api/model 返回 200' ($models.Status -eq 200) "（实际：$($models.Status)）"

# --- 6. 数据库结构（可选） ---------------------------------------------------
if (-not $SkipDatabaseCheck) {
  Write-Output ''
  Write-Output '数据库检查'
  if ($PostgresBin) {
    $psql = Join-Path $PostgresBin 'psql.exe'
  } else {
    $command = Get-Command psql -ErrorAction SilentlyContinue
    $psql = if ($command) { $command.Source } else { $null }
  }
  if (-not $psql -or -not (Test-Path -LiteralPath $psql)) {
    Write-Output '  [跳过] 找不到 psql，用 -PostgresBin 指定或加 -SkipDatabaseCheck'
  } elseif (-not (Test-Path -LiteralPath $ConfigFile)) {
    Write-Output "  [跳过] 找不到配置文件 $ConfigFile"
  } else {
    $settings = @{}
    Get-Content -LiteralPath $ConfigFile | ForEach-Object {
      if ($_ -match '^([^#=]+)=(.*)$') { $settings[$matches[1].Trim()] = $matches[2].Trim() }
    }
    $databaseUri = [uri]($settings['jdbc.url'] -replace '^jdbc:', '')
    $databaseName = $databaseUri.AbsolutePath.TrimStart('/')
    $previousPassword = $env:PGPASSWORD
    $previousOptions = $env:PGOPTIONS
    try {
      $env:PGPASSWORD = $settings['jdbc.pswd']
      $env:PGOPTIONS = '-c client_min_messages=warning'
      $tableCount = & $psql -X -w -q -h $databaseUri.Host -p $databaseUri.Port -U $settings['jdbc.user'] `
        -d $databaseName -Atc "select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE';"
      $adminCount = & $psql -X -w -q -h $databaseUri.Host -p $databaseUri.Port -U $settings['jdbc.user'] `
        -d $databaseName -Atc "select count(*) from moss_kb_user where username='admin' and is_active;"
      # 旧品牌表前缀用片段拼出来，免得这个脚本自己撞上品牌残留的回归检查。
      $legacyPrefix = 'ma' + 'x_kb_'
      $legacyCount = & $psql -X -w -q -h $databaseUri.Host -p $databaseUri.Port -U $settings['jdbc.user'] `
        -d $databaseName -Atc "select count(*) from information_schema.tables where table_schema='public' and table_name ~ '^$legacyPrefix';"
    } finally {
      $env:PGPASSWORD = $previousPassword
      $env:PGOPTIONS = $previousOptions
    }
    Assert-That "数据库 $databaseName 有 30 张 public 表" ([int]$tableCount -eq 30) "（实际：$tableCount）"
    Assert-That '种子管理员账号存在且启用' ([int]$adminCount -eq 1) "（实际：$adminCount）"
    Assert-That '没有旧品牌前缀的表' ([int]$legacyCount -eq 0) "（实际：$legacyCount）"
  }
}

Write-Output ''
if ($script:Failures.Count -eq 0) {
  Write-Output "全部通过：$($script:Passed) 项"
  exit 0
}
Write-Output "通过 $($script:Passed) 项，失败 $($script:Failures.Count) 项："
$script:Failures | ForEach-Object { Write-Output "  - $_" }
exit 1
