# collab_documents

Security-domain contracts for collaborative documents in the Secure Collab
client. The package intentionally contains **no home-grown CRDT, encryption,
signature, or key-storage implementation**. Production must inject a reviewed
CRDT engine, OpenMLS application-message protection, an OS-protected device
signer/verifier, and crash-safe stores through the exported ports.

## Privacy boundary

The relayable event contains only an opaque security-domain ID, a canonical
32-byte random document ID, event/member/device IDs, positive permission and
MLS membership epochs, a device sequence, a coarse event category, at most 1 MiB of decoded ciphertext,
and an Ed25519 signature. Titles, document text, comments, filenames, display
names, email addresses, CRDT changes, causal/change/version heads, and content
keys are never server metadata or public AAD. Unknown wire fields are rejected.
Causal heads remain inside the MLS-encrypted CRDT payload only.

Every event must:

1. bind its metadata as AEAD AAD in the OpenMLS application message;
2. be signed by the author device over the exact AAD and ciphertext;
3. match the current permission and MLS membership epochs;
4. arrive with the next document-and-device lifetime sequence and a new event
   ID (permission changes never reset this counter);
5. be authorized by the current `viewer/commenter/suggestor/editor/admin`
   roster; and
6. have its successor replay state durably committed before the server cursor
   is acknowledged.

The security-domain ID is also bound into the AAD, so a valid event from one
homeserver cannot be replayed into a migrated or unrelated security domain.

The coarse event category is authenticated public AAD so the homeserver can
apply role-based abuse controls without decrypting content. Permission changes
use a separate route and commit exactly one target mutation per permission
epoch.

CRDT convergence is not authorization. A member with decryption keys can run a
modified client, so every recipient rechecks the device signature, epoch, and
role before applying a change. Permission changes and the related MLS commit
must be one crash-safe transaction. Removing access cannot erase copies that a
former member already decrypted.

## ArtCraft/WordCraft-inspired command boundary

UI actions, keyboard shortcuts, a local CLI, and optional MCP integration use
the same bounded `DocumentCommandId` values and authorization mapping. This
adopts the stable-command idea without adopting a plaintext collaboration
server. MCP and AI access to decrypted content is disabled unless the tool is a
visible roster participant **and** presents a signed, document/tool/command/
scope-bound, expiring, one-use consent grant. A caller-provided boolean cannot
authorize plaintext access.
An integration must not silently treat the homeserver, an AI provider, or an
administrator as a content participant.

## Entitlement downgrade

Creation and publishing new edits may be a paid work feature. Losing that
entitlement never blocks reading existing documents, encrypted export,
deletion, security history, or recovery/export of local unpublished work.
Cryptographic safety and data portability are not subscription features.

## Required integration gates

- exact-version, audited CRDT implementation with Korean IME, grapheme, emoji,
  offline fork/merge, duplicate, reordering, and malicious-input tests;
- real OpenMLS protection and OS-protected device keys;
- atomic permission/MLS persistence and one generation containing the server
  cursor, encrypted CRDT/MLS/replay state, and durable outbound event queue;
- signed snapshot/history-checkpoint verification before the bounded replay-ID
  window can be compacted; silent local replay-state truncation is forbidden;
- bounded splitting of large CRDT edits so each protected relay event stays
  within the 1 MiB decoded ciphertext limit;
- encrypted snapshots and object attachments with independent AAD domains;
  snapshot sync uploads an encrypted media object and sends only its
  authenticated descriptor inside the MLS ciphertext;
- fuzzing for wire, CRDT, and snapshot decoders;
- long-offline, disk-full, crash-recovery, revoked-device, and 2018-era device
  performance tests.

Blockchain anchoring is not used for document content, IDs, changes, or heads.
At most, the separate key-transparency system may anchor a fixed-size aggregate
checkpoint; it never replaces MLS encryption or device authorization.
