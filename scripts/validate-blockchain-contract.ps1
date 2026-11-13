[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $CompilerPath
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$contractPath = Join-Path $workspaceRoot 'contracts/blockchain/KeyTransparencyAnchor.sol'
$compiler = (Resolve-Path -LiteralPath $CompilerPath).Path

if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw 'Missing contracts/blockchain/KeyTransparencyAnchor.sol.'
}
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Solidity compiler is not a file: $compiler"
}

$versionOutput = (& $compiler --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or
    $versionOutput -notmatch '(?m)^Version:\s*0\.8\.38\+commit\.1835d247\b') {
    throw "Expected official Solidity 0.8.38+commit.1835d247, received: $versionOutput"
}

$validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'chat-platform-solidity-' + [System.Guid]::NewGuid().ToString('N')
)
$outputRoot = Join-Path $validationRoot 'out'
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

try {
    & $compiler `
        --optimize `
        --optimize-runs 200 `
        --evm-version prague `
        --abi `
        --bin `
        --bin-runtime `
        --metadata `
        --output-dir $outputRoot `
        --overwrite `
        $contractPath
    if ($LASTEXITCODE -ne 0) {
        throw "Solidity compilation failed with exit code $LASTEXITCODE."
    }

    $abiFiles = @(Get-ChildItem -LiteralPath $outputRoot -Filter '*.abi' -File)
    $runtimeFiles = @(Get-ChildItem -LiteralPath $outputRoot -Filter '*.bin-runtime' -File)
    $creationFiles = @(Get-ChildItem -LiteralPath $outputRoot -Filter '*.bin' -File)
    $metadataFiles = @(Get-ChildItem -LiteralPath $outputRoot -Filter '*_meta.json' -File)
    if ($abiFiles.Count -ne 1 -or
        $runtimeFiles.Count -ne 1 -or
        $creationFiles.Count -ne 1 -or
        $metadataFiles.Count -ne 1) {
        throw 'Expected exactly one ABI, creation bytecode, runtime bytecode and metadata artifact.'
    }

    $abi = @(Get-Content -LiteralPath $abiFiles[0].FullName -Raw | ConvertFrom-Json)
    if (@($abi | Where-Object { $_.type -eq 'function' }).Count -ne 0) {
        throw 'The checkpoint contract ABI must not expose callable functions.'
    }
    if (@($abi | Where-Object { $_.type -eq 'receive' }).Count -ne 0) {
        throw 'The checkpoint contract ABI must not expose a receive handler.'
    }

    $fallback = @($abi | Where-Object { $_.type -eq 'fallback' })
    if ($fallback.Count -ne 1 -or $fallback[0].stateMutability -cne 'nonpayable') {
        throw 'The checkpoint contract must expose one nonpayable fallback.'
    }

    $events = @($abi | Where-Object { $_.type -eq 'event' })
    if ($events.Count -ne 1 -or
        $events[0].name -cne 'CheckpointAnchored' -or
        $events[0].anonymous -ne $true -or
        @($events[0].inputs).Count -ne 1 -or
        $events[0].inputs[0].type -cne 'bytes32' -or
        $events[0].inputs[0].indexed -ne $true) {
        throw 'The checkpoint event must remain one anonymous indexed bytes32 digest.'
    }

    $errors = @($abi | Where-Object { $_.type -eq 'error' })
    $errorNames = @($errors | ForEach-Object { [string]$_.name } | Sort-Object)
    if ($errorNames.Count -ne 2 -or
        $errorNames[0] -cne 'InvalidAnchorCalldata' -or
        $errorNames[1] -cne 'ZeroAnchorDigest') {
        throw 'The checkpoint contract error surface changed unexpectedly.'
    }
    if (@($errors | Where-Object { @($_.inputs).Count -ne 0 }).Count -ne 0) {
        throw 'Checkpoint contract errors must not carry user-controlled values.'
    }

    $runtimeBytecode = (Get-Content -LiteralPath $runtimeFiles[0].FullName -Raw).Trim()
    $creationBytecode = (Get-Content -LiteralPath $creationFiles[0].FullName -Raw).Trim()
    if ($runtimeBytecode -notmatch '^[0-9a-fA-F]+$' -or
        $creationBytecode -notmatch '^[0-9a-fA-F]+$') {
        throw 'Compiled contract bytecode is empty or malformed.'
    }

    $runtimeBytes = [byte[]]::new($runtimeBytecode.Length / 2)
    for ($index = 0; $index -lt $runtimeBytes.Length; $index++) {
        $runtimeBytes[$index] = [Convert]::ToByte($runtimeBytecode.Substring($index * 2, 2), 16)
    }
    $runtimeSha256 = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($runtimeBytes)
    ).ToLowerInvariant()
    Write-Host "Blockchain contract compiled and ABI policy passed. Runtime SHA-256: $runtimeSha256" -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $validationRoot) {
        $resolvedValidationRoot = (Resolve-Path -LiteralPath $validationRoot).Path
        $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
        if (-not $resolvedValidationRoot.StartsWith(
                $resolvedTempRoot + '\chat-platform-solidity-',
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Refusing to remove unexpected validation directory: $resolvedValidationRoot"
        }
        Remove-Item -LiteralPath $resolvedValidationRoot -Recurse -Force
    }
}
