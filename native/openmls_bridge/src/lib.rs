//! Narrow, app-owned OpenMLS bridge.
//!
//! The Rust state machine is kept behind typed operations that preserve MLS
//! pending-commit ordering. A C ABI is exposed only after crash-safe encrypted
//! persistence is available, avoiding an in-memory prototype being mistaken
//! for production E2EE.

#![deny(unsafe_code)]

mod engine;

pub use engine::{BridgeError, InboundApplicationMessage, MlsClient, PreparedMemberAdd};

/// OpenMLS version pinned by this bridge.
pub const OPENMLS_VERSION: &str = "0.9.2";

/// Protocol implemented by the pinned dependency.
pub const PROTOCOL: &str = "MLS 1.0 / RFC 9420";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dependency_identity_is_explicit() {
        assert_eq!(OPENMLS_VERSION, "0.9.2");
        assert_eq!(PROTOCOL, "MLS 1.0 / RFC 9420");
    }
}
