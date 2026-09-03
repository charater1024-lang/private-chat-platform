[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$deployRoot = Join-Path $repositoryRoot 'deploy/self-host'
$environmentPath = Join-Path $deployRoot '.env'
$secretDirectory = Join-Path $deployRoot 'runtime/secrets'
$databaseSecretPath = Join-Path $secretDirectory 'postgres_password.txt'
$synapseDatabaseSecretPath = Join-Path $secretDirectory 'synapse_database.yaml'
$composePath = Join-Path $deployRoot 'docker-compose.yml'

if (-not (Test-Path -LiteralPath $environmentPath -PathType Leaf)) {
  throw 'Copy deploy/self-host/.env.example to deploy/self-host/.env and review it first.'
}

$settings = @{}
foreach ($line in Get-Content -LiteralPath $environmentPath) {
  $trimmed = $line.Trim()
  if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
    continue
  }

  $separator = $trimmed.IndexOf('=')
  if ($separator -lt 1) {
    throw "Invalid .env line: $line"
  }

  $name = $trimmed.Substring(0, $separator).Trim()
  $value = $trimmed.Substring($separator + 1).Trim().Trim('"').Trim("'")
  $settings[$name] = $value
}

foreach ($required in @('MATRIX_SERVER_NAME', 'MATRIX_PUBLIC_HOST', 'CADDY_ACME_EMAIL', 'SYNAPSE_IMAGE', 'POSTGRES_IMAGE', 'CADDY_IMAGE')) {
  if (-not $settings.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($settings[$required])) {
    throw "Missing required .env setting: $required"
  }
}

if (($settings.Values -join "`n") -match 'REPLACE_|:latest(?:\s|$)') {
  throw '.env still contains a placeholder or moving latest image tag.'
}

if ($settings['MATRIX_SERVER_NAME'] -ne $settings['MATRIX_PUBLIC_HOST']) {
  throw 'The reference profile requires MATRIX_SERVER_NAME and MATRIX_PUBLIC_HOST to match.'
}

if ($settings['MATRIX_SERVER_NAME'] -notmatch '^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$') {
  throw 'MATRIX_SERVER_NAME must be a lowercase DNS name. Localhost and IP literals are not accepted.'
}

$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($null -eq $docker) {
  throw 'Docker Engine with Compose v2 was not found on PATH.'
}

New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath $databaseSecretPath -PathType Leaf)) {
  $randomBytes = New-Object byte[] 48
  $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $generator.GetBytes($randomBytes)
  } finally {
    $generator.Dispose()
  }

  $databasePassword = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  [System.IO.File]::WriteAllText(
    $databaseSecretPath,
    $databasePassword,
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Host 'Generated runtime/secrets/postgres_password.txt without printing its value.'
} else {
  $databasePassword = (Get-Content -LiteralPath $databaseSecretPath -Raw).Trim()
  if ($databasePassword -notmatch '^[A-Za-z0-9_-]{43,}$') {
    throw 'Existing PostgreSQL password must contain at least 32 random bytes encoded as base64url.'
  }
}

$expectedSynapseDatabaseConfiguration = @"
database:
  name: psycopg2
  txn_limit: 10000
  args:
    user: synapse
    password: "$databasePassword"
    dbname: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10
"@

if (-not (Test-Path -LiteralPath $synapseDatabaseSecretPath -PathType Leaf)) {
  [System.IO.File]::WriteAllText(
    $synapseDatabaseSecretPath,
    "$expectedSynapseDatabaseConfiguration`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Host 'Generated runtime/secrets/synapse_database.yaml without printing its value.'
} else {
  $actualDatabaseConfiguration = Get-Content -LiteralPath $synapseDatabaseSecretPath -Raw
  $normalizedActualConfiguration = $actualDatabaseConfiguration.Replace("`r`n", "`n").TrimEnd()
  $normalizedExpectedConfiguration = $expectedSynapseDatabaseConfiguration.Replace("`r`n", "`n").TrimEnd()
  if (-not [string]::Equals(
      $normalizedActualConfiguration,
      $normalizedExpectedConfiguration,
      [System.StringComparison]::Ordinal
    )) {
    throw 'Existing synapse_database.yaml is non-canonical or does not match postgres_password.txt. SQLite and partial database overrides are forbidden; rotate both secrets together.'
  }
}

$isUnixPlatform = $false
$isLinuxVariable = Get-Variable -Name IsLinux -ErrorAction SilentlyContinue
$isMacVariable = Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue
if (($null -ne $isLinuxVariable -and [bool]$isLinuxVariable.Value) -or
    ($null -ne $isMacVariable -and [bool]$isMacVariable.Value)) {
  $isUnixPlatform = $true
}

if ($isUnixPlatform) {
  & chmod 700 $secretDirectory
  & chmod 600 $databaseSecretPath $synapseDatabaseSecretPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to apply restrictive permissions to the runtime secrets.'
  }
} else {
  Write-Warning 'Verify that only the intended Windows account can read deploy/self-host/runtime/secrets.'
}

& (Join-Path $PSScriptRoot 'validate-self-host.ps1') -RequireDocker

# The maintained Synapse image generator only consumes the server name and
# report-stats choice. Database settings are loaded later from a Docker secret;
# POSTGRES_* variables would be ignored and could silently leave SQLite enabled.
$previousServerName = [Environment]::GetEnvironmentVariable('SYNAPSE_SERVER_NAME', 'Process')
$previousReportStats = [Environment]::GetEnvironmentVariable('SYNAPSE_REPORT_STATS', 'Process')

try {
  $env:SYNAPSE_SERVER_NAME = $settings['MATRIX_SERVER_NAME']
  $env:SYNAPSE_REPORT_STATS = 'no'

  & $docker.Source compose --project-directory $deployRoot --env-file $environmentPath -f $composePath run --rm --no-deps `
    -e SYNAPSE_SERVER_NAME -e SYNAPSE_REPORT_STATS synapse generate
  if ($LASTEXITCODE -ne 0) {
    throw 'Synapse configuration generation failed. Existing configuration is never overwritten automatically.'
  }
} finally {
  [Environment]::SetEnvironmentVariable('SYNAPSE_SERVER_NAME', $previousServerName, 'Process')
  [Environment]::SetEnvironmentVariable('SYNAPSE_REPORT_STATS', $previousReportStats, 'Process')
}

& $docker.Source compose --project-directory $deployRoot --env-file $environmentPath -f $composePath run --rm --no-deps `
  --entrypoint python synapse -m synapse.config -c /data/homeserver.yaml `
  -c /etc/synapse/closed-private.yaml -c /run/secrets/synapse_database.yaml
if ($LASTEXITCODE -ne 0) {
  throw 'Synapse semantic configuration validation failed.'
}

$databasePassword = $null

Write-Host 'Bootstrap and Synapse configuration validation completed. Review the generated configuration before docker compose up -d.' -ForegroundColor Green
