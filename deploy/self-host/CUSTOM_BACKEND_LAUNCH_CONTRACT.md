# Custom `/v1` homeserver secure-launch contract

`deploy/self-host` is a hardened **Matrix reference only**. The Flutter clients
use the repository's custom `/v1` contract, so this Compose stack is not their
backend. Caddy deliberately returns `503` for `/v1/*`; no release process may
reinterpret the Synapse service as an implementation of that API.

A future `app_homeserver` launcher may be connected only after every condition
below is implemented and independently reviewed.

## Exact process and network boundary

- The service name is `app_homeserver`; it listens on internal port `8080` and
  has no host-published port.
- It receives a fixed RFC1918/ULA address on an internal-only proxy network.
  Caddy also receives a fixed address on that network. Dynamic container DNS or
  a broad subnet is not accepted as peer authorization.
- The launcher constructs `HomeserverListenerPolicy.privateReverseProxy` with
  the exact internal bind address, Caddy's exact peer address, and the exact
  external `Host` value. Wildcard/public binds and wildcard Host values remain
  impossible.
- Caddy removes any client-supplied
  `X-Private-Homeserver-Proxy-Authorization`, injects
  `PrivateProxy {file./run/secrets/app_proxy_credential}` from a protected
  secret mount, and supplies exactly one `X-Forwarded-Proto: https` value.
  The credential file is written without a trailing newline, is never an
  environment variable, and is independently generated with at least 256 bits.
- Only `/healthz` and the reviewed `/v1/*` routes are forwarded. The active
  health check sends the same Host, proxy credential and HTTPS-forwarding
  evidence; otherwise the runtime correctly returns `403`.
- Caddy-to-runtime cleartext is permitted only on the isolated internal bridge.
  The runtime container has no frontend network and no direct internet egress.

## Mandatory persistence and identity boundary

The launcher must refuse to bind its listener until all dependencies below are
available. There is no development fallback in a release build.

- `SecurePersistenceSnapshotProtector` receives a `SecureRecordKeyProvider`
  backed by an OS keystore, TPM/HSM, or authenticated external secret service.
  Passwords, environment variables, Compose secrets mounted as plaintext key
  files, and files beside the snapshot directory are forbidden key providers.
- `PrivateAtomicSnapshotStore` receives a `SecureGenerationAnchor` kept outside
  both the snapshot directory and its backup/restore domain. The anchor must
  atomically increase and never decrease. An unavailable or regressed anchor
  prevents startup and commits.
- The snapshot directory passes the POSIX owner-only verifier, or a separately
  reviewed native ACL/reparse-point verifier. The selected adapter must also
  prove directory-fsync, backup exclusion and power-loss behavior.
- Initial owner-token persistence and the first snapshot commit use a
  recoverable bootstrap transaction. The service never starts in a state where
  a committed owner exists but its credential was lost.
- Registration uses `Ed25519DeviceProofVerifier` in a terminable,
  resource-bounded worker. It has no `(_) => true` or in-process test fallback.
- The launcher image is pinned by immutable registry digest, uses a read-only
  root filesystem, a non-root UID, dropped capabilities, bounded memory/PIDs,
  and a signed SBOM/provenance statement.

## Evidence required before changing the marker

`backend-profile.yaml` must remain `release_eligible: false` until CI has all of
the following evidence: launcher source and tests; external key-provider and
generation-anchor integration tests; rollback, disk-full, crash and restore
tests; proxy peer/Host/header negative tests; packet capture proving no public
cleartext listener; two-device `/v1` interoperability; and an independent
security review. Only then may a reviewed change add the service and replace
the deliberate `/v1` `503` route.
