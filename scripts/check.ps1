[CmdletBinding()]
param(
    [switch]$Offline,
    [switch]$EnforceLockfile
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$runRoot = $workspaceRoot

if ($isWindowsHost) {
    $linkPath = Join-Path ([System.IO.Path]::GetTempPath()) 'chat_platform_checks_ascii'

    if (Test-Path -LiteralPath $linkPath) {
        $link = Get-Item -LiteralPath $linkPath -Force
        $linkTarget = [string]$link.Target
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

function Resolve-ToolExecutable {
    param(
        [Parameter(Mandatory = $true)] [string] $LocalRelativePath,
        [Parameter(Mandatory = $true)] [string] $CommandName
    )

    $localExecutable = Join-Path $runRoot $LocalRelativePath
    if (Test-Path -LiteralPath $localExecutable) {
        return $localExecutable
    }

    $pathCommand = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -ne $pathCommand) {
        return $pathCommand.Source
    }

    throw "$CommandName was not found in .tooling/flutter or PATH. Follow README setup first."
}

$flutterExecutable = if ($isWindowsHost) { 'flutter.bat' } else { 'flutter' }
$dartExecutable = if ($isWindowsHost) { 'dart.bat' } else { 'dart' }
$flutter = Resolve-ToolExecutable -LocalRelativePath ".tooling/flutter/bin/$flutterExecutable" -CommandName 'flutter'
$dart = Resolve-ToolExecutable -LocalRelativePath ".tooling/flutter/bin/$dartExecutable" -CommandName 'dart'

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)] [string] $Executable,
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [Parameter(Mandatory = $true)] [string] $WorkingDirectory
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $Executable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $Executable $Arguments"
        }
    } finally {
        Pop-Location
    }
}

$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_TOOL_DISABLE_ANALYTICS = '1'

& (Join-Path $PSScriptRoot 'validate-contract.ps1')
& (Join-Path $PSScriptRoot 'validate-product-boundaries.ps1')
& (Join-Path $PSScriptRoot 'validate-localizations.ps1')
& (Join-Path $PSScriptRoot 'validate-ci.ps1')
& (Join-Path $PSScriptRoot 'validate-crypto-dependencies.ps1') -SelfTest
& (Join-Path $PSScriptRoot 'release-preflight.ps1') -SelfTest

$pubGetArguments = @('pub', 'get')
if ($Offline) {
    $pubGetArguments += '--offline'
}
if ($EnforceLockfile) {
    $pubGetArguments += '--enforce-lockfile'
}
# Dependency resolution is a source check. Using the Flutter SDK's Dart
# wrapper avoids creating native plugin symlinks, so widget tests do not
# require Windows Developer Mode merely to validate a locked workspace.
Invoke-Checked -Executable $dart -Arguments $pubGetArguments -WorkingDirectory $runRoot

# On Windows, a failed shader compile from the original non-ASCII workspace
# path can leave an apparently current but incomplete unit-test asset bundle.
# Invalidate only generated test assets, preserving plugin metadata so source
# validation does not require Developer Mode merely to recreate symlinks.
if ($isWindowsHost) {
    foreach ($appModule in @('apps/everyday_chat', 'apps/secure_collab')) {
        $unitTestAssets = Join-Path $runRoot "$appModule/build/unit_test_assets"
        if (Test-Path -LiteralPath $unitTestAssets) {
            $resolvedAssets = (Resolve-Path -LiteralPath $unitTestAssets).Path
            $resolvedAppRoot = (Resolve-Path -LiteralPath (Join-Path $runRoot $appModule)).Path
            if (-not $resolvedAssets.StartsWith(
                    $resolvedAppRoot.TrimEnd('\') + '\build\',
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                throw "Refusing to remove unexpected generated test assets: $resolvedAssets"
            }
            Remove-Item -LiteralPath $resolvedAssets -Recurse -Force
        }
    }
}
& (Join-Path $PSScriptRoot 'validate-self-host.ps1')
Invoke-Checked -Executable $dart -Arguments @(
    'format',
    '--output=none',
    '--set-exit-if-changed',
    'apps',
    'packages',
    'tool',
    'scripts/validate_self_host_yaml.dart'
) -WorkingDirectory $runRoot

Invoke-Checked -Executable $dart -Arguments @(
    'analyze',
    'tool',
    'scripts/validate_self_host_yaml.dart'
) -WorkingDirectory $runRoot

Invoke-Checked -Executable $dart -Arguments @(
    'run',
    'tool/validate_openapi.dart',
    'contracts/chat-api.openapi.yaml'
) -WorkingDirectory $runRoot
Invoke-Checked -Executable $dart -Arguments @(
    'run',
    'tool/validate_ci_workflow.dart',
    '.github/workflows/source-validation.yml',
    '.github/workflows/release-gate.yml',
    '.github/dependabot.yml'
) -WorkingDirectory $runRoot
Invoke-Checked -Executable $dart -Arguments @(
    'run',
    'tool/generate_sbom.dart',
    '--check'
) -WorkingDirectory $runRoot

$modules = @(
    'apps/everyday_chat',
    'apps/secure_collab',
    'packages/chat_core',
    'packages/chat_media',
    'packages/chat_media_crypto',
    'packages/chat_media_picker',
    'packages/chat_sync',
    'packages/chat_ui',
    'packages/homeserver_client',
    'packages/homeserver_runtime',
    'packages/key_transparency'
)

foreach ($module in $modules) {
    Invoke-Checked -Executable $dart -Arguments @('analyze', '.') -WorkingDirectory (Join-Path $runRoot $module)
}

Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/chat_core')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/chat_media')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/chat_media_crypto')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/key_transparency')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/chat_media_picker')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/chat_sync')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/chat_ui')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/homeserver_client')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'packages/homeserver_runtime')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'apps/everyday_chat')
Invoke-Checked -Executable $flutter -Arguments @('test', '--no-pub') -WorkingDirectory (Join-Path $runRoot 'apps/secure_collab')

Write-Host 'Contract, static-analysis, and automated tests passed. Native release artifacts were not built.' -ForegroundColor Green
