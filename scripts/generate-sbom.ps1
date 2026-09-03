[CmdletBinding()]
param(
    [string] $Output = 'build/release/private-chat-platform.cdx.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$dartName = if ($isWindowsHost) { 'dart.bat' } else { 'dart' }
$localDart = Join-Path $workspaceRoot ".tooling/flutter/bin/$dartName"
$dart = if (Test-Path -LiteralPath $localDart) {
    $localDart
} else {
    $command = Get-Command dart -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'Dart was not found in .tooling/flutter or PATH.'
    }
    $command.Source
}

$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_TOOL_DISABLE_ANALYTICS = '1'

Push-Location -LiteralPath $workspaceRoot
try {
    & $dart run tool/generate_sbom.dart --output $Output
    if ($LASTEXITCODE -ne 0) {
        throw "SBOM generation failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
