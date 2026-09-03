# Third-party notices

This repository references or depends on third-party projects. Their licenses and trademarks remain their own; the root Apache-2.0 license does not replace them.

| Component | How used | Upstream license/source |
|---|---|---|
| Flutter and Dart | client framework/toolchain | Flutter/Dart upstream notices and licenses |
| `cryptography` for Dart | provisional client-side attachment AEAD implementation | Apache-2.0, <https://pub.dev/packages/cryptography> |
| `crypto` for Dart | SHA-256 integrity and commitment hashing | BSD-3-Clause, <https://pub.dev/packages/crypto> |
| Matrix specification | interoperability target | <https://spec.matrix.org/> |
| Element Synapse | optional self-hosted homeserver container | AGPLv3 or a separate commercial license as stated at <https://github.com/element-hq/synapse> |
| PostgreSQL | reference database container | PostgreSQL License, <https://www.postgresql.org/about/licence/> |
| Caddy | reference TLS reverse-proxy container | Apache-2.0, <https://github.com/caddyserver/caddy> |

The image tags in `.env.example` are review baselines, not a promise that a particular release remains current or supported. Operators must verify the selected image digest, current license, security notices, source offer obligations, and trademark terms before each release or deployment. `scripts/generate-sbom.ps1` creates a deterministic CycloneDX inventory from the locked pub dependencies. The SBOM records package hashes and dependency scope, but it does not infer licenses; release owners must still complete and review the license inventory described in [open-source-governance.md](docs/open-source-governance.md).

No blockchain client or smart-contract runtime is currently bundled. Any future optional key-transparency checkpoint anchor must add its exact dependency, license and source here before release; it must not place messages, files, keys or identifiers on-chain.

KakaoTalk, Kakao, Slack, Matrix, Element and other referenced names are used only to describe compatibility, research context, or independent upstream projects. No affiliation or endorsement is claimed.

The Mori, Lulu, Bobo, Toto, Nuri and Duri mascot artwork in this repository was created specifically for this project; no KakaoTalk or Slack artwork is bundled. This statement is not trademark clearance. The release owner must complete name/logo similarity review in intended jurisdictions before public branding or merchandise use.
