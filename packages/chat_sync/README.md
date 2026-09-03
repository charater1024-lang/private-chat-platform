# chat_sync

Pure-Dart durable synchronization for opaque, already-encrypted chat
envelopes. The package is shared by the consumer and collaboration clients.

This is deliberately **not** a cryptographic or networking implementation. It
does not create message keys, encrypt plaintext, authenticate users, open HTTP
connections, or trust a server certificate. Platform code supplies:

- an `AuthenticatedSyncTransport` whose private adapter owns credentials and
  verifies the selected home server;
- a `SyncSnapshotStore` that atomically replaces snapshots with a generation
  compare-and-swap, preferably in encrypted device storage;
- ciphertext produced and authenticated by the product's E2EE layer.

## Reliability model

An enqueue is durable before it becomes eligible for network use. Sending uses
these persisted transitions:

```text
queued -> sending -> acknowledged
   |          |
   |          +-> queued (ambiguous/transient failure, same idempotency key)
   +-> cancelled
   +-> permanentlyFailed (explicit non-retryable rejection)
```

If a process stops in `sending`, `ChatSyncEngine.restore` returns the entry to
`queued`. The transport must use `clientMessageId` as a server-side idempotency
key and return the original receipt for an exact retry. This covers both
request loss and the harder case where the server committed but its ACK was
lost.

Only the head of each conversation is eligible to send. A delayed head blocks
later messages in that conversation, while independent conversations continue.
Reconnect and send deadlines use bounded exponential backoff and are persisted
across restarts. The engine does not create hidden timers: the application
schedules another `runCycle` using `SyncCycleResult.nextNetworkActionAt` or a
trusted push/connectivity signal.

## Cursor and inbox model

Each pull atomically stores the new opaque cursor together with received
ciphertext. Events are deduplicated by stable server event id and ordered by a
strict per-conversation sequence. Gaps are buffered. The app reads at most the
next event for each conversation with `readDeliverable`, commits it to its own
message database, and then calls `acknowledgeInbound`. Until that acknowledgement
is durable, the event remains deliverable (at-least-once local delivery).

A stale cursor can request a full replay or a trusted recovery cursor. Already
acknowledged sequences are suppressed, so replay does not recreate messages.
Conflicting event ids/content at a known event or sequence fail closed.

## Capacity and receipt integrity

The engine defaults to 4,096 outbox entries / 64 MiB outbox ciphertext, 10,000
buffered inbound events / 64 MiB inbound ciphertext, 4,096 tracked
conversations, and 2,048 recent acknowledgement markers. It validates the same
limits while restoring a snapshot. Outbox overflow rejects enqueue atomically;
inbound overflow blocks the cycle without advancing its cursor. If a transport
implements `TerminalSendPreparationCleaner`, the engine releases its exact-byte
prepared request only after the terminal outbox state is durably committed and
retries idempotent cleanup at the start of later cycles, including after a
restart. Applications must still explicitly prune terminal outbox rows only
after their durable message database and transport-preparation records have
been reconciled.

Send receipts cannot reuse a server event ID or a conversation sequence already
bound to a different send/inbound event. A transport page containing more events
than requested is also rejected as a protocol violation. These finite client
indexes complement rather than replace UNIQUE constraints in the durable server
database.

## Cancellation

`cancel` durably cancels a queued entry. Once an adapter has begun a send, the
engine returns `tooLateInFlight`: the server may already have committed and an
"unsend" promise would be unsafe. `SyncCancellationToken` stops a cycle between
network operations. It never pretends that an already-started request was not
accepted.

## Logging and persistence

Model and exception `toString` implementations redact ciphertext, ids, cursors,
receipts, and adapter details. `SyncDiagnostics` contains aggregate counts only.
Raw transport exceptions are converted to fixed failure kinds.

`SyncStateSnapshot.toJson` is **not** a diagnostic representation. It must
contain ciphertext and opaque routing metadata so work can resume after a
crash; store it securely and never send it to logs or crash analytics.

## Adapter contract checklist

- Keep bearer tokens, cookies, private keys, signed URLs, and TLS details inside
  the adapter.
- Authenticate every call and pin/verify the intended home-server identity.
- Enforce exact idempotency: same client id plus same request returns the same
  receipt; conflicting reuse is rejected.
- Give each conversation a contiguous sequence beginning with 1 in a full
  replay and return stable server event ids.
- Treat cursors as opaque and return `staleCursor` with a safe recovery point
  when history compaction invalidates one.
- Bound response sizes before constructing a `SyncPage`; the engine additionally
  caps its persisted inbound buffer.
