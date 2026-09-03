[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Read-Arb {
    param([Parameter(Mandatory = $true)] [string] $Path)

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Localization validation failed: invalid ARB JSON at $Path. $($_.Exception.Message)"
    }
}

function Get-MessageKeys {
    param([Parameter(Mandatory = $true)] [object] $Arb)

    return @(
        $Arb.PSObject.Properties.Name |
            Where-Object { -not $_.StartsWith('@') } |
            Sort-Object
    )
}

function Get-Placeholders {
    param([Parameter(Mandatory = $true)] [string] $Message)

    return @(
        [regex]::Matches($Message, '\{([A-Za-z][A-Za-z0-9_]*)') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
    )
}

foreach ($app in @('everyday_chat', 'secure_collab')) {
    $l10nRoot = Join-Path $workspaceRoot "apps\$app\lib\l10n"
    $koPath = Join-Path $l10nRoot 'app_ko.arb'
    $enPath = Join-Path $l10nRoot 'app_en.arb'
    $ko = Read-Arb $koPath
    $en = Read-Arb $enPath

    if ($ko.'@@locale' -ne 'ko' -or $en.'@@locale' -ne 'en') {
        throw "Localization validation failed: $app must declare ko and en locales."
    }

    $koKeys = Get-MessageKeys $ko
    $enKeys = Get-MessageKeys $en
    $keyDifference = @(Compare-Object $koKeys $enKeys)
    if ($keyDifference.Count -ne 0) {
        $details = $keyDifference | ForEach-Object { "$($_.InputObject) $($_.SideIndicator)" }
        throw "Localization validation failed: $app key mismatch: $($details -join ', ')"
    }

    foreach ($key in $koKeys) {
        $koMessage = [string] $ko.$key
        $enMessage = [string] $en.$key
        if ([string]::IsNullOrWhiteSpace($koMessage) -or
            [string]::IsNullOrWhiteSpace($enMessage)) {
            throw "Localization validation failed: $app.$key contains an empty translation."
        }

        $koPlaceholders = Get-Placeholders $koMessage
        $enPlaceholders = Get-Placeholders $enMessage
        if (($koPlaceholders -join "`0") -ne ($enPlaceholders -join "`0")) {
            throw "Localization validation failed: $app.$key has different ko/en placeholders."
        }
    }

    $configurationPath = Join-Path $workspaceRoot "apps\$app\l10n.yaml"
    $configuration = Get-Content -LiteralPath $configurationPath -Raw
    if ($configuration -notmatch '(?m)^template-arb-file:\s*app_ko\.arb\s*$') {
        throw "Localization validation failed: $app must use Korean as the template locale."
    }
    if ($configuration -match '(?m)^synthetic-package:') {
        throw "Localization validation failed: $app uses removed synthetic-package configuration."
    }
    if ($configuration -notmatch '(?ms)^preferred-supported-locales:\s*\r?\n\s+- ko\s*\r?\n\s+- en\s*$') {
        throw "Localization validation failed: $app must prefer ko then en."
    }
}

Write-Host 'Korean/English localization parity passed.' -ForegroundColor Green
