## 0.1.0

- Add atomic transactional outbox state transitions.
- Add idempotent retry, reconnect backoff, and process-restart recovery.
- Add cursor inbox synchronization, duplicate suppression, and strict
  per-conversation ordering.
- Add queued-send and cooperative cycle cancellation.
- Add aggregate, redacted diagnostics.
- Add explicit outbox/inbound/conversation/acknowledgement capacity limits and
  fail-closed snapshot restore validation.
- Reject receipt event-ID/sequence reuse and transport pages above the requested
  limit.
- Release transport-prepared exact request bytes only after a durable terminal
  outbox transition, with idempotent restart reconciliation.
