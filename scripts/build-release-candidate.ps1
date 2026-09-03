<#
.SYNOPSIS
Builds one non-published native release candidate after all source gates pass.

.DESCRIPTION
This wrapper never invents application identifiers, creates signing keys,
uploads artifacts, or publishes a release. It runs the full source validation
and platform-specific release preflight before invoking Flutter. The resulting
native output is only a candidate: a trusted platform builder must still verify
its signature, provenance, SBOM, installation, update, and rollback behavior.

.EXAMPLE
./scripts/build-release-candidate.ps1 -Product everyday_chat -Platform windows -BuildName 1.0.0 -BuildNumber 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('everyday_chat', 'secure_collab')]
    [string]$Product,

    [Parameter(Mandatory = $true)]
    [ValidateSet('android', 'windows', 'linux', 'ios', 'macos')]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$BuildName,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$BuildNumber,

    [switch]$Offline,

    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runRoot = $workspaceRoot
$isWindowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows
)
$isLinuxHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Linux
)
$isMacosHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX
)

if ($isWindowsHost) {
    $linkPath = Join-Path ([System.IO.Path]::GetTempPath()) 'chat_platform_checks_ascii'
    if (Test-Path -LiteralPath $linkPath) {
        $link = Get-Item -LiteralPath $linkPath -Force
        $linkTarget = [string] $link.Target
        if ($link.LinkType -ne 'Junction' -or
            -not [string]::Equals(
                [System.IO.Path]::GetFullPath($linkTarget).TrimEnd('\'),
                [System.IO.Path]::GetFullPath($workspaceRoot).TrimEnd('\'),
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Refusing to use unexpected path: $linkPath"
        }
    } else {
        New-Item -ItemType Junction -Path $linkPath -Target $workspaceRoot | Out-Null
    }
    $runRoot = $linkPath
}

$hostSupported = switch ($Platform) {
    'android' { $isWindowsHost -or $isLinuxHost -or $isMacosHost }
    'windows' { $isWindowsHost }
    'linux' { $isLinuxHost }
    'ios' { $isMacosHost }
    'macos' { $isMacosHost }
}
if (-not $hostSupported) {
    throw "$Platform release candidates cannot be built on this host OS."
}

# The command-line version is embedded into the native artifact by Flutter,
# while the SBOM is derived from pubspec.yaml. Refuse divergent inputs so a
# candidate can never be paired with metadata for a different app version.
$manifestPath = Join-Path $workspaceRoot "apps/$Product/pubspec.yaml"
$manifest = Get-Content -LiteralPath $manifestPath -Raw
$manifestVersionMatches = [regex]::Matches(
    $manifest,
    '(?m)^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$'
)
if ($manifestVersionMatches.Count -ne 1) {
    throw "The $Product manifest must contain exactly one numeric release version and positive build number."
}
$manifestBuildName = $manifestVersionMatches[0].Groups[1].Value
$manifestBuildNumber = [int64] $manifestVersionMatches[0].Groups[2].Value
if ($BuildName -cne $manifestBuildName -or [int64] $BuildNumber -ne $manifestBuildNumber) {
    throw "Requested version $BuildName+$BuildNumber does not match the reviewed $Product manifest version $manifestBuildName+$manifestBuildNumber."
}

$localFlutter = Join-Path $runRoot '.tooling/flutter/bin'
$flutterName = if ($isWindowsHost) { 'flutter.bat' } else { 'flutter' }
$flutter = Join-Path $localFlutter $flutterName
if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -eq $flutterCommand) {
        throw 'Flutter was not found in .tooling/flutter or PATH.'
    }
    $flutter = $flutterCommand.Source
}

$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_TOOL_DISABLE_ANALYTICS = '1'
$env:CI = 'true'

& (Join-Path $PSScriptRoot 'release-preflight.ps1') -Product $Product -Platform $Platform
if ($LASTEXITCODE -ne 0) {
    throw 'Release preflight failed; no release candidate was built.'
}

$checkArguments = @('-EnforceLockfile')
if ($Offline) {
    $checkArguments += '-Offline'
}
& (Join-Path $PSScriptRoot 'check.ps1') @checkArguments
if ($LASTEXITCODE -ne 0) {
    throw 'Source validation failed; no release candidate was built.'
}
& (Join-Path $PSScriptRoot 'generate-sbom.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'SBOM generation failed; no release candidate was built.'
}
$sbomPath = Join-Path $runRoot 'build/release/private-chat-platform.cdx.json'
if (-not (Test-Path -LiteralPath $sbomPath -PathType Leaf)) {
    throw 'SBOM generation reported success without producing its expected output.'
}

$buildTarget = switch ($Platform) {
    'android' { 'appbundle' }
    'windows' { 'windows' }
    'linux' { 'linux' }
    'ios' { 'ipa' }
    'macos' { 'macos' }
}
$appRoot = Join-Path $runRoot "apps/$Product"
$startedAt = [DateTime]::UtcNow
Push-Location -LiteralPath $appRoot
try {
    & $flutter build $buildTarget --release --build-name $BuildName --build-number $BuildNumber --no-pub
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter $Platform release-candidate build failed."
    }
} finally {
    Pop-Location
}

$searchRoot = Join-Path $appRoot 'build'
$artifactCandidates = switch ($Platform) {
    'android' {
        @(Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter 'app-release.aab')
    }
    'windows' {
        @(Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter "$Product.exe")
    }
    'linux' {
        @(Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter $Product)
    }
    'ios' {
        @(Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter '*.ipa')
    }
    'macos' {
        @(Get-ChildItem -LiteralPath $searchRoot -Recurse -Directory -Filter '*.app')
    }
}
$freshArtifacts = @(
    $artifactCandidates |
        Where-Object { $_.LastWriteTimeUtc -ge $startedAt.AddSeconds(-2) }
)
if ($freshArtifacts.Count -eq 0) {
    throw 'Flutter reported success, but no freshly built release candidate was found.'
}

$result = [pscustomobject]@{
    status = 'native_candidate_built_not_published'
    product = $Product
    platform = $Platform
    build_name = $BuildName
    build_number = $BuildNumber
    artifacts = @($freshArtifacts | ForEach-Object { $_.FullName })
    sbom = $sbomPath
    remaining_gate = 'Verify platform signature, trusted identity, SBOM/provenance, install, update, rollback, and real-device behavior before packaging or publication.'
}

if ($Json) {
    $result | ConvertTo-Json -Depth 4
} else {
    Write-Host "Native $Product/$Platform candidate built; it was not packaged, uploaded, or published." -ForegroundColor Green
    foreach ($artifact in $result.artifacts) {
        Write-Host "CANDIDATE $artifact"
    }
    Write-Warning $result.remaining_gate
}
