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
$backendProfile = Read-RequiredFile 'deploy/self-host/backend-profile.yaml'
$launcherContract = Read-RequiredFile 'deploy/self-host/CUSTOM_BACKEND_LAUNCH_CONTRACT.md'
$synapse = Read-RequiredFile 'deploy/self-host/synapse/closed-private.yaml'
$synapseLog = Read-RequiredFile 'deploy/self-host/synapse/log.config'
$synapseScrubber = Read-RequiredFile 'deploy/self-host/synapse/scrub_generated_config.py'
$caddy = Read-RequiredFile 'deploy/self-host/Caddyfile'
$exampleEnvironment = Read-RequiredFile 'deploy/self-host/.env.example'
$deploymentGuide = Read-RequiredFile 'deploy/self-host/README.md'
$threatModel = Read-RequiredFile 'docs/security-threat-model.md'
$operations = Read-RequiredFile 'docs/security-operations.md'
$bootstrap = Read-RequiredFile 'scripts/bootstrap-self-host.ps1'
$runtimeConfig = Read-RequiredFile 'packages/homeserver_runtime/lib/src/runtime_config.dart'
$runtimeServer = Read-RequiredFile 'packages/homeserver_runtime/lib/src/runtime_server.dart'
$runtimeSnapshotStore = Read-RequiredFile 'packages/homeserver_runtime/lib/src/private_atomic_snapshot_store.dart'
$securePersistenceBoundary = Read-RequiredFile 'packages/secure_persistence/lib/src/security_boundaries.dart'
$securePersistenceGuide = Read-RequiredFile 'packages/secure_persistence/README.md'

# Compose boundary checks.
Require-Match $compose '(?m)^\s*postgres:\s*$' 'Compose must define PostgreSQL.'
Require-Match $compose '(?m)^\s*synapse:\s*$' 'Compose must define Synapse.'
Require-Match $compose '(?m)^\s*caddy:\s*$' 'Compose must define the TLS reverse proxy.'
Forbid-Match $compose '(?m)^\s{2}app_homeserver:\s*$' 'The custom app homeserver must not be composed before its secure launcher exists.'
Require-Match $compose '(?ms)^\s*proxy:\s*\r?\n\s+internal:\s*true\s*$' 'The reverse-proxy network must be internal.'
Require-Match $compose '(?ms)^\s*database:\s*\r?\n\s+internal:\s*true\s*$' 'The database network must be internal.'
Require-Match $compose 'POSTGRES_PASSWORD_FILE:\s*/run/secrets/postgres_password' 'PostgreSQL must read its password from a secret file.'
Require-Match $compose '(?ms)^secrets:\s*\r?\n\s+postgres_password:' 'Compose must declare the PostgreSQL secret.'
Require-Match $compose '(?m)^\s{2}synapse_database:\s*$' 'Compose must declare the Synapse database configuration secret.'
Require-Match $compose 'file:\s*\./runtime/secrets/synapse_database\.yaml' 'The Synapse database secret must come from the gitignored runtime path.'
Require-Match $compose '--config-path=/run/secrets/synapse_database\.yaml' 'Synapse must load the database secret as the final configuration layer.'
Require-Match $compose '(?m)^\s+-\s+source:\s*synapse_database\s*$' 'Synapse must mount its database configuration through a Compose secret.'
Require-Match $compose 'closed-private\.yaml:.+:ro' 'The closed-private Synapse override must be mounted read-only.'
Require-Match $compose 'synapse/log\.config:/etc/synapse/log\.config:ro' 'The privacy-preserving Synapse log configuration must be mounted read-only.'
Require-Match $compose 'scrub_generated_config\.py:/etc/synapse/scrub_generated_config\.py:ro' 'The registration-secret scrubber must be mounted read-only.'
Require-Match $compose '\$\{CADDY_BIND_IP:-127\.0\.0\.1\}:80:80' 'HTTP must bind to the explicit CADDY_BIND_IP with a loopback default.'
Require-Match $compose '\$\{CADDY_BIND_IP:-127\.0\.0\.1\}:443:443' 'HTTPS must bind to the explicit CADDY_BIND_IP with a loopback default.'
Require-MinimumMatches $compose '(?m)^\s+read_only:\s*true\s*$' 3 'Every service must use a read-only root filesystem.'
Require-MinimumMatches $compose '(?m)^\s+-\s+no-new-privileges:true\s*$' 3 'Every service must set no-new-privileges.'
Require-MinimumMatches $compose '(?m)^\s+healthcheck:\s*$' 3 'Every service must define a healthcheck.'
Require-MinimumMatches $compose '(?m)^\s+cap_drop:\s*$' 3 'Every service must drop capabilities.'
Forbid-Match $compose '(?im)^\s*image:\s*.*:latest(?:\s|$)' 'Moving latest image tags are forbidden.'
Forbid-Match $compose '(?m)^\s*-\s*["'']?(?:0\.0\.0\.0:)?(?:8008|8448):' 'Synapse/federation ports must not be published to the host.'
Forbid-Match $compose '(?m)^\s*-\s*["'']?(?:80|443):(?:80|443)["'']?\s*$' 'Caddy ports must not use an implicit all-interface bind.'

# Closed homeserver invariants.
Require-Match $synapse '(?m)^federation_domain_whitelist:\s*\[\]\s*$' 'Federation allowlist must be explicitly empty.'
Forbid-Match $synapse '(?m)^\s*-\s+federation\s*$' 'The default listener must not expose the federation resource.'
Require-Match $synapse '(?m)^enable_registration:\s*false\s*$' 'Public registration must be disabled.'
Require-Match $synapse '(?m)^registration_shared_secret:\s*null\s*$' 'Shared-secret registration must be explicitly disabled.'
Require-Match $synapse '(?m)^allow_guest_access:\s*false\s*$' 'Guest access must be disabled.'
Require-Match $synapse '(?m)^encryption_enabled_by_default_for_room_type:\s*all\s*$' 'All locally-created rooms must default to encryption.'
Require-Match $synapse '(?m)^enable_authenticated_media:\s*true\s*$' 'Authenticated media must be explicitly enabled.'
Require-Match $synapse '(?m)^enable_room_list_search:\s*false\s*$' 'Public room list search must be disabled.'
Require-Match $synapse '(?m)^push:\s*\r?\n(?:\s{2}#[^\r\n]*\r?\n)*\s{2}enabled:\s*false\s*$' 'Native Synapse push must remain disabled until an opaque wake adapter exists.'
Require-Match $synapse '(?m)^\s*include_content:\s*false\s*$' 'Push content must be disabled.'
Require-Match $synapse '(?m)^url_preview_enabled:\s*false\s*$' 'URL previews must remain disabled by default.'
Require-Match $synapse '(?m)^log_config:\s*/etc/synapse/log\.config\s*$' 'Synapse must use the reviewed privacy log configuration.'
Require-Match $synapse '(?m)^rc_message:\s*$' 'Message rate limits must be explicit.'
Require-Match $synapse '(?m)^rc_login:\s*$' 'Login rate limits must be explicit.'
Require-Match $synapse '(?m)^rc_invites:\s*$' 'Invite rate limits must be explicit.'
Require-Match $synapse '(?m)^rc_media_create:\s*$' 'Media creation rate limits must be explicit.'
Require-Match $synapse '(?m)^max_upload_size:\s*256M\s*$' 'Uploads must use the reviewed 256 MiB ceiling.'
Forbid-Match $synapse '(?im)^\s*(?:password|secret|private_key)\s*:\s*[^#\s]' 'Tracked Synapse override must not contain literal secret material.'

# Privacy logging and bootstrap credential lifecycle.
Require-Match $synapseLog '(?ms)^\s*synapse\.access\.http:\s*.*?\s+level:\s*WARNING\s*$' 'Successful Synapse access metadata must not be logged.'
Require-Match $synapseLog '(?m)^\s*level:\s*WARNING\s*$' 'Synapse logging must default to warning or higher.'
Require-Match $synapseScrubber 'registration_shared_secret' 'Bootstrap must scrub generated registration secrets.'
Require-Match $synapseScrubber 'os\.replace' 'Registration-secret scrubbing must use atomic replacement.'

# Edge allowlist checks.
Require-Match $caddy '(?m)^\s*admin off\s*$' 'The Caddy admin endpoint must be disabled.'
Require-Match $caddy 'Strict-Transport-Security' 'HSTS must be configured.'
Require-Match $caddy '@matrix_client path\s+/_matrix/client/\*' 'Caddy must use the reviewed authenticated Matrix client path allowlist.'
Require-Match $caddy '(?ms)@unsupported_custom_api\s+path\s+/v1/\*\s*.*?handle\s+@unsupported_custom_api\s*\{\s*respond\s+503\s*\}' 'The Matrix reference must fail closed with 503 for the custom /v1 API.'
Require-Match $caddy '(?ms)request_body\s+@matrix_client\s*\{\s*max_size\s+256MB\s*\}' 'Caddy must reject oversized client request bodies.'
Require-Match $caddy 'max_header_size\s+32KiB' 'Caddy must cap request headers.'
Require-Match $caddy '(?m)^\s*read_header\s+10s\s*$' 'Caddy must bound header read time.'
Require-Match $caddy '(?m)^\s*read_body_idle\s+30s\s*$' 'Caddy must bound stalled request bodies.'
Forbid-Match $caddy '(?m)^\s*encode\s+' 'Dynamic Matrix responses must not be compressed at the edge.'
Forbid-Match $caddy '(?m)^\s*log(?:\s|\{)' 'Caddy access logs must remain disabled unless a separately reviewed redaction policy exists.'
Forbid-Match $caddy '/_matrix/media' 'Legacy unauthenticated Matrix media routes must not be public.'
Forbid-Match $caddy '/_synapse/client' 'Broad Synapse helper routes must not be public.'
Forbid-Match $caddy '/_matrix/federation' 'Caddy must not route the federation API.'
Forbid-Match $caddy '/_synapse/admin' 'Caddy must not route the Synapse admin API.'
Forbid-Match $caddy '(?i)reverse_proxy\s+app_homeserver' 'The custom /v1 daemon must not be routed before the secure-launch contract is satisfied.'

# Machine-readable backend compatibility and future launcher contract.
Require-Match $backendProfile '(?m)^profile_version:\s*1\s*$' 'Backend profile version must be explicit.'
Require-Match $backendProfile '(?m)^protocol:\s*matrix-reference\s*$' 'The current deployment must identify itself as Matrix-only.'
Require-Match $backendProfile '(?m)^application_backend:\s*false\s*$' 'The Matrix stack must not claim to be the application backend.'
Require-Match $backendProfile '(?m)^custom_v1_routed:\s*false\s*$' 'The Matrix stack must not claim custom /v1 routing.'
Require-Match $backendProfile '(?m)^release_eligible:\s*false\s*$' 'The current backend profile must remain release-blocked.'
Require-Match $backendProfile '(?m)^custom_v1_failure_status:\s*503\s*$' 'The custom API failure status must be fixed at 503.'
Require-Match $launcherContract 'HomeserverListenerPolicy\.privateReverseProxy' 'Launcher contract must require the private reverse-proxy listener policy.'
Require-Match $launcherContract 'SecureRecordKeyProvider' 'Launcher contract must require an external protected key provider.'
Require-Match $launcherContract 'SecureGenerationAnchor' 'Launcher contract must require an external rollback anchor.'
Require-Match $launcherContract '(?is)environment variables.*forbidden' 'Launcher contract must forbid environment-variable key fallback.'
Require-Match $launcherContract 'X-Private-Homeserver-Proxy-Authorization' 'Launcher contract must preserve the internal proxy credential boundary.'
Require-Match $launcherContract 'X-Forwarded-Proto:\s*https' 'Launcher contract must preserve HTTPS forwarding evidence.'

# The future custom daemon may only use the reviewed runtime trust boundaries.
Require-Match $runtimeConfig 'HomeserverListenerPolicy\.privateReverseProxy' 'Runtime must retain the explicit private reverse-proxy policy.'
Require-Match $runtimeConfig '!_isPrivateUnicast\(bindAddress\)\s*\|\|\s*bindAddress\.isLoopback' 'Networked runtime binds must reject loopback, wildcard, and public addresses.'
Require-Match $runtimeConfig '_trustedProxyAddresses\.contains\(address\.address\.toLowerCase\(\)\)' 'Runtime policy must retain exact direct-peer authorization.'
Require-Match $runtimeConfig 'normalized\.contains\(''\*''\)' 'Runtime Host policy must reject wildcard values.'
Require-Match $runtimeConfig 'x-private-homeserver-proxy-authorization' 'Runtime must require the internal proxy authorization header.'
Require-Match $runtimeConfig 'forwardedProto\?\.length\s*==\s*1' 'Runtime must reject duplicated forwarded-proto evidence.'
Require-Match $runtimeConfig 'forwardedProto!\.single\.toLowerCase\(\)\s*==\s*''https''' 'Runtime must require HTTPS forwarding evidence.'
Require-Match $runtimeServer '!listener\.acceptsDirectPeer\(connection\.remoteAddress\)' 'Runtime request admission must enforce the peer policy.'
Require-Match $runtimeServer '!listener\.acceptsHost\(request\.headers\.host,\s*_server\.port\)' 'Runtime request admission must enforce the exact Host policy.'
Require-Match $runtimeServer '!listener\.acceptsProxyHeaders\(request\.headers\)' 'Runtime request admission must enforce proxy headers.'
Require-Match $runtimeServer "_matches\(segments, const \['healthz'\]\)" 'Runtime must retain the bounded health endpoint used by a future proxy.'
Require-Match $runtimeSnapshotStore 'required SecureGenerationAnchor generationAnchor' 'Persistent runtime snapshots must require an external generation anchor.'
Require-Match $securePersistenceBoundary 'abstract interface class SecureRecordKeyProvider' 'Secure persistence must require an external key-provider boundary.'
Require-Match $securePersistenceGuide '(?is)does \*\*not\*\* provide password, environment-variable,\s*or adjacent key-file fallbacks' 'Secure persistence must continue to forbid insecure key fallbacks.'

# Documentation and safe example checks.
Require-Match $exampleEnvironment 'REPLACE_WITH_VERIFIED_DIGEST' '.env.example must require image digest verification.'
Require-Match $exampleEnvironment '(?m)^CADDY_BIND_IP=127\.0\.0\.1\s*$' '.env.example must bind Caddy to loopback by default.'
Require-Match $exampleEnvironment '(?m)^PUBLIC_EXPOSURE_ACK=NO\s*$' '.env.example must not acknowledge public exposure by default.'
Forbid-Match $exampleEnvironment '(?im)^\s*(?:password|secret|token|private_key)\s*=' '.env.example must not invite secrets into environment files.'
Require-Match $deploymentGuide '연결되지 않았|not connected' 'Deployment guide must state that the Flutter client is not integrated.'
Require-Match $deploymentGuide '(?s)custom `/v1`.*Matrix.*호환되지 않는다' 'Deployment guide must explicitly state the custom/Matrix protocol mismatch.'
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
Require-Match $bootstrap '@sha256:\[0-9a-fA-F\]\{64\}' 'Bootstrap must require full registry digests.'
Require-Match $bootstrap 'I_ACCEPT_PUBLIC_INTERNET_EXPOSURE' 'Bootstrap must require explicit acknowledgement for public binding.'
Require-Match $bootstrap 'scrub_generated_config\.py' 'Bootstrap must remove the generated registration secret.'
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

  $runtimeSettings = @{}
  foreach ($line in Get-Content -LiteralPath $realEnvironment) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) {
      $failures.Add("Invalid deploy/self-host/.env line: $line")
      continue
    }
    $runtimeSettings[$trimmed.Substring(0, $separator).Trim()] =
      $trimmed.Substring($separator + 1).Trim().Trim('"').Trim("'")
  }

  foreach ($imageSetting in @('SYNAPSE_IMAGE', 'POSTGRES_IMAGE', 'CADDY_IMAGE')) {
    if (-not $runtimeSettings.ContainsKey($imageSetting) -or
        $runtimeSettings[$imageSetting] -notmatch '^[^@\s]+:[^@\s]+@sha256:[0-9a-fA-F]{64}$' -or
        $runtimeSettings[$imageSetting] -match ':latest@') {
      $failures.Add("$imageSetting must contain an immutable tag and a full sha256 registry digest.")
    }
  }

  if (-not $runtimeSettings.ContainsKey('CADDY_BIND_IP')) {
    $failures.Add('CADDY_BIND_IP is required.')
  } else {
    $validatedBindAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($runtimeSettings['CADDY_BIND_IP'], [ref]$validatedBindAddress) -or
        $validatedBindAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
        $validatedBindAddress.ToString() -cne $runtimeSettings['CADDY_BIND_IP']) {
      $failures.Add('CADDY_BIND_IP must be one explicit IPv4 address.')
    } else {
      $validatedBindBytes = $validatedBindAddress.GetAddressBytes()
      $isPrivateBind = [System.Net.IPAddress]::IsLoopback($validatedBindAddress) -or
        $validatedBindBytes[0] -eq 10 -or
        ($validatedBindBytes[0] -eq 172 -and $validatedBindBytes[1] -ge 16 -and $validatedBindBytes[1] -le 31) -or
        ($validatedBindBytes[0] -eq 192 -and $validatedBindBytes[1] -eq 168)
      if (-not $isPrivateBind -and
          (-not $runtimeSettings.ContainsKey('PUBLIC_EXPOSURE_ACK') -or
           $runtimeSettings['PUBLIC_EXPOSURE_ACK'] -cne 'I_ACCEPT_PUBLIC_INTERNET_EXPOSURE')) {
        $failures.Add('A wildcard/public CADDY_BIND_IP requires explicit exposure acknowledgement.')
      }
    }
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
