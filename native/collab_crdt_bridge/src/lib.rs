//! Bounded, app-owned collaborative document CRDT core.

#![deny(unsafe_code)]

mod engine;

pub use engine::*;

/// Automerge version pinned by this bridge.
pub const AUTOMERGE_VERSION: &str = "0.12.0";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dependency_identity_is_explicit() {
        assert_eq!(AUTOMERGE_VERSION, "0.12.0");
    }
}
