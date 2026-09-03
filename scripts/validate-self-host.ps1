[CmdletBinding()]
param(
  [switch]$RequireDocker
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$deployRoot = Join-Path $repositoryRoot 'deploy/self-host'
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Read-RequiredFile {
  param([Parameter(Mandatory = $true)][string]$RelativePath)

  $path = Join-Path $repositoryRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $script:failures.Add("Missing required file: $RelativePath")
    return ''
  }

  return Get-Content -LiteralPath $path -Raw
}

function Require-Match {
  param(
    [Parameter(Mandatory = $true)][string]$Content,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ($Content -notmatch $Pattern) {
    $script:failures.Add($Message)
  }
}

function Forbid-Match {
  param(
    [Parameter(Mandatory = $true)][string]$Content,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ($Content -match $Pattern) {
    $script:failures.Add($Message)
  }
}

function Require-MinimumMatches {
  param(
    [Parameter(Mandatory = $true)][string]$Content,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][int]$Minimum,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ([regex]::Matches($Content, $Pattern).Count -lt $Minimum) {
    $script:failures.Add($Message)
  }
}

$compose = Read-RequiredFile 'deploy/self-host/docker-compose.yml'
$synapse = Read-RequiredFile 'deploy/self-host/synapse/closed-private.yaml'
$caddy = Read-RequiredFile 'deploy/self-host/Caddyfile'
$exampleEnvironment = Read-RequiredFile 'deploy/self-host/.env.example'
$deploymentGuide = Read-RequiredFile 'deploy/self-host/README.md'
$threatModel = Read-RequiredFile 'docs/security-threat-model.md'
$operations = Read-RequiredFile 'docs/security-operations.md'
$bootstrap = Read-RequiredFile 'scripts/bootstrap-self-host.ps1'

# Compose boundary checks.
Require-Match $compose '(?m)^\s*postgres:\s*$' 'Compose must define PostgreSQL.'
Require-Match $compose '(?m)^\s*synapse:\s*$' 'Compose must define Synapse.'
Require-Match $compose '(?m)^\s*caddy:\s*$' 'Compose must define the TLS reverse proxy.'
Require-Match $compose '(?ms)^\s*database:\s*\r?\n\s+internal:\s*true\s*$' 'The database network must be internal.'
Require-Match $compose 'POSTGRES_PASSWORD_FILE:\s*/run/secrets/postgres_password' 'PostgreSQL must read its password from a secret file.'
Require-Match $compose '(?ms)^secrets:\s*\r?\n\s+postgres_password:' 'Compose must declare the PostgreSQL secret.'
Require-Match $compose '(?m)^\s{2}synapse_database:\s*$' 'Compose must declare the Synapse database configuration secret.'
Require-Match $compose 'file:\s*\./runtime/secrets/synapse_database\.yaml' 'The Synapse database secret must come from the gitignored runtime path.'
Require-Match $compose '--config-path=/run/secrets/synapse_database\.yaml' 'Synapse must load the database secret as the final configuration layer.'
Require-Match $compose '(?m)^\s+-\s+source:\s*synapse_database\s*$' 'Synapse must mount its database configuration through a Compose secret.'
Require-Match $compose 'closed-private\.yaml:.+:ro' 'The closed-private Synapse override must be mounted read-only.'
Require-MinimumMatches $compose '(?m)^\s+read_only:\s*true\s*$' 3 'Every service must use a read-only root filesystem.'
Require-MinimumMatches $compose '(?m)^\s+-\s+no-new-privileges:true\s*$' 3 'Every service must set no-new-privileges.'
Require-MinimumMatches $compose '(?m)^\s+healthcheck:\s*$' 3 'Every service must define a healthcheck.'
Require-MinimumMatches $compose '(?m)^\s+cap_drop:\s*$' 3 'Every service must drop capabilities.'
Forbid-Match $compose '(?im)^\s*image:\s*.*:latest(?:\s|$)' 'Moving latest image tags are forbidden.'
Forbid-Match $compose '(?m)^\s*-\s*["'']?(?:0\.0\.0\.0:)?(?:8008|8448):' 'Synapse/federation ports must not be published to the host.'

# Closed homeserver invariants.
Require-Match $synapse '(?m)^federation_domain_whitelist:\s*\[\]\s*$' 'Federation allowlist must be explicitly empty.'
Forbid-Match $synapse '(?m)^\s*-\s+federation\s*$' 'The default listener must not expose the federation resource.'
Require-Match $synapse '(?m)^enable_registration:\s*false\s*$' 'Public registration must be disabled.'
Require-Match $synapse '(?m)^allow_guest_access:\s*false\s*$' 'Guest access must be disabled.'
Require-Match $synapse '(?m)^encryption_enabled_by_default_for_room_type:\s*all\s*$' 'All locally-created rooms must default to encryption.'
Require-Match $synapse '(?m)^enable_room_list_search:\s*false\s*$' 'Public room list search must be disabled.'
Require-Match $synapse '(?m)^push:\s*\r?\n(?:\s{2}#[^\r\n]*\r?\n)*\s{2}enabled:\s*false\s*$' 'Native Synapse push must remain disabled until an opaque wake adapter exists.'
Require-Match $synapse '(?m)^\s*include_content:\s*false\s*$' 'Push content must be disabled.'
Require-Match $synapse '(?m)^url_preview_enabled:\s*false\s*$' 'URL previews must remain disabled by default.'
Forbid-Match $synapse '(?im)^\s*(?:password|secret|private_key)\s*:\s*[^#\s]' 'Tracked Synapse override must not contain literal secret material.'

# Edge allowlist checks.
Require-Match $caddy '(?m)^\s*admin off\s*$' 'The Caddy admin endpoint must be disabled.'
Require-Match $caddy 'Strict-Transport-Security' 'HSTS must be configured.'
Require-Match $caddy '@matrix_client path\s+/_matrix/client/\*\s+/_matrix/media/\*\s+/_synapse/client/\*' 'Caddy must use the reviewed Matrix client path allowlist.'
Forbid-Match $caddy '(?m)^\s*encode\s+' 'Dynamic Matrix responses must not be compressed at the edge.'
Forbid-Match $caddy '/_matrix/federation' 'Caddy must not route the federation API.'
Forbid-Match $caddy '/_synapse/admin' 'Caddy must not route the Synapse admin API.'

# Documentation and safe example checks.
Require-Match $exampleEnvironment 'REPLACE_WITH_VERIFIED_DIGEST' '.env.example must require image digest verification.'
Forbid-Match $exampleEnvironment '(?im)^\s*(?:password|secret|token|private_key)\s*=' '.env.example must not invite secrets into environment files.'
Require-Match $deploymentGuide '아직 연결되지 않았|not yet connected' 'Deployment guide must state that the Flutter client is not integrated.'
Require-Match $threatModel 'metadata' 'Threat model must cover metadata exposure.'
Require-Match $operations 'APNs/FCM' 'Operations guide must cover opaque mobile push limitations.'
Require-Match $deploymentGuide '(?i)SQLite' 'Deployment guide must explicitly reject a SQLite production fallback.'
Require-Match $deploymentGuide '(?i)background notification|백그라운드 알림' 'Deployment guide must state the current background-notification limitation.'

# The clean repository has no runtime secrets, so also validate the bootstrap
# recipe that creates them. Runtime values are checked below when .env exists.
Require-Match $bootstrap "synapse_database\.yaml" 'Bootstrap must create the Synapse database configuration secret.'
Require-Match $bootstrap '(?m)^\s*name:\s*psycopg2\s*$' 'Bootstrap must configure Synapse to use psycopg2.'
Require-Match $bootstrap '(?m)^\s*host:\s*postgres\s*$' 'Bootstrap must point Synapse at the PostgreSQL service.'
Require-Match $bootstrap '(?m)^\s*dbname:\s*synapse\s*$' 'Bootstrap must configure the Synapse database name.'
Require-Match $bootstrap '(?m)^\s*cp_min:\s*5\s*$' 'Bootstrap must define the minimum PostgreSQL connection pool size.'
Require-Match $bootstrap '(?m)^\s*cp_max:\s*10\s*$' 'Bootstrap must define the maximum PostgreSQL connection pool size.'
Require-Match $bootstrap '-c /run/secrets/synapse_database\.yaml' 'Semantic validation must include the database secret configuration.'
Forbid-Match $bootstrap '(?im)\$env:POSTGRES_' 'Synapse generation must not use ignored POSTGRES_* environment variables.'

# Parse both YAML files with the workspace's pinned Dart yaml package when the
# local SDK is available. Regex checks above enforce policy; this catches YAML
# syntax and basic structure errors without starting a container.
$isWindowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
  [System.Runtime.InteropServices.OSPlatform]::Windows
)
$dartName = if ($isWindowsHost) { 'dart.bat' } else { 'dart' }
$repositoryDart = Join-Path $repositoryRoot ".tooling/flutter/bin/$dartName"
$dartPath = if (Test-Path -LiteralPath $repositoryDart -PathType Leaf) {
  (Get-Item -LiteralPath $repositoryDart -Force).FullName
} else {
  $dartCommand = Get-Command dart -ErrorAction SilentlyContinue
  if ($null -ne $dartCommand) { $dartCommand.Source }
}

if (-not [string]::IsNullOrWhiteSpace($dartPath)) {
  & $dartPath run (Join-Path $repositoryRoot 'scripts/validate_self_host_yaml.dart')
  if ($LASTEXITCODE -ne 0) {
    $failures.Add('Dart YAML syntax/structure validation failed.')
  }
} else {
  $warnings.Add('Dart was not found; YAML syntax parsing was skipped.')
}

# If the operator has prepared a real environment, ask Docker Compose itself to
# parse and normalize the file. This never starts or pulls a container.
$realEnvironment = Join-Path $deployRoot '.env'
$secretPath = Join-Path $deployRoot 'runtime/secrets/postgres_password.txt'
$synapseDatabaseSecretPath = Join-Path $deployRoot 'runtime/secrets/synapse_database.yaml'
$docker = Get-Command docker -ErrorAction SilentlyContinue
$hasRealEnvironment = Test-Path -LiteralPath $realEnvironment -PathType Leaf
$runtimeSecretsReady = $false

if ($hasRealEnvironment) {
  $realEnvironmentContent = Get-Content -LiteralPath $realEnvironment -Raw
  if ($realEnvironmentContent -match 'REPLACE_|:latest(?:\s|$)') {
    $failures.Add('deploy/self-host/.env still contains a placeholder or moving latest tag.')
  }

  if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) {
    $failures.Add('Prepared .env requires runtime/secrets/postgres_password.txt.')
  }
  if (-not (Test-Path -LiteralPath $synapseDatabaseSecretPath -PathType Leaf)) {
    $failures.Add('Prepared .env requires runtime/secrets/synapse_database.yaml; SQLite fallback is forbidden.')
  }

  if ((Test-Path -LiteralPath $secretPath -PathType Leaf) -and
      (Test-Path -LiteralPath $synapseDatabaseSecretPath -PathType Leaf)) {
    $databasePassword = (Get-Content -LiteralPath $secretPath -Raw).Trim()
    $databaseConfiguration = Get-Content -LiteralPath $synapseDatabaseSecretPath -Raw

    if ($databasePassword -notmatch '^[A-Za-z0-9_-]{43,}$') {
      $failures.Add('PostgreSQL password must contain at least 32 random bytes encoded as base64url.')
    }
    Require-Match $databaseConfiguration '(?m)^\s{2}name:\s*psycopg2\s*$' 'Runtime Synapse database config must use psycopg2.'
    Require-Match $databaseConfiguration '(?m)^\s{4}user:\s*synapse\s*$' 'Runtime Synapse database config must use the synapse role.'
    Require-Match $databaseConfiguration '(?m)^\s{4}dbname:\s*synapse\s*$' 'Runtime Synapse database config must use the synapse database.'
    Require-Match $databaseConfiguration '(?m)^\s{4}host:\s*postgres\s*$' 'Runtime Synapse database config must use the postgres service.'
    Require-Match $databaseConfiguration '(?m)^\s{4}port:\s*5432\s*$' 'Runtime Synapse database config must use PostgreSQL port 5432.'
    Require-Match $databaseConfiguration '(?m)^\s{4}cp_min:\s*5\s*$' 'Runtime Synapse database config must set cp_min.'
    Require-Match $databaseConfiguration '(?m)^\s{4}cp_max:\s*10\s*$' 'Runtime Synapse database config must set cp_max.'
    Forbid-Match $databaseConfiguration '(?im)^\s*name:\s*sqlite3\s*$' 'SQLite is forbidden for the production reference deployment.'

    $passwordMatch = [regex]::Match(
      $databaseConfiguration,
      '(?m)^\s{4}password:\s*"([A-Za-z0-9_-]{43,})"\s*$'
    )
    if (-not $passwordMatch.Success -or $passwordMatch.Groups[1].Value -cne $databasePassword) {
      $failures.Add('Synapse and PostgreSQL secret files must contain the same password.')
    }

    $runtimeSecretsReady = $true
    $databasePassword = $null
  }
}

if ($RequireDocker -and $null -eq $docker) {
  $failures.Add('Docker is required but was not found on PATH.')
} elseif ($null -ne $docker -and $hasRealEnvironment -and $runtimeSecretsReady) {
  & $docker.Source compose --project-directory $deployRoot --env-file $realEnvironment -f (Join-Path $deployRoot 'docker-compose.yml') config --quiet
  if ($LASTEXITCODE -ne 0) {
    $failures.Add('docker compose config validation failed.')
  }
} elseif ($null -eq $docker) {
  $warnings.Add('Docker was not found; static policy checks ran, Compose parser validation was skipped.')
} elseif (-not $hasRealEnvironment) {
  $warnings.Add('No deploy/self-host/.env exists; static checks ran, real-environment Compose validation was skipped.')
}

foreach ($warning in $warnings) {
  Write-Warning $warning
}

if ($failures.Count -gt 0) {
  foreach ($failure in $failures) {
    Write-Error $failure -ErrorAction Continue
  }
  throw "Self-host validation failed with $($failures.Count) error(s)."
}

Write-Host 'Self-host static security checks passed.' -ForegroundColor Green
