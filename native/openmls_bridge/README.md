# App-owned OpenMLS bridge

This native crate is the only permitted implementation boundary for message
E2EE. It pins stable OpenMLS `0.9.2` and Rust `1.91`; release-candidate,
floating Git and hosted prebuilt crypto binaries are forbidden.

The public ABI remains unavailable until native tests cover group creation,
invitation, membership changes, application-message round trips, replay
rejection, pending-commit ordering, past-epoch deletion and crash-safe
encrypted state persistence. A partial FFI wrapper would create a false
security claim.

No server, Dart package or UI may label a message as MLS merely because this
crate exists. Release validation must require a built, signed bridge and the
full interop/vector/fuzz evidence described in
`docs/adr/0001-e2ee-protocol.md`.
