[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$contractPath = Join-Path $workspaceRoot 'contracts\chat-api.openapi.yaml'
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw "OpenAPI contract was not found: $contractPath"
}
$contract = Get-Content -LiteralPath $contractPath -Raw

function Require-ContractPattern {
    param(
        [Parameter(Mandatory = $true)] [string] $Pattern,
        [Parameter(Mandatory = $true)] [string] $Message
    )
    if (-not [regex]::IsMatch(
        $contract,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )) {
        throw "Contract invariant failed: $Message"
    }
}

function Forbid-ContractPattern {
    param(
        [Parameter(Mandatory = $true)] [string] $Pattern,
        [Parameter(Mandatory = $true)] [string] $Message
    )
    if ([regex]::IsMatch(
        $contract,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )) {
        throw "Contract invariant failed: $Message"
    }
}

if ($contract.Contains("`t")) {
    throw 'Contract invariant failed: YAML must not contain tab indentation.'
}

$requiredPatterns = [ordered]@{
    '^openapi: 3\.1\.0\s*$' = 'OpenAPI 3.1 is required.'
    '^\s+version: 0\.7\.0\s*$' = 'The no-escrow API revision must remain explicit.'
    '^  /v1/homeserver/profile:\s*$' = 'Homeserver profile discovery is required.'
    '^  /v1/members:\s*$' = 'The active-member directory is required.'
    '^  /v1/invitations:\s*$' = 'Invite-only registration is required.'
    '^  /v1/registrations/accept-invitation:\s*$' = 'Invitation acceptance must keep its secret out of the URL.'
    '^  /v1/conversations:\s*$' = 'Member-created conversations are required.'
    '^  /v1/conversations/\{conversation_id\}/messages:\s*$' = 'Opaque message synchronization is required.'
    '^  /v1/media/uploads:\s*$' = 'Encrypted media upload initiation is required.'
    '^  /v1/media/uploads/\{upload_id\}/chunks/\{chunk_index\}:\s*$' = 'Bounded resumable upload chunks are required.'
    '^  /v1/media/uploads/\{upload_id\}/complete:\s*$' = 'Whole-object verification before commit is required.'
    '^  /v1/media/objects/\{object_id\}/manifest:\s*$' = 'Authenticated encrypted-object manifests are required.'
    '^  /v1/media/objects/\{object_id\}/chunks/\{chunk_index\}:\s*$' = 'Bounded encrypted downloads are required.'
    '^  /v1/key-transparency/checkpoints/latest:\s*$' = 'Signed key-transparency checkpoints are required.'
    '^  /v1/key-transparency/proofs/inclusion:\s*$' = 'Inclusion proofs are required.'
    '^  /v1/key-transparency/proofs/consistency:\s*$' = 'Append-only consistency proofs are required.'
    '^  /v1/key-transparency/checkpoint-anchors:\s*$' = 'The optional minimal checkpoint anchor route is required.'
    '^    SecurityMode:\s*\r?\n\s+type: string\s*\r?\n\s+const: TRUE_E2EE\s*$' = 'Both products must have only TRUE_E2EE mode.'
    'const: PRIVACY_CONSUMER' = 'The consumer product discriminator is required.'
    'const: SECURE_COLLAB' = 'The collaboration product discriminator is required.'
    'ownership_model:\s*\r?\n\s+const: PERSONALLY_OWNED' = 'Every server must be personally owned.'
    'federation_enabled:\s*\r?\n\s+const: false' = 'Federation must fail closed.'
    'member_conversation_creation:\s*\r?\n\s+const: ENABLED_FOR_ACTIVE_MEMBERS' = 'Active members must create chats without per-room owner approval.'
    'server_can_decrypt_message_content:\s*\r?\n\s+const: false' = 'A homeserver must not receive content keys.'
    'key_transparency_enabled:\s*\r?\n\s+type: boolean' = 'A profile must report actual key-transparency deployment availability.'
    '^    TrueE2eeMessageEnvelope:\s*$' = 'Only the no-escrow encrypted message envelope is permitted.'
    '^    EncryptedMediaDescriptor:\s*$' = 'A server-safe encrypted media descriptor is required.'
    '^    BlockchainCheckpointAnchorPayload:\s*$' = 'A closed chain payload schema is required.'
    'aggregate_checkpoint_commitment:' = 'The chain payload must use a single aggregate commitment.'
    'schema_version:\s*\r?\n\s+const: 2' = 'The chain payload schema version must be explicit.'
    'protocol_domain:\s*\r?\n\s+const: key-transparency/blockchain-anchor/v2' = 'The chain payload must use its v2 domain separation.'
    'const: no-store' = 'Responses containing invitation material must disable caching.'
    'writeOnly: true' = 'Invitation secrets and possession proofs must be write-only.'
    "pattern: '\^\[A-Za-z0-9_-\]\{42\}\[AQgw\]\$'" = 'Every 32-byte digest, key, and nonce must use canonical unpadded base64url tail bits.'
    "pattern: '\^\[A-Za-z0-9_-\]\{85\}\[AEIMQUYcgkosw048\]\$'" = 'The 64-byte registration proof must use canonical unpadded base64url tail bits.'
    'const: ko' = 'Korean must remain the homeserver default locale.'
}

foreach ($entry in $requiredPatterns.GetEnumerator()) {
    Require-ContractPattern -Pattern $entry.Key -Message $entry.Value
}

$forbiddenPatterns = [ordered]@{
    '(?i)MANAGED_RECOVERABLE' = 'A server-readable message mode must not return.'
    '(?i)recovery[_A-Za-z]*capsule' = 'Content-key capsule fields are forbidden.'
    '(?i)key[_ -]?escrow' = 'Server key custody terminology is forbidden.'
    '(?i)managed[_ -]?recovery' = 'Server-assisted content recovery is forbidden.'
    '(?i)lawful[_ -]?(?:access|export)' = 'Special plaintext export endpoints are forbidden.'
    '^    OffChainCiphertextObject:\s*$' = 'Message ciphertext must stay bounded inline; attachments use the media API.'
    '^\s+(?:public_url|presigned_url|download_url):\s*$' = 'Public or presigned media URLs are forbidden.'
}
foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
    Forbid-ContractPattern -Pattern $entry.Key -Message $entry.Value
}

$anchorStart = $contract.IndexOf("    BlockchainCheckpointAnchorPayload:")
$anchorEnd = $contract.IndexOf("    SubmitCheckpointAnchorRequest:", $anchorStart)
if ($anchorStart -lt 0 -or $anchorEnd -le $anchorStart) {
    throw 'Contract invariant failed: checkpoint anchor payload scope is malformed.'
}
$anchorBlock = $contract.Substring($anchorStart, $anchorEnd - $anchorStart)
if ([regex]::IsMatch($anchorBlock, '(?m)^\s+tree_size:\s*$')) {
    throw 'Contract invariant failed: public checkpoint anchor payload must not expose tree_size.'
}
$anchorFields = [regex]::Matches(
    $anchorBlock,
    '(?m)^ {8}(schema_version|protocol_domain|aggregate_checkpoint_commitment):\s*$'
)
if ($anchorFields.Count -ne 3) {
    throw 'Contract invariant failed: checkpoint anchor payload must contain only its three public fields.'
}

$localReferences = [regex]::Matches(
    $contract,
    '\$ref:\s*''#/components/(?<section>schemas|parameters|headers|responses|securitySchemes)/(?<name>[A-Za-z][A-Za-z0-9]*)'''
)
if ($localReferences.Count -eq 0) {
    throw 'Contract invariant failed: no local component references were found.'
}
$missingReferences = [System.Collections.Generic.SortedSet[string]]::new()
foreach ($reference in $localReferences) {
    $name = $reference.Groups['name'].Value
    $definitionPattern = "(?m)^    $([regex]::Escape($name)):\s*$"
    if (-not [regex]::IsMatch($contract, $definitionPattern)) {
        [void] $missingReferences.Add($reference.Value)
    }
}
if ($missingReferences.Count -gt 0) {
    throw "Contract invariant failed: unresolved local references: $($missingReferences -join ', ')"
}

$invitationSecretDefinitions = [regex]::Matches(
    $contract,
    '(?m)^\s{8,12}invitation_secret:\s*$'
).Count
$writeOnlyInvitationSecrets = [regex]::Matches(
    $contract,
    '(?m)^ {12}invitation_secret:\s*\r?\n(?: {14}.+\r?\n){0,5} {14}writeOnly: true\s*$'
).Count
$readOnlyInvitationSecrets = [regex]::Matches(
    $contract,
    '(?m)^ {8}invitation_secret:\s*\r?\n(?: {10}.+\r?\n){0,5} {10}readOnly: true\s*$'
).Count
if ($invitationSecretDefinitions -ne 2 -or
    $writeOnlyInvitationSecrets -ne 1 -or
    $readOnlyInvitationSecrets -ne 1) {
    throw 'Contract invariant failed: invitation output must be read-only and acceptance input write-only.'
}

Write-Host 'No-escrow OpenAPI security contract invariants passed.' -ForegroundColor Green
