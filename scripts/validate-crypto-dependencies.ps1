[CmdletBinding()]
param(
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:violations = [System.Collections.Generic.List[string]]::new()

function Get-RelativeWorkspacePath {
    param([Parameter(Mandatory = $true)] [string] $Path)

    $absolutePath = [System.IO.Path]::GetFullPath($Path)
    if ($absolutePath.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $absolutePath.Substring($workspaceRoot.Length).TrimStart('\', '/')
    }
    return $absolutePath
}

function Add-PolicyViolation {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    $label = Get-RelativeWorkspacePath -Path $Path
    $script:violations.Add("${label}: $Message")
}

function Get-ControlledManifestFiles {
    param([Parameter(Mandatory = $true)] [string[]] $Names)

    $wantedNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($name in $Names) {
        [void] $wantedNames.Add($name)
    }

    # Generated dependency trees and build outputs are deliberately excluded. The
    # validator examines every source-controlled manifest, including future vendor
    # directories, but must not treat Flutter's bundled SDK manifests as this
    # repository's dependency declarations.
    $excludedDirectories = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($name in @(
        '.git',
        '.dart_tool',
        '.tooling',
        '.symlinks',
        'build',
        'ephemeral',
        'node_modules',
        'Pods',
        'target'
    )) {
        [void] $excludedDirectories.Add($name)
    }

    $pending = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $pending.Push((Get-Item -LiteralPath $workspaceRoot))
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()

        foreach ($file in Get-ChildItem -LiteralPath $directory.FullName -Force -File) {
            if ($wantedNames.Contains($file.Name)) {
                $files.Add($file)
            }
        }

        foreach ($child in Get-ChildItem -LiteralPath $directory.FullName -Force -Directory) {
            if ($excludedDirectories.Contains($child.Name)) {
                continue
            }
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }
            $pending.Push($child)
        }
    }

    # Generated directories are skipped during the filesystem walk, but a
    # tracked manifest must never escape review merely because it was placed
    # under a directory named build/target/vendor. Merge Git's complete tracked
    # and non-ignored-untracked view back into the candidate set.
    $git = Get-Command git -ErrorAction SilentlyContinue
    $gitDirectory = Join-Path $workspaceRoot '.git'
    if ($null -ne $git -and (Test-Path -LiteralPath $gitDirectory)) {
        $repositoryPaths = @(
            & $git.Source -C $workspaceRoot -c core.quotePath=false `
                ls-files --cached --others --exclude-standard
        )
        if ($LASTEXITCODE -ne 0) {
            throw 'git ls-files failed while enumerating dependency manifests.'
        }
        foreach ($relativePath in $repositoryPaths) {
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                continue
            }
            $candidatePath = Join-Path $workspaceRoot $relativePath
            if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
                continue
            }
            # PowerShell marks Unix dotfiles as Hidden. Test-Path can see them,
            # while Get-Item without -Force may still fail on hosted Linux CI.
            $candidate = Get-Item -LiteralPath $candidatePath -Force
            if ($wantedNames.Contains($candidate.Name)) {
                $files.Add($candidate)
            }
        }
    }

    return @($files | Sort-Object -Property FullName -Unique)
}

function ConvertTo-NormalizedPackageName {
    param([Parameter(Mandatory = $true)] [string] $Name)

    return $Name.Trim().Trim('"', "'").ToLowerInvariant().Replace('-', '_')
}

function Test-IsBlockedPubRoute {
    param([Parameter(Mandatory = $true)] [string] $Name)

    $normalized = ConvertTo-NormalizedPackageName -Name $Name

    # `crypto` is the Dart SHA/hash utility. It is intentionally allowed; do not
    # replace these exact route checks with a broad "crypto" substring match.
    if ($normalized -eq 'crypto') {
        return $false
    }

    if ($normalized -in @(
        'openmls',
        'matrix',
        'matrix_sdk',
        'matrix_dart_sdk',
        'vodozemac',
        'flutter_vodozemac',
        'libsignal',
        'signal_protocol',
        'signal_protocol_dart',
        'signal_protocol_flutter'
    )) {
        return $true
    }

    return $normalized.StartsWith('libsignal_') -or
        $normalized.StartsWith('signal_protocol_')
}

function Test-IsBlockedCargoRoute {
    param([Parameter(Mandatory = $true)] [string] $Name)

    $normalized = ConvertTo-NormalizedPackageName -Name $Name
    return $normalized -eq 'vodozemac' -or
        $normalized -eq 'libsignal' -or
        $normalized.StartsWith('libsignal_') -or
        $normalized -eq 'signal_protocol' -or
        $normalized.StartsWith('signal_protocol_') -or
        $normalized -eq 'matrix_sdk' -or
        $normalized.StartsWith('matrix_sdk_')
}

function Get-YamlScalar {
    param([Parameter(Mandatory = $true)] [string] $Value)

    return $Value.Trim().Trim('"', "'")
}

function Get-PubspecDirectDependenciesFromContent {
    param([Parameter(Mandatory = $true)] [string] $Content)

    $result = [System.Collections.Generic.List[object]]::new()
    $section = $null
    $lineNumber = 0

    foreach ($line in ($Content -split "`r?`n")) {
        $lineNumber++

        if ($line -match '^(dependencies|dev_dependencies|dependency_overrides):\s*(?:#.*)?$') {
            $section = $Matches[1]
            continue
        }

        if ($line -match '^\S') {
            $section = $null
            continue
        }

        if ($null -ne $section -and
            $line -match '^ {2}(?<name>[A-Za-z0-9_]+):(?:\s|$)') {
            $result.Add([pscustomobject]@{
                Name       = $Matches['name']
                Section    = $section
                LineNumber = $lineNumber
            })
        }
    }

    return @($result)
}

function Get-BlockedPubRouteMentionsFromContent {
    param([Parameter(Mandatory = $true)] [string] $Content)

    # This deliberately scans every YAML mapping key rather than relying on a
    # particular indentation style. Pub permits quoted keys and flow mappings,
    # and pubspec.lock can introduce a prohibited route transitively. A
    # suspicious key outside a dependency section is also rejected so the gate
    # fails closed instead of silently accepting syntax it does not understand.
    $result = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in ($Content -split "`r?`n")) {
        $lineNumber++
        foreach ($match in [regex]::Matches(
            $line,
            '(?:^|[{,])\s*["'']?(?<name>[A-Za-z0-9_-]+)["'']?\s*:',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )) {
            $name = $match.Groups['name'].Value
            if (Test-IsBlockedPubRoute -Name $name) {
                $result.Add([pscustomobject]@{
                    Name       = $name
                    LineNumber = $lineNumber
                })
            }
        }
    }

    return @($result)
}

function Get-PubLockPackagesFromContent {
    param([Parameter(Mandatory = $true)] [string] $Content)

    $result = [System.Collections.Generic.List[object]]::new()
    $currentName = $null
    $currentDependency = $null
    $currentSource = $null
    $currentVersion = $null

    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -match '^ {2}(?<name>[A-Za-z0-9_]+):\s*$') {
            if ($null -ne $currentName) {
                $result.Add([pscustomobject]@{
                    Name       = $currentName
                    Dependency = $currentDependency
                    Source     = $currentSource
                    Version    = $currentVersion
                })
            }

            $currentName = $Matches['name']
            $currentDependency = $null
            $currentSource = $null
            $currentVersion = $null
            continue
        }

        if ($null -eq $currentName) {
            continue
        }

        if ($line -match '^ {4}dependency:\s*(?<value>.+?)\s*$') {
            $currentDependency = Get-YamlScalar -Value $Matches['value']
        } elseif ($line -match '^ {4}source:\s*(?<value>.+?)\s*$') {
            $currentSource = Get-YamlScalar -Value $Matches['value']
        } elseif ($line -match '^ {4}version:\s*(?<value>.+?)\s*$') {
            $currentVersion = Get-YamlScalar -Value $Matches['value']
        }
    }

    if ($null -ne $currentName) {
        $result.Add([pscustomobject]@{
            Name       = $currentName
            Dependency = $currentDependency
            Source     = $currentSource
            Version    = $currentVersion
        })
    }

    return @($result)
}

function Get-TomlScalar {
    param([Parameter(Mandatory = $true)] [string] $Value)

    $trimmed = $Value.Trim().TrimEnd(',').Trim()
    if ($trimmed -match '^"(?<value>[^"]*)"') {
        return $Matches['value']
    }
    if ($trimmed -match "^'(?<value>[^']*)'") {
        return $Matches['value']
    }
    return $trimmed
}

function Get-InlineCargoFields {
    param([Parameter(Mandatory = $true)] [string] $Value)

    $fields = @{}
    $trimmed = $Value.Trim()
    if ($trimmed -match '^["'']') {
        $fields['version'] = Get-TomlScalar -Value $trimmed
        return $fields
    }

    if (-not $trimmed.StartsWith('{')) {
        return $fields
    }

    $fieldPattern = '(?<key>package|version|git|tag|rev|branch|path|workspace)\s*=\s*(?<value>"[^"]*"|''[^'']*''|true|false)'
    foreach ($match in [regex]::Matches(
        $trimmed,
        $fieldPattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )) {
        $key = $match.Groups['key'].Value.ToLowerInvariant()
        $fields[$key] = Get-TomlScalar -Value $match.Groups['value'].Value
    }

    return $fields
}

function New-CargoDependencyRecord {
    param(
        [Parameter(Mandatory = $true)] [string] $Alias,
        [Parameter(Mandatory = $true)] [string] $Section,
        [Parameter(Mandatory = $true)] [int] $LineNumber,
        [Parameter(Mandatory = $true)] [hashtable] $Fields
    )

    $packageName = $Alias
    if ($Fields.ContainsKey('package')) {
        $packageName = [string] $Fields['package']
    }

    return [pscustomobject]@{
        Alias       = $Alias
        PackageName = $packageName
        Section     = $Section
        LineNumber  = $LineNumber
        Fields      = $Fields
    }
}

function Get-CargoDependenciesFromContent {
    param([Parameter(Mandatory = $true)] [string] $Content)

    $result = [System.Collections.Generic.List[object]]::new()
    $section = $null
    $isDependencyList = $false
    $detailedAlias = $null
    $detailedSection = $null
    $detailedLineNumber = 0
    $detailedFields = $null
    $lineNumber = 0

    foreach ($line in ($Content -split "`r?`n")) {
        $lineNumber++
        $trimmed = $line.Trim()

        if ($trimmed -match '^\[(?<header>[^\]]+)\]\s*$') {
            if ($null -ne $detailedAlias) {
                $result.Add((New-CargoDependencyRecord `
                    -Alias $detailedAlias `
                    -Section $detailedSection `
                    -LineNumber $detailedLineNumber `
                    -Fields $detailedFields))
            }

            $header = $Matches['header'].Trim()
            $section = $header
            $isDependencyList = $false
            $detailedAlias = $null
            $detailedSection = $null
            $detailedLineNumber = 0
            $detailedFields = $null

            $detailedMatch = [regex]::Match(
                $header,
                '(?:^|\.)(?:dependencies|dev-dependencies|build-dependencies)\.(?<name>[A-Za-z0-9_-]+|"[^"]+")$',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
            if ($detailedMatch.Success) {
                $detailedAlias = $detailedMatch.Groups['name'].Value.Trim('"')
                $detailedSection = $header
                $detailedLineNumber = $lineNumber
                $detailedFields = @{}
                continue
            }

            if ($header -match '(?:^|\.)(?:dependencies|dev-dependencies|build-dependencies)$' -or
                $header -match '^patch\.') {
                $isDependencyList = $true
            }
            continue
        }

        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }

        if ($null -ne $detailedAlias -and
            $trimmed -match '^(?<key>package|version|git|tag|rev|branch|path|workspace)\s*=\s*(?<value>.+?)\s*$') {
            $detailedFields[$Matches['key'].ToLowerInvariant()] = Get-TomlScalar -Value $Matches['value']
            continue
        }

        if ($isDependencyList -and
            $trimmed -match '^(?<name>[A-Za-z0-9_-]+|"[^"]+")\s*=\s*(?<value>.+?)\s*$') {
            $alias = $Matches['name'].Trim('"')
            $fields = Get-InlineCargoFields -Value $Matches['value']
            $result.Add((New-CargoDependencyRecord `
                -Alias $alias `
                -Section $section `
                -LineNumber $lineNumber `
                -Fields $fields))
        }
    }

    if ($null -ne $detailedAlias) {
        $result.Add((New-CargoDependencyRecord `
            -Alias $detailedAlias `
            -Section $detailedSection `
            -LineNumber $detailedLineNumber `
            -Fields $detailedFields))
    }

    return @($result)
}

function Get-CargoPackageIdentityFromContent {
    param([Parameter(Mandatory = $true)] [string] $Content)

    $inPackage = $false
    $name = $null
    $version = $null

    foreach ($line in ($Content -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(?<header>[^\]]+)\]\s*$') {
            $inPackage = $Matches['header'].Trim() -eq 'package'
            continue
        }
        if (-not $inPackage -or $trimmed.StartsWith('#')) {
            continue
        }
        if ($trimmed -match '^name\s*=\s*(?<value>.+?)\s*$') {
            $name = Get-TomlScalar -Value $Matches['value']
        } elseif ($trimmed -match '^version\s*=\s*(?<value>.+?)\s*$') {
            $version = Get-TomlScalar -Value $Matches['value']
        }
    }

    return [pscustomobject]@{
        Name    = $name
        Version = $version
    }
}

function Test-SemVerAtLeastOpenMlsMinimum {
    param([Parameter(Mandatory = $true)] [string] $Version)

    $trimmed = $Version.Trim()
    if ($trimmed -match '\d+\.\d+(?:\.\d+)?-[0-9A-Za-z]') {
        return $false
    }
    if ($trimmed -notmatch '^(?<major>\d+)\.(?<minor>\d+)(?:\.(?<patch>\d+))?(?:\+[0-9A-Za-z.-]+)?$') {
        return $false
    }

    $major = [int] $Matches['major']
    $minor = [int] $Matches['minor']
    return $major -gt 0 -or $minor -ge 9
}

function Test-OpenMlsConstraintExcludesOldVersions {
    param([Parameter(Mandatory = $true)] [string] $Constraint)

    foreach ($alternative in ($Constraint -split '\|\|')) {
        $part = $alternative.Trim()
        if ($part.Length -eq 0 -or $part -match '\d+\.\d+(?:\.\d+)?-[0-9A-Za-z]') {
            return $false
        }

        $candidate = $null
        if ($part -match '^(?:=|\^|~)?\s*(?<version>\d+\.\d+(?:\.\d+)?)') {
            $candidate = $Matches['version']
        } else {
            $lowerBounds = [regex]::Matches($part, '(?:^|,)\s*(?:>=|>)\s*(?<version>\d+\.\d+(?:\.\d+)?)')
            if ($lowerBounds.Count -eq 0) {
                return $false
            }
            $candidate = $lowerBounds[0].Groups['version'].Value
        }

        if (-not (Test-SemVerAtLeastOpenMlsMinimum -Version $candidate)) {
            return $false
        }
    }

    return $true
}

function Test-OpenMlsTagIsSafe {
    param([Parameter(Mandatory = $true)] [string] $Tag)

    if ($Tag -notmatch '(?i)(?:^v?|openmls[-_]?v)(?<version>\d+\.\d+(?:\.\d+)?)$') {
        return $false
    }
    return Test-SemVerAtLeastOpenMlsMinimum -Version $Matches['version']
}

function Test-OpenMlsVersionIsExactlyPinned {
    param([Parameter(Mandatory = $true)] [string] $Version)

    return $Version.Trim() -match '^=\s*\d+\.\d+\.\d+(?:\+[0-9A-Za-z.-]+)?$'
}

function Test-GitRevisionIsImmutable {
    param([Parameter(Mandatory = $true)] [string] $Revision)

    # Accept full SHA-1 and SHA-256 object identifiers only. Short hashes and
    # symbolic refs can become ambiguous or move.
    return $Revision.Trim() -match '^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$'
}

function Get-CargoLockPackagesFromContent {
    param([Parameter(Mandatory = $true)] [string] $Content)

    $result = [System.Collections.Generic.List[object]]::new()
    $blockPattern = '(?ms)^\[\[package\]\]\s*(?<body>.*?)(?=^\[\[package\]\]|\z)'
    foreach ($block in [regex]::Matches($Content, $blockPattern)) {
        $body = $block.Groups['body'].Value
        $name = $null
        $version = $null
        $source = $null

        if ($body -match '(?m)^name\s*=\s*"(?<value>[^"]+)"\s*$') {
            $name = $Matches['value']
        }
        if ($body -match '(?m)^version\s*=\s*"(?<value>[^"]+)"\s*$') {
            $version = $Matches['value']
        }
        if ($body -match '(?m)^source\s*=\s*"(?<value>[^"]+)"\s*$') {
            $source = $Matches['value']
        }

        $result.Add([pscustomobject]@{
            Name    = $name
            Version = $version
            Source  = $source
        })
    }

    return @($result)
}

function Test-ManifestHasCargoLock {
    param([Parameter(Mandatory = $true)] [string] $ManifestPath)

    $directory = Split-Path -Parent $ManifestPath
    while ($directory.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath (Join-Path $directory 'Cargo.lock') -PathType Leaf) {
            return $true
        }
        if ([string]::Equals($directory, $workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $directory = Split-Path -Parent $directory
    }
    return $false
}

function Assert-PolicySelfTests {
    if (-not (Test-OpenMlsConstraintExcludesOldVersions -Constraint '=0.9.0')) {
        throw 'Self-test failed: OpenMLS 0.9.0 must be accepted.'
    }
    if (-not (Test-OpenMlsConstraintExcludesOldVersions -Constraint '>=0.9.0, <1.0.0')) {
        throw 'Self-test failed: a range bounded below by 0.9.0 must be recognized as safe.'
    }
    if (Test-OpenMlsConstraintExcludesOldVersions -Constraint '^0.8.1') {
        throw 'Self-test failed: OpenMLS 0.8.1 must be rejected.'
    }
    if (Test-OpenMlsConstraintExcludesOldVersions -Constraint '*') {
        throw 'Self-test failed: an unbounded OpenMLS dependency must be rejected.'
    }
    if (Test-OpenMlsConstraintExcludesOldVersions -Constraint '0.9.0-rc.1') {
        throw 'Self-test failed: a pre-0.9.0 release candidate must be rejected.'
    }
    if (-not (Test-OpenMlsTagIsSafe -Tag 'openmls-v0.9.0')) {
        throw 'Self-test failed: the reviewed OpenMLS tag form must be accepted.'
    }
    if (Test-OpenMlsTagIsSafe -Tag 'openmls-v0.8.1') {
        throw 'Self-test failed: the vulnerable OpenMLS tag must be rejected.'
    }
    if (-not (Test-GitRevisionIsImmutable -Revision ('a' * 40)) -or
        (Test-GitRevisionIsImmutable -Revision 'deadbeef')) {
        throw 'Self-test failed: only full immutable git revisions may satisfy the pinning rule.'
    }
    if (Test-IsBlockedPubRoute -Name 'crypto') {
        throw 'Self-test failed: the Dart crypto hash package must remain allowed.'
    }
    if (-not (Test-IsBlockedPubRoute -Name 'flutter_vodozemac')) {
        throw 'Self-test failed: flutter_vodozemac must be blocked.'
    }

    $pubspecFixture = @"
dependencies:
  crypto: ^3.0.0
  matrix: ^10.0.0
"@
    $pubDependencies = @(Get-PubspecDirectDependenciesFromContent -Content $pubspecFixture)
    if ($pubDependencies.Count -ne 2 -or
        -not ($pubDependencies.Name -contains 'crypto') -or
        -not ($pubDependencies.Name -contains 'matrix')) {
        throw 'Self-test failed: pubspec dependency parsing is incomplete.'
    }

    $quotedFlowFixture = @"
dependencies: { 'matrix': ^10.0.0, "flutter_vodozemac": ^1.0.0 }
"@
    $blockedMentions = @(Get-BlockedPubRouteMentionsFromContent -Content $quotedFlowFixture)
    if ($blockedMentions.Count -ne 2 -or
        -not ($blockedMentions.Name -contains 'matrix') -or
        -not ($blockedMentions.Name -contains 'flutter_vodozemac')) {
        throw 'Self-test failed: quoted or flow-style blocked pub routes were not detected.'
    }

    $cargoFixture = @"
[dependencies]
safe_mls = { package = "openmls", version = "=0.9.0" }
vodozemac = "0.10.0"
"@
    $cargoDependencies = @(Get-CargoDependenciesFromContent -Content $cargoFixture)
    if ($cargoDependencies.Count -ne 2 -or
        -not ($cargoDependencies.PackageName -contains 'openmls') -or
        -not ($cargoDependencies.PackageName -contains 'vodozemac')) {
        throw 'Self-test failed: Cargo dependency parsing is incomplete.'
    }

    Write-Host 'Crypto dependency validator self-tests passed.' -ForegroundColor Green
}

if ($SelfTest) {
    Assert-PolicySelfTests
}

$pubspecFiles = @(Get-ControlledManifestFiles -Names @('pubspec.yaml'))
$pubLockFiles = @(Get-ControlledManifestFiles -Names @('pubspec.lock'))
$cargoManifestFiles = @(Get-ControlledManifestFiles -Names @('Cargo.toml'))
$cargoLockFiles = @(Get-ControlledManifestFiles -Names @('Cargo.lock'))
$cargoConfigFiles = @(
    Get-ControlledManifestFiles -Names @('config', 'config.toml') |
        Where-Object {
            (Split-Path -Leaf (Split-Path -Parent $_.FullName)) -eq '.cargo'
        }
)

foreach ($file in $pubspecFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($dependency in Get-BlockedPubRouteMentionsFromContent -Content $content) {
        Add-PolicyViolation `
            -Path $file.FullName `
            -Message "line $($dependency.LineNumber): '$($dependency.Name)' selects an unapproved E2EE route. See docs/adr/0001-e2ee-protocol.md."
    }
}

foreach ($file in $pubLockFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($package in Get-BlockedPubRouteMentionsFromContent -Content $content) {
        Add-PolicyViolation `
            -Path $file.FullName `
            -Message "line $($package.LineNumber): lockfile contains unapproved direct or transitive crypto route '$($package.Name)'."
    }
}

foreach ($file in $cargoManifestFiles) {
    Add-PolicyViolation `
        -Path $file.FullName `
        -Message 'Rust dependencies are fail-closed until the app-owned MLS bridge has cargo metadata, source provenance, licence, advisory, and native artifact verification.'
}

foreach ($file in $cargoLockFiles) {
    Add-PolicyViolation `
        -Path $file.FullName `
        -Message 'Rust lockfiles are not accepted before the reviewed MLS bridge ingestion workflow exists.'
}

foreach ($file in $cargoConfigFiles) {
    Add-PolicyViolation `
        -Path $file.FullName `
        -Message 'Cargo source configuration is not accepted before registry/source replacement verification exists.'
}

if ($script:violations.Count -gt 0) {
    Write-Host 'Crypto dependency policy failed:' -ForegroundColor Red
    foreach ($violation in $script:violations) {
        Write-Host " - $violation" -ForegroundColor Red
    }
    throw "Crypto dependency policy found $($script:violations.Count) violation(s)."
}

Write-Host (
    'Crypto dependency policy passed. Inspected {0} pubspec, {1} pub lock, {2} Cargo manifest, {3} Cargo lock, and {4} Cargo config file(s).' -f
        $pubspecFiles.Count,
        $pubLockFiles.Count,
        $cargoManifestFiles.Count,
        $cargoLockFiles.Count,
        $cargoConfigFiles.Count
) -ForegroundColor Green
