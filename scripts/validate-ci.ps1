[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workflowPath = Join-Path $workspaceRoot '.github/workflows/source-validation.yml'
$releaseWorkflowPath = Join-Path $workspaceRoot '.github/workflows/release-gate.yml'
$platformBuildWorkflowPath = Join-Path $workspaceRoot '.github/workflows/platform-build-smoke.yml'
$nativeCryptoWorkflowPath = Join-Path $workspaceRoot '.github/workflows/native-crypto.yml'
$blockchainContractWorkflowPath = Join-Path $workspaceRoot '.github/workflows/blockchain-contract.yml'
$dependencyReviewWorkflowPath = Join-Path $workspaceRoot '.github/workflows/dependency-review.yml'
$nativeCollabDocsWorkflowPath = Join-Path $workspaceRoot '.github/workflows/native-collab-docs.yml'
$dependabotPath = Join-Path $workspaceRoot '.github/dependabot.yml'
$preflightPath = Join-Path $workspaceRoot 'scripts/release-preflight.ps1'
$candidateBuildPath = Join-Path $workspaceRoot 'scripts/build-release-candidate.ps1'

if (-not (Test-Path -LiteralPath $workflowPath)) {
    throw 'Missing .github/workflows/source-validation.yml.'
}

if (-not (Test-Path -LiteralPath $preflightPath)) {
    throw 'Missing scripts/release-preflight.ps1.'
}

if (-not (Test-Path -LiteralPath $releaseWorkflowPath)) {
    throw 'Missing .github/workflows/release-gate.yml.'
}

if (-not (Test-Path -LiteralPath $platformBuildWorkflowPath)) {
    throw 'Missing .github/workflows/platform-build-smoke.yml.'
}

if (-not (Test-Path -LiteralPath $nativeCryptoWorkflowPath)) {
    throw 'Missing .github/workflows/native-crypto.yml.'
}

if (-not (Test-Path -LiteralPath $blockchainContractWorkflowPath)) {
    throw 'Missing .github/workflows/blockchain-contract.yml.'
}

if (-not (Test-Path -LiteralPath $dependencyReviewWorkflowPath)) {
    throw 'Missing .github/workflows/dependency-review.yml.'
}

if (-not (Test-Path -LiteralPath $nativeCollabDocsWorkflowPath)) {
    throw 'Missing .github/workflows/native-collab-docs.yml.'
}

if (-not (Test-Path -LiteralPath $candidateBuildPath)) {
    throw 'Missing scripts/build-release-candidate.ps1.'
}

if (-not (Test-Path -LiteralPath $dependabotPath)) {
    throw 'Missing .github/dependabot.yml for pinned action update proposals.'
}

$workflow = Get-Content -LiteralPath $workflowPath -Raw
$releaseWorkflow = Get-Content -LiteralPath $releaseWorkflowPath -Raw
$platformBuildWorkflow = Get-Content -LiteralPath $platformBuildWorkflowPath -Raw
$nativeCryptoWorkflow = Get-Content -LiteralPath $nativeCryptoWorkflowPath -Raw
$blockchainContractWorkflow = Get-Content -LiteralPath $blockchainContractWorkflowPath -Raw
$dependencyReviewWorkflow = Get-Content -LiteralPath $dependencyReviewWorkflowPath -Raw
$nativeCollabDocsWorkflow = Get-Content -LiteralPath $nativeCollabDocsWorkflowPath -Raw
$candidateBuild = Get-Content -LiteralPath $candidateBuildPath -Raw

if ($workflow -notmatch '(?m)^name:\s*Source validation \(no native release build\)\s*$') {
    throw 'The workflow name must explicitly state that it does not build native release artifacts.'
}

$actionReferences = [regex]::Matches($workflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
if ($actionReferences.Count -eq 0) {
    throw 'The source validation workflow does not reference any actions.'
}

foreach ($reference in $actionReferences) {
    $value = $reference.Groups[1].Value
    if ($value -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$') {
        throw "GitHub Action references must use a full 40-character commit SHA: $value"
    }
}

$releaseActionReferences = [regex]::Matches($releaseWorkflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
if ($releaseActionReferences.Count -eq 0) {
    throw 'The release source gate does not reference any actions.'
}
foreach ($reference in $releaseActionReferences) {
    $value = $reference.Groups[1].Value
    if ($value -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$') {
        throw "Release gate actions must use a full 40-character commit SHA: $value"
    }
}

$platformActionReferences = [regex]::Matches($platformBuildWorkflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
if ($platformActionReferences.Count -eq 0) {
    throw 'The platform build smoke workflow does not reference any actions.'
}
foreach ($reference in $platformActionReferences) {
    $value = $reference.Groups[1].Value
    if ($value -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$') {
        throw "Platform build smoke actions must use a full 40-character commit SHA: $value"
    }
}

$nativeCryptoActionReferences = [regex]::Matches($nativeCryptoWorkflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
if ($nativeCryptoActionReferences.Count -eq 0) {
    throw 'The native OpenMLS workflow does not reference any actions.'
}
foreach ($reference in $nativeCryptoActionReferences) {
    $value = $reference.Groups[1].Value
    if ($value -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$') {
        throw "Native OpenMLS actions must use a full 40-character commit SHA: $value"
    }
}

$blockchainContractActionReferences = [regex]::Matches($blockchainContractWorkflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
if ($blockchainContractActionReferences.Count -eq 0) {
    throw 'The blockchain contract workflow does not reference any actions.'
}
foreach ($reference in $blockchainContractActionReferences) {
    $value = $reference.Groups[1].Value
    if ($value -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$') {
        throw "Blockchain contract actions must use a full 40-character commit SHA: $value"
    }
}

$dependencyReviewActionReferences = [regex]::Matches($dependencyReviewWorkflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
if ($dependencyReviewActionReferences.Count -eq 0) {
    throw 'The dependency review workflow does not reference any actions.'
}
foreach ($reference in $dependencyReviewActionReferences) {
    $value = $reference.Groups[1].Value
    if ($value -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$') {
        throw "Dependency review actions must use a full 40-character commit SHA: $value"
    }
}

$nativeCollabDocsActionReferences = [regex]::Matches($nativeCollabDocsWorkflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
if ($nativeCollabDocsActionReferences.Count -eq 0) {
    throw 'The native collaborative-document workflow does not reference any actions.'
}
foreach ($reference in $nativeCollabDocsActionReferences) {
    $value = $reference.Groups[1].Value
    if ($value -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$') {
        throw "Native collaborative-document actions must use a full 40-character commit SHA: $value"
    }
}

$requiredPatterns = @(
    '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$',
    '(?m)^\s+persist-credentials:\s*false\s*$',
    "(?m)^\s+flutter-version:\s*'3\.47\.2'\s*$",
    '(?m)^\s+run:\s*\./scripts/check\.ps1 -EnforceLockfile\s*$',
    '(?m)^\s+git status --porcelain=v1 --untracked-files=all > /tmp/chat-platform-source-status\.txt\s*$',
    '(?m)^\s+test ! -s /tmp/chat-platform-source-status\.txt\s*$'
)

foreach ($pattern in $requiredPatterns) {
    if ($workflow -notmatch $pattern) {
        throw "Source validation workflow is missing required hardening pattern: $pattern"
    }
}

if ($workflow -match '(?im)^\s*(?:run:\s*)?.*flutter\s+build\b') {
    throw 'Source validation must not imply native artifact validation by running flutter build.'
}

$forbiddenPatterns = [ordered]@{
    '(?m)^\s*pull_request_target:\s*$' = 'pull_request_target must not execute untrusted contribution code.'
    '(?m)^\s*(?:write-all|contents:\s*write)\s*$' = 'Source validation must keep the GitHub token read-only.'
    '(?m)^\s*continue-on-error:\s*true\s*$' = 'Required source validation steps must not ignore failures.'
    '\$\{\{\s*secrets\.' = 'Source validation for untrusted pull requests must not consume repository secrets.'
}

foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
    if ($workflow -match $entry.Key) {
        throw $entry.Value
    }
}

if ($releaseWorkflow -notmatch '(?m)^name:\s*Release source gate \(no build or publication\)\s*$' -or
    $releaseWorkflow -notmatch '(?ms)^on:\s*\r?\n\s+workflow_dispatch:\s*$') {
    throw 'The release source gate must be explicitly manual and accurately named.'
}

if ($platformBuildWorkflow -notmatch '(?m)^name:\s*Native platform debug build smoke \(non-release\)\s*$' -or
    $platformBuildWorkflow -notmatch '(?ms)^on:\s*\r?\n\s+workflow_dispatch:\s*$') {
    throw 'The platform build smoke workflow must be explicitly manual and accurately named.'
}
if ($platformBuildWorkflow -match '(?m)^\s{2}(?:push|pull_request|pull_request_target|schedule):\s*$' -or
    $platformBuildWorkflow -notmatch '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$' -or
    $platformBuildWorkflow -notmatch '(?m)^\s+persist-credentials:\s*false\s*$' -or
    $platformBuildWorkflow -notmatch "(?m)^\s+flutter-version:\s*'3\.47\.2'\s*$") {
    throw 'Platform build smoke must be manual, read-only, pinned, and discard checkout credentials.'
}

$expectedPlatformEntries = @(
    @{
        Label = 'everyday_chat/android'
        Pattern = '(?ms)- app:\s*everyday_chat\s*\r?\n\s+platform:\s*android\s*\r?\n\s+runner:\s*ubuntu-24\.04\s*\r?\n\s+build_target:\s*apk\s*\r?\n\s+build_flags:\s*--debug --no-pub\s*$'
    },
    @{
        Label = 'secure_collab/android'
        Pattern = '(?ms)- app:\s*secure_collab\s*\r?\n\s+platform:\s*android\s*\r?\n\s+runner:\s*ubuntu-24\.04\s*\r?\n\s+build_target:\s*apk\s*\r?\n\s+build_flags:\s*--debug --no-pub\s*$'
    },
    @{
        Label = 'everyday_chat/linux'
        Pattern = '(?ms)- app:\s*everyday_chat\s*\r?\n\s+platform:\s*linux\s*\r?\n\s+runner:\s*ubuntu-24\.04\s*\r?\n\s+build_target:\s*linux\s*\r?\n\s+build_flags:\s*--debug --no-pub\s*$'
    },
    @{
        Label = 'secure_collab/linux'
        Pattern = '(?ms)- app:\s*secure_collab\s*\r?\n\s+platform:\s*linux\s*\r?\n\s+runner:\s*ubuntu-24\.04\s*\r?\n\s+build_target:\s*linux\s*\r?\n\s+build_flags:\s*--debug --no-pub\s*$'
    },
    @{
        Label = 'everyday_chat/windows'
        Pattern = '(?ms)- app:\s*everyday_chat\s*\r?\n\s+platform:\s*windows\s*\r?\n\s+runner:\s*windows-2025\s*\r?\n\s+build_target:\s*windows\s*\r?\n\s+build_flags:\s*--debug --no-pub\s*$'
    },
    @{
        Label = 'secure_collab/windows'
        Pattern = '(?ms)- app:\s*secure_collab\s*\r?\n\s+platform:\s*windows\s*\r?\n\s+runner:\s*windows-2025\s*\r?\n\s+build_target:\s*windows\s*\r?\n\s+build_flags:\s*--debug --no-pub\s*$'
    },
    @{
        Label = 'everyday_chat/ios'
        Pattern = '(?ms)- app:\s*everyday_chat\s*\r?\n\s+platform:\s*ios\s*\r?\n\s+runner:\s*macos-15\s*\r?\n\s+build_target:\s*ios\s*\r?\n\s+build_flags:\s*--simulator --debug --no-pub\s*$'
    },
    @{
        Label = 'secure_collab/ios'
        Pattern = '(?ms)- app:\s*secure_collab\s*\r?\n\s+platform:\s*ios\s*\r?\n\s+runner:\s*macos-15\s*\r?\n\s+build_target:\s*ios\s*\r?\n\s+build_flags:\s*--simulator --debug --no-pub\s*$'
    }
)

if ([regex]::Matches($platformBuildWorkflow, '(?m)^\s+- app:\s*').Count -ne $expectedPlatformEntries.Count) {
    throw 'Platform build smoke must contain exactly the reviewed eight app/platform entries.'
}
foreach ($entry in $expectedPlatformEntries) {
    if ($platformBuildWorkflow -notmatch $entry.Pattern) {
        throw "Platform build smoke entry is missing or altered: $($entry.Label)."
    }
}

$platformRequiredPatterns = @(
    '(?m)^\s+run:\s*dart pub get --enforce-lockfile\s*$',
    '(?m)^\s+run:\s*flutter build \$\{\{ matrix\.build_target \}\} \$\{\{ matrix\.build_flags \}\}\s*$',
    '(?m)^\s+run:\s*git diff --exit-code\s*$'
)
foreach ($pattern in $platformRequiredPatterns) {
    if ($platformBuildWorkflow -notmatch $pattern) {
        throw "Platform build smoke is missing required hardening pattern: $pattern"
    }
}

if ($platformBuildWorkflow -match '(?i)\$\{\{\s*secrets\.' -or
    $platformBuildWorkflow -match '(?im)^\s*-?\s*uses:\s*actions/upload-artifact@' -or
    $platformBuildWorkflow -match '(?im)\b(?:gh\s+release|npm\s+publish|dart\s+pub\s+publish|flutter\s+build\s+(?:appbundle|ipa)\b|--release\b)') {
    throw 'Platform debug smoke must not consume secrets, upload, publish, or build release-oriented packages.'
}

if ($nativeCryptoWorkflow -notmatch '(?m)^name:\s*Native OpenMLS security gate\s*$' -or
    $nativeCryptoWorkflow -notmatch '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$' -or
    $nativeCryptoWorkflow -notmatch '(?m)^\s+persist-credentials:\s*false\s*$' -or
    $nativeCryptoWorkflow -notmatch '(?m)^\s+runner:\s*\[ubuntu-24\.04, windows-2025, macos-15\]\s*$') {
    throw 'Native OpenMLS validation must be read-only, credential-free, and run on the reviewed three host OS runners.'
}
$nativeCryptoRequiredPatterns = @(
    '(?m)^\s+rustup toolchain install 1\.91\.0\s*$',
    '(?m)^\s+run:\s*cargo \+1\.91\.0 fmt --manifest-path native/openmls_bridge/Cargo\.toml -- --check\s*$',
    '(?m)^\s+--manifest-path native/openmls_bridge/Cargo\.toml\s*$',
    '(?m)^\s+--locked\s*$',
    '(?m)^\s+-D warnings\s*$'
)
foreach ($pattern in $nativeCryptoRequiredPatterns) {
    if ($nativeCryptoWorkflow -notmatch $pattern) {
        throw "Native OpenMLS workflow is missing a required deterministic gate: $pattern"
    }
}
if ([regex]::Matches($nativeCryptoWorkflow, '(?m)^\s+--locked\s*$').Count -lt 2 -or
    $nativeCryptoWorkflow -notmatch '(?m)^\s+--all-targets\s*$' -or
    $nativeCryptoWorkflow -match '(?i)\$\{\{\s*secrets\.' -or
    $nativeCryptoWorkflow -match '(?im)^\s*-?\s*uses:\s*actions/upload-artifact@' -or
    $nativeCryptoWorkflow -match '(?im)\b(?:cargo\s+publish|gh\s+release)\b') {
    throw 'Native OpenMLS validation must test locked all-target builds without secrets, artifact upload, or publication.'
}

if ($blockchainContractWorkflow -notmatch '(?m)^name:\s*Blockchain checkpoint contract gate\s*$' -or
    $blockchainContractWorkflow -notmatch '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$' -or
    $blockchainContractWorkflow -notmatch '(?m)^\s+persist-credentials:\s*false\s*$' -or
    $blockchainContractWorkflow -notmatch '(?m)^\s+runs-on:\s*windows-2025\s*$') {
    throw 'Blockchain contract validation must be read-only, credential-free, and run on the reviewed Windows runner.'
}
$blockchainContractRequiredPatterns = @(
    '(?m)^\s+\$uri = ''https://binaries\.soliditylang\.org/windows-amd64/solc-windows-amd64-v0\.8\.38\+commit\.1835d247\.exe''\s*$',
    '(?m)^\s+\$expected = ''3fb6699791d7eb9d8cb28168116cc9b5eca9f2bec1ec356f7d66034d91035e9b''\s*$',
    '(?m)^\s+run:\s*\./scripts/validate-blockchain-contract\.ps1 -CompilerPath \$env:SOLC_PATH\s*$',
    '(?m)^\s+run:\s*git diff --exit-code\s*$'
)
foreach ($pattern in $blockchainContractRequiredPatterns) {
    if ($blockchainContractWorkflow -notmatch $pattern) {
        throw "Blockchain contract workflow is missing a required deterministic gate: $pattern"
    }
}
if ($blockchainContractWorkflow -match '(?i)\$\{\{\s*secrets\.' -or
    $blockchainContractWorkflow -match '(?im)^\s*-?\s*uses:\s*actions/upload-artifact@' -or
    $blockchainContractWorkflow -match '(?im)\b(?:gh\s+release|forge\s+create|cast\s+send)\b') {
    throw 'Blockchain contract validation must not use secrets, upload artifacts, publish, or deploy.'
}

if ($dependencyReviewWorkflow -notmatch '(?m)^name:\s*Dependency vulnerability review\s*$' -or
    $dependencyReviewWorkflow -notmatch '(?ms)^on:\s*\r?\n\s+pull_request:\s*$' -or
    $dependencyReviewWorkflow -notmatch '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$' -or
    $dependencyReviewWorkflow -notmatch '(?m)^\s+persist-credentials:\s*false\s*$' -or
    $dependencyReviewWorkflow -notmatch '(?m)^\s+uses:\s*actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294\s+# v5\.0\.0\s*$' -or
    $dependencyReviewWorkflow -notmatch '(?m)^\s+fail-on-severity:\s*moderate\s*$') {
    throw 'Dependency review must be pull-request-only, read-only, immutable, and reject moderate-or-higher vulnerabilities.'
}
if ($dependencyReviewWorkflow -match '(?i)\$\{\{\s*secrets\.' -or
    $dependencyReviewWorkflow -match '(?m)^\s*pull_request_target:\s*$' -or
    $dependencyReviewWorkflow -match '(?m)^\s*(?:write-all|contents:\s*write)\s*$') {
    throw 'Dependency review must not use secrets, pull_request_target, or write permissions.'
}

if ($nativeCollabDocsWorkflow -notmatch '(?m)^name:\s*Native collaborative document CRDT gate\s*$' -or
    $nativeCollabDocsWorkflow -notmatch '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$' -or
    $nativeCollabDocsWorkflow -notmatch '(?m)^\s+persist-credentials:\s*false\s*$' -or
    $nativeCollabDocsWorkflow -notmatch '(?m)^\s+runner:\s*\[ubuntu-24\.04, windows-2025, macos-15\]\s*$') {
    throw 'Native collaborative-document validation must be read-only, credential-free, and run on the reviewed three host OS runners.'
}
$nativeCollabDocsRequiredPatterns = @(
    '(?m)^\s+rustup toolchain install 1\.91\.0\s*$',
    '(?m)^\s+run:\s*cargo \+1\.91\.0 fmt --manifest-path native/collab_crdt_bridge/Cargo\.toml -- --check\s*$',
    '(?m)^\s+--manifest-path native/collab_crdt_bridge/Cargo\.toml\s*$',
    '(?m)^\s+--locked\s*$',
    '(?m)^\s+-D warnings\s*$'
)
foreach ($pattern in $nativeCollabDocsRequiredPatterns) {
    if ($nativeCollabDocsWorkflow -notmatch $pattern) {
        throw "Native collaborative-document workflow is missing a required deterministic gate: $pattern"
    }
}
if ([regex]::Matches($nativeCollabDocsWorkflow, '(?m)^\s+--locked\s*$').Count -lt 2 -or
    $nativeCollabDocsWorkflow -notmatch '(?m)^\s+--all-targets\s*$' -or
    $nativeCollabDocsWorkflow -match '(?i)\$\{\{\s*secrets\.' -or
    $nativeCollabDocsWorkflow -match '(?im)^\s*-?\s*uses:\s*actions/upload-artifact@' -or
    $nativeCollabDocsWorkflow -match '(?im)\b(?:cargo\s+publish|gh\s+release)\b') {
    throw 'Native collaborative-document validation must test locked all-target builds without secrets, artifact upload, or publication.'
}
if ($releaseWorkflow -match '(?m)^\s{2}(?:push|pull_request|pull_request_target|schedule):\s*$') {
    throw 'The release source gate must not run automatically or on untrusted pull requests.'
}
if ($releaseWorkflow -notmatch '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$' -or
    $releaseWorkflow -notmatch '(?m)^\s+persist-credentials:\s*false\s*$' -or
    $releaseWorkflow -notmatch "(?m)^\s+flutter-version:\s*'3\.47\.2'\s*$") {
    throw 'The release source gate must use read-only contents permission and discard checkout credentials.'
}
if ($releaseWorkflow -notmatch '(?m)^\s+run:\s*\./scripts/check\.ps1 -EnforceLockfile\s*$' -or
    $releaseWorkflow -notmatch '(?m)^\s+run:\s*\./scripts/generate-sbom\.ps1\s*$' -or
    $releaseWorkflow -notmatch '(?m)^\s+run:\s*\./scripts/release-preflight\.ps1 -Json\s*$') {
    throw 'The release source gate must run deterministic source checks, generate an SBOM, and enforce release preflight.'
}
if ($releaseWorkflow -match '(?im)^\s*(?:run:\s*)?.*flutter\s+build\b' -or
    $releaseWorkflow -match '(?im)^\s*-?\s*uses:\s*actions/upload-artifact@' -or
    $releaseWorkflow -match '(?i)\$\{\{\s*secrets\.' -or
    $releaseWorkflow -match '(?im)\b(?:gh\s+release|npm\s+publish|dart\s+pub\s+publish)\b') {
    throw 'The source-only release gate must not build, upload, publish, or consume signing secrets.'
}
if ($releaseWorkflow -notmatch '(?m)^\s+git diff --exit-code\s*$' -or
    $releaseWorkflow -notmatch '(?m)^\s+git status --porcelain=v1 --untracked-files=all > /tmp/chat-platform-release-status\.txt\s*$' -or
    $releaseWorkflow -notmatch '(?m)^\s+test ! -s /tmp/chat-platform-release-status\.txt\s*$') {
    throw 'The release source gate must fail if validation or SBOM generation changes the source tree.'
}

if ($candidateBuild -notmatch "\[ValidateSet\('everyday_chat', 'secure_collab'\)\]" -or
    $candidateBuild -notmatch "\[ValidateSet\('android', 'windows', 'linux', 'ios', 'macos'\)\]" -or
    $candidateBuild -notmatch "'release-preflight\.ps1'" -or
    $candidateBuild -notmatch "'check\.ps1'" -or
    $candidateBuild -notmatch "'generate-sbom\.ps1'" -or
    -not $candidateBuild.Contains('if ($BuildName -cne $manifestBuildName -or [int64] $BuildNumber -ne $manifestBuildNumber)') -or
    $candidateBuild -notmatch '(?m)^\s*& \$flutter build \$buildTarget --release --build-name \$BuildName --build-number \$BuildNumber --no-pub\s*$') {
    throw 'The candidate builder must keep its fixed product/platform allowlists, manifest-bound version, and mandatory source, preflight, SBOM, and release build gates.'
}
if ($candidateBuild -match '(?i)\b(?:skip|bypass)(?:preflight|validation|signing)\b' -or
    $candidateBuild -match '(?i)\b(?:gh\s+release|npm\s+publish|dart\s+pub\s+publish)\b' -or
    $candidateBuild -match '(?i)Invoke-Expression') {
    throw 'The candidate builder must not expose gate bypasses, publish, or execute dynamically constructed commands.'
}

$dependabot = Get-Content -LiteralPath $dependabotPath -Raw
if ([regex]::Matches($dependabot, '(?m)^\s+interval:\s*weekly\s*$').Count -ne 4 -or
    $dependabot -notmatch '(?ms)^\s*- package-ecosystem:\s*github-actions\s*\r?\n\s+directory:\s*/\s*$' -or
    $dependabot -notmatch '(?ms)^\s*- package-ecosystem:\s*pub\s*\r?\n\s+directory:\s*/\s*$' -or
    $dependabot -notmatch '(?ms)^\s*- package-ecosystem:\s*cargo\s*\r?\n\s+directory:\s*/native/openmls_bridge\s*$' -or
    $dependabot -notmatch '(?ms)^\s*- package-ecosystem:\s*cargo\s*\r?\n\s+directory:\s*/native/collab_crdt_bridge\s*$') {
    throw 'Dependabot must propose weekly GitHub Actions, Pub, OpenMLS, and collaborative-document Cargo updates.'
}

Write-Host 'CI workflow policy validation passed.' -ForegroundColor Green
