[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workflowPath = Join-Path $workspaceRoot '.github/workflows/source-validation.yml'
$releaseWorkflowPath = Join-Path $workspaceRoot '.github/workflows/release-gate.yml'
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

if (-not (Test-Path -LiteralPath $candidateBuildPath)) {
    throw 'Missing scripts/build-release-candidate.ps1.'
}

if (-not (Test-Path -LiteralPath $dependabotPath)) {
    throw 'Missing .github/dependabot.yml for pinned action update proposals.'
}

$workflow = Get-Content -LiteralPath $workflowPath -Raw
$releaseWorkflow = Get-Content -LiteralPath $releaseWorkflowPath -Raw
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
if ($dependabot -notmatch '(?m)^\s*- package-ecosystem:\s*github-actions\s*$' -or
    $dependabot -notmatch '(?m)^\s+interval:\s*weekly\s*$') {
    throw 'Dependabot must propose weekly updates for pinned GitHub Actions.'
}

Write-Host 'CI workflow policy validation passed.' -ForegroundColor Green
