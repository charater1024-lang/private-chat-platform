# homeserver_runtime

`homeserver_runtime` is a runnable, loopback-only reference vertical for the
personally owned chat homeserver. It uses `dart:io` directly and listens only on
`127.0.0.1`; it cannot be configured to bind to a LAN or public interface.

Implemented HTTP flows:

- owner/admin invitation creation and one-time member activation;
- mandatory external device proof verification and opaque bearer credentials;
- active-member direct and group conversation creation;
- bounded opaque TRUE_E2EE message append and byte-budgeted,
  conversation-scoped sync with exact continuation metadata;
- stable server event IDs and monotonically increasing conversation sequences;
- resumable, precommitted SHA-256 ciphertext chunk upload and download;
- conversation-participant authorization for every upload and object read;
- request binding to server domain, product, mode, policy, and resource version;
- bounded request, message, media, cursor, invitation, conversation, and
  idempotency state with per-member fairness limits.

The runtime does **not** encrypt or decrypt. A client crypto layer must produce
authenticated ciphertext, and the required `DeviceProofVerifier` callback must
be backed by an audited Ed25519 implementation. It must verify
`challenge.copySigningTranscript()` exactly; that domain-separated,
length-prefixed transcript binds the invitation, server/domain/policy, member
profile, nonce, and both device public keys. The server stores public device
keys, opaque message envelopes, and encrypted file bytes only. Filename, MIME
type, attachment key, base nonce, previews, and plaintext are rejected from the
server-visible media API.

Registration accepts only canonical unpadded base64url values: 32-byte Ed25519
and X25519 public keys, a 32-byte client nonce, and a 64-byte Ed25519 signature.
Concurrent proof verification is bounded and every verifier call has a deadline;
timeout, exception, or false all reject registration without consuming the
invitation. The deadline does not forcibly cancel the callback's underlying
`Future`. A timed-out call therefore keeps its concurrency slot until it
actually settles, and any late exception is absorbed as an authentication
failure. Production launchers should run verification in an externally
isolated, resource-bounded worker that they can terminate; a permanently
stalled verifier intentionally leaves its bounded slot unavailable.

The in-memory reference defaults cap one message at 1 MiB, all retained message
ciphertext at 64 MiB, and each sender at 16 MiB / 25,000 messages. One encrypted
media object is capped at 128 MiB, the retained media store at 256 MiB, and each
member's outstanding media reservation at 128 MiB. Operators may tune limits,
but cannot configure a single object or member reservation beyond the selected
store budget.

## Bootstrap

```dart
final runtime = await HomeserverRuntime.start(
  HomeserverRuntimeConfig(
    serverRef: 'server_reference_0001',
    displayName: 'My home server',
    securityDomainId: 'security_domain_0001',
    policyVersion: 'policy.1',
    productKind: ProductKind.consumer,
    ownerMemberRef: 'owner_member_000001',
    ownerDisplayName: 'Owner',
    ownerDeviceIdentity: ownerPublicIdentity,
    deviceProofVerifier: auditedVerifier.verify,
  ),
);
```

The launcher must move `runtime.ownerAccessToken` into an operating-system
credential store immediately. Registration credentials are returned in the
`X-Homeserver-Access-Token` response header with `Cache-Control: no-store`.
Credential lookup stores SHA-256 digests, but the bounded idempotency
cache retains exact successful responses—including one-time credential
responses—for its configured TTL so a lost response can be replayed safely.
Accepted message IDs additionally retain their immutable body digest and first
receipt with the message record, so ACK-loss retries remain safe after the
short idempotency cache expires.

For crash recovery, inject a previously opened `PrivateAtomicSnapshotStore`:

```dart
final runtime = await HomeserverRuntime.start(
  config,
  snapshotStore: snapshotStore,
  minimumSnapshotGeneration: trustedExternalGeneration,
);
final newOwnerToken = runtime.bootstrapOwnerAccessToken;
```

`bootstrapOwnerAccessToken` is non-null only when no snapshot existed and a new
owner was created. Store it before discarding the newly created runtime. On
recovery it is null because the snapshot contains only the owner's token digest;
the compatibility `ownerAccessToken` getter throws rather than fabricating or
recovering a credential. The launcher must retain the original token outside
the snapshot directory in an operating-system credential store.

## Security boundary

Plain HTTP is intentional only because the listener is strictly loopback. A
production home-server process must place an authenticated TLS gateway in front
of this service without changing the loopback bind.

The runtime now has a versioned, deterministic state codec and an injectable
`HomeserverRuntimeSnapshotStore` boundary. With a store configured, every
state-changing POST/PUT and every new pagination/sync cursor is serialized
through one request gate. The complete next state is committed with generation
compare-and-swap before the HTTP success response is written. A failed commit
restores the prior in-memory state and returns no success ACK. Recovery validates
the server/domain/policy/product/owner binding, exact object keys, canonical
encodings and timestamps, membership and device references, message sequences,
chunk and object digests, resource versions, derived counters, and configured
quotas before accepting credentials or serving bytes. Unknown schema versions,
malformed state and config mismatches fail closed.

Shutdown stops admission and waits for every accepted request, including a
request queued behind the persistence gate, to finish its commit or rollback.
Concurrent close callers share that completion. If the connection is forcibly
closed after commit but before the ACK arrives, the persisted idempotency record
allows an exact replay after restart without duplicating the mutation.

The snapshot includes member token digests, invitations, exact bounded
idempotency responses, conversations, opaque message envelopes, encrypted media
chunks, and cursors. One-time invitation/registration response credentials can
therefore exist inside the plaintext passed to the protector; authenticated
encryption is mandatory and its key must never be stored beside the snapshots.

`PrivateAtomicSnapshotStore` provides the concrete crash-recovery mechanics. It
binds namespace and generation as AEAD associated data, flushes a same-directory
temporary record before renaming it to an immutable generation, serializes
writers with an OS file lock, and rejects a corrupt highest generation instead
of silently falling back. Interrupted `.tmp` files are never committed. A
trusted external `minimumSnapshotGeneration` detects deletion rollback; without
an anchor outside the snapshot directory, file deletion rollback is
indistinguishable from an older store.

This is a correctness-oriented reference store, not a scalable production
database. Each mutation validates and rewrites the complete bounded snapshot,
and persistent mode deliberately serializes requests so readers never observe a
state that might still roll back. Run exactly one active runtime per snapshot
namespace; a competing writer is rejected by generation CAS and requires an
operator-controlled restart. Higher-throughput deployments should replace the
interface with an audited transactional database preserving the same
commit-before-ACK and rollback properties.

The portable POSIX verifier accepts only an actual owner-rwx directory with no
group/other mode bits. It intentionally rejects Windows; a Windows launcher
must provide a native effective-ACL/reparse-point verifier. Dart can flush file
contents and rename within one directory, but its portable API cannot fsync the
containing directory or prove platform backup, indexing, data-protection and
full-disk-encryption policy. Production adapters must supply and fault-test
those OS guarantees. Protector keys must live in an OS credential/keystore
facility and never beside snapshot files.

The first snapshot commit and saving its newly generated owner credential in an
OS keystore are not one atomic transaction in this reference implementation. A
production launcher must provide a recoverable bootstrap protocol so a crash in
that gap cannot leave a committed server whose owner credential was lost.

The profile deliberately reports `key_transparency_enabled: false`: this
reference server has no authenticated device-key lookup or inclusion-proof
route. Production clients must fail closed until a separately pinned key
transparency service and rollback-resistant client monitor are integrated.

Run its isolated checks from the workspace root:

```text
dart analyze packages/homeserver_runtime
dart test packages/homeserver_runtime
```
