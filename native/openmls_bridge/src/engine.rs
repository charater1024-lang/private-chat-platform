use std::collections::HashMap;

use openmls::prelude::*;
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::OpenMlsProvider;
use thiserror::Error;
use tls_codec::{Deserialize, Serialize};
use zeroize::Zeroize;

const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_CHACHA20POLY1305_SHA256_Ed25519;
const MAX_IDENTITY_BYTES: usize = 256;
const MIN_GROUP_ID_BYTES: usize = 16;
const MAX_GROUP_ID_BYTES: usize = 128;
const MAX_KEY_PACKAGE_BYTES: usize = 64 * 1024;
const MAX_WELCOME_BYTES: usize = 2 * 1024 * 1024;
const MAX_MESSAGE_BYTES: usize = 2 * 1024 * 1024;
const MAX_PLAINTEXT_BYTES: usize = 1024 * 1024;
const MAX_AAD_BYTES: usize = 4096;

/// Sanitized bridge failures. Underlying cryptographic errors are never
/// returned across an eventual FFI boundary.
#[derive(Clone, Copy, Debug, Error, PartialEq, Eq)]
pub enum BridgeError {
    #[error("invalid bounded input")]
    InvalidInput,
    #[error("group already exists")]
    GroupAlreadyExists,
    #[error("group was not found")]
    GroupNotFound,
    #[error("group has an incompatible pending operation")]
    GroupStateConflict,
    #[error("cryptographic authentication failed")]
    AuthenticationFailed,
    #[error("unsupported MLS content")]
    UnsupportedContent,
    #[error("cryptographic provider failure")]
    CryptographicFailure,
}

/// Commit and Welcome bytes created while the sender's group remains in the
/// OpenMLS pending-commit state. The caller must durably enqueue [commit] and
/// only then call [`MlsClient::confirm_pending_commit`].
#[must_use = "the commit and Welcome must be durably delivered or the pending operation cleared"]
#[derive(Debug)]
pub struct PreparedMemberAdd {
    pub commit: Vec<u8>,
    pub welcome: Vec<u8>,
}

/// Authenticated application data returned only after OpenMLS has verified and
/// decrypted an MLS PrivateMessage.
#[must_use = "authenticated plaintext must be handled or explicitly discarded"]
#[derive(Debug, PartialEq, Eq)]
pub struct InboundApplicationMessage {
    pub authenticated_data: Vec<u8>,
    pub plaintext: Vec<u8>,
}

impl Drop for InboundApplicationMessage {
    fn drop(&mut self) {
        self.authenticated_data.zeroize();
        self.plaintext.zeroize();
    }
}

/// One device-local MLS client.
///
/// OpenMLS state currently lives in its in-memory provider. This type is not
/// exported over C FFI until that provider is replaced by crash-safe encrypted
/// persistence. Native tests exercise the real RFC 9420 implementation now,
/// while release checks continue to fail closed for application wiring.
pub struct MlsClient {
    provider: OpenMlsRustCrypto,
    signer: SignatureKeyPair,
    credential: CredentialWithKey,
    groups: HashMap<Vec<u8>, MlsGroup>,
    pending_inbound_commits: HashMap<Vec<u8>, Box<StagedCommit>>,
}

impl MlsClient {
    pub fn new(identity: &[u8]) -> Result<Self, BridgeError> {
        if identity.is_empty() || identity.len() > MAX_IDENTITY_BYTES {
            return Err(BridgeError::InvalidInput);
        }
        let provider = OpenMlsRustCrypto::default();
        let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm())
            .map_err(|_| BridgeError::CryptographicFailure)?;
        signer
            .store(provider.storage())
            .map_err(|_| BridgeError::CryptographicFailure)?;
        let credential = CredentialWithKey {
            credential: BasicCredential::new(identity.to_vec()).into(),
            signature_key: signer.to_public_vec().into(),
        };
        Ok(Self {
            provider,
            signer,
            credential,
            groups: HashMap::new(),
            pending_inbound_commits: HashMap::new(),
        })
    }

    /// Creates and stores the private init material, returning only the public
    /// validated KeyPackage wire representation.
    pub fn generate_key_package(&self) -> Result<Vec<u8>, BridgeError> {
        let bundle = KeyPackage::builder()
            .build(
                CIPHERSUITE,
                &self.provider,
                &self.signer,
                self.credential.clone(),
            )
            .map_err(|_| BridgeError::CryptographicFailure)?;
        let encoded = bundle
            .key_package()
            .tls_serialize_detached()
            .map_err(|_| BridgeError::CryptographicFailure)?;
        if encoded.is_empty() || encoded.len() > MAX_KEY_PACKAGE_BYTES {
            return Err(BridgeError::InvalidInput);
        }
        Ok(encoded)
    }

    pub fn create_group(&mut self, group_id: &[u8]) -> Result<(), BridgeError> {
        validate_group_id(group_id)?;
        if self.groups.contains_key(group_id) {
            return Err(BridgeError::GroupAlreadyExists);
        }
        let group = MlsGroup::new_with_group_id(
            &self.provider,
            &self.signer,
            &group_create_config(),
            GroupId::from_slice(group_id),
            self.credential.clone(),
        )
        .map_err(|_| BridgeError::CryptographicFailure)?;
        self.groups.insert(group_id.to_vec(), group);
        Ok(())
    }

    /// Validates an externally supplied KeyPackage before constructing a
    /// membership commit. The local group remains pending until explicitly
    /// confirmed after durable delivery-service acceptance.
    pub fn prepare_add_member(
        &mut self,
        group_id: &[u8],
        key_package_bytes: &[u8],
    ) -> Result<PreparedMemberAdd, BridgeError> {
        if key_package_bytes.is_empty() || key_package_bytes.len() > MAX_KEY_PACKAGE_BYTES {
            return Err(BridgeError::InvalidInput);
        }
        let key_package_in = KeyPackageIn::tls_deserialize_exact(key_package_bytes)
            .map_err(|_| BridgeError::InvalidInput)?;
        let key_package = key_package_in
            .validate(self.provider.crypto(), ProtocolVersion::Mls10)
            .map_err(|_| BridgeError::AuthenticationFailed)?;
        validate_group_id(group_id)?;
        if self.pending_inbound_commits.contains_key(group_id) {
            return Err(BridgeError::GroupStateConflict);
        }
        let provider = &self.provider;
        let signer = &self.signer;
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or(BridgeError::GroupNotFound)?;
        if group.pending_commit().is_some() {
            return Err(BridgeError::GroupStateConflict);
        }
        let (commit, welcome, _) = group
            .add_members(provider, signer, &[key_package])
            .map_err(|_| BridgeError::CryptographicFailure)?;
        let mut commit = match commit.tls_serialize_detached() {
            Ok(commit) => commit,
            Err(_) => {
                group
                    .clear_pending_commit(provider.storage())
                    .map_err(|_| BridgeError::CryptographicFailure)?;
                return Err(BridgeError::CryptographicFailure);
            }
        };
        let mut welcome = match welcome.tls_serialize_detached() {
            Ok(welcome) => welcome,
            Err(_) => {
                commit.zeroize();
                group
                    .clear_pending_commit(provider.storage())
                    .map_err(|_| BridgeError::CryptographicFailure)?;
                return Err(BridgeError::CryptographicFailure);
            }
        };
        if commit.is_empty()
            || commit.len() > MAX_MESSAGE_BYTES
            || welcome.is_empty()
            || welcome.len() > MAX_WELCOME_BYTES
        {
            commit.zeroize();
            welcome.zeroize();
            group
                .clear_pending_commit(provider.storage())
                .map_err(|_| BridgeError::CryptographicFailure)?;
            return Err(BridgeError::InvalidInput);
        }
        Ok(PreparedMemberAdd { commit, welcome })
    }

    pub fn confirm_pending_commit(&mut self, group_id: &[u8]) -> Result<(), BridgeError> {
        validate_group_id(group_id)?;
        if self.pending_inbound_commits.contains_key(group_id) {
            return Err(BridgeError::GroupStateConflict);
        }
        let provider = &self.provider;
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or(BridgeError::GroupNotFound)?;
        if group.pending_commit().is_none() {
            return Err(BridgeError::GroupStateConflict);
        }
        group
            .merge_pending_commit(provider)
            .map_err(|_| BridgeError::CryptographicFailure)
    }

    pub fn clear_pending_commit(&mut self, group_id: &[u8]) -> Result<(), BridgeError> {
        validate_group_id(group_id)?;
        let storage = self.provider.storage();
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or(BridgeError::GroupNotFound)?;
        if group.pending_commit().is_none() {
            return Err(BridgeError::GroupStateConflict);
        }
        group
            .clear_pending_commit(storage)
            .map_err(|_| BridgeError::CryptographicFailure)
    }

    pub fn join_from_welcome(&mut self, welcome_bytes: &[u8]) -> Result<Vec<u8>, BridgeError> {
        if welcome_bytes.is_empty() || welcome_bytes.len() > MAX_WELCOME_BYTES {
            return Err(BridgeError::InvalidInput);
        }
        let wire = MlsMessageIn::tls_deserialize_exact(welcome_bytes)
            .map_err(|_| BridgeError::InvalidInput)?;
        let welcome = match wire.extract() {
            MlsMessageBodyIn::Welcome(welcome) => welcome,
            _ => return Err(BridgeError::InvalidInput),
        };
        let staged =
            StagedWelcome::new_from_welcome(&self.provider, &group_join_config(), welcome, None)
                .map_err(|_| BridgeError::AuthenticationFailed)?;
        let group_id = staged.group_context().group_id().as_slice().to_vec();
        validate_group_id(&group_id)?;
        if self.groups.contains_key(&group_id) {
            return Err(BridgeError::GroupAlreadyExists);
        }
        // `into_group` persists through the provider. Rejecting a duplicate
        // only afterwards could replace the durable state behind the existing
        // in-memory group with a different, attacker-supplied branch.
        let group = staged
            .into_group(&self.provider)
            .map_err(|_| BridgeError::CryptographicFailure)?;
        self.groups.insert(group_id.clone(), group);
        Ok(group_id)
    }

    pub fn encrypt(
        &mut self,
        group_id: &[u8],
        authenticated_data: &[u8],
        plaintext: &[u8],
    ) -> Result<Vec<u8>, BridgeError> {
        if plaintext.is_empty()
            || plaintext.len() > MAX_PLAINTEXT_BYTES
            || authenticated_data.len() > MAX_AAD_BYTES
        {
            return Err(BridgeError::InvalidInput);
        }
        validate_group_id(group_id)?;
        let provider = &self.provider;
        let signer = &self.signer;
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or(BridgeError::GroupNotFound)?;
        if group.pending_commit().is_some() {
            return Err(BridgeError::GroupStateConflict);
        }
        group.set_aad(authenticated_data.to_vec());
        group
            .create_message(provider, signer, plaintext)
            .map_err(|_| BridgeError::CryptographicFailure)?
            .tls_serialize_detached()
            .map_err(|_| BridgeError::CryptographicFailure)
    }

    /// Processes one delivery-service frame. Application plaintext is returned
    /// only for an authenticated application message. A membership commit is
    /// staged internally and requires a separate authorization/merge call.
    pub fn process_incoming(
        &mut self,
        group_id: &[u8],
        message_bytes: &[u8],
    ) -> Result<Option<InboundApplicationMessage>, BridgeError> {
        if message_bytes.is_empty() || message_bytes.len() > MAX_MESSAGE_BYTES {
            return Err(BridgeError::InvalidInput);
        }
        if self.pending_inbound_commits.contains_key(group_id) {
            return Err(BridgeError::GroupStateConflict);
        }
        let wire = MlsMessageIn::tls_deserialize_exact(message_bytes)
            .map_err(|_| BridgeError::InvalidInput)?;
        let protocol_message = wire
            .try_into_protocol_message()
            .map_err(|_| BridgeError::InvalidInput)?;
        if matches!(
            &protocol_message,
            ProtocolMessage::PrivateMessage(message) if message.aad().len() > MAX_AAD_BYTES
        ) {
            return Err(BridgeError::InvalidInput);
        }
        validate_group_id(group_id)?;
        let provider = &self.provider;
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or(BridgeError::GroupNotFound)?;
        let processed = group
            .process_message(provider, protocol_message)
            .map_err(|_| BridgeError::AuthenticationFailed)?;
        let mut aad = processed.aad().to_vec();
        if aad.len() > MAX_AAD_BYTES {
            aad.zeroize();
            return Err(BridgeError::InvalidInput);
        }
        match processed.into_content() {
            ProcessedMessageContent::ApplicationMessage(message) => {
                let mut plaintext = message.into_bytes();
                if plaintext.is_empty() || plaintext.len() > MAX_PLAINTEXT_BYTES {
                    plaintext.zeroize();
                    aad.zeroize();
                    return Err(BridgeError::InvalidInput);
                }
                Ok(Some(InboundApplicationMessage {
                    authenticated_data: aad,
                    plaintext,
                }))
            }
            ProcessedMessageContent::StagedCommitMessage(commit) => {
                if group.pending_commit().is_some() {
                    return Err(BridgeError::GroupStateConflict);
                }
                self.pending_inbound_commits
                    .insert(group_id.to_vec(), commit);
                Ok(None)
            }
            // Receipt of our own Commit proves only that the delivery service
            // echoed the frame. The caller still has to durably advance its
            // cursor/outbox state before explicitly merging the pending epoch.
            ProcessedMessageContent::OwnPendingCommit => Ok(None),
            ProcessedMessageContent::OwnPrivateMessage => Ok(None),
            _ => Err(BridgeError::UnsupportedContent),
        }
    }

    /// Merges a previously authenticated inbound Commit only after the app has
    /// authorized its membership changes and durably advanced its server
    /// cursor.
    pub fn confirm_inbound_commit(&mut self, group_id: &[u8]) -> Result<(), BridgeError> {
        validate_group_id(group_id)?;
        let group = self
            .groups
            .get(group_id)
            .ok_or(BridgeError::GroupNotFound)?;
        if group.pending_commit().is_some() {
            return Err(BridgeError::GroupStateConflict);
        }
        if !self.pending_inbound_commits.contains_key(group_id) {
            return Err(BridgeError::GroupStateConflict);
        }
        let commit = self
            .pending_inbound_commits
            .remove(group_id)
            .ok_or(BridgeError::GroupStateConflict)?;
        let provider = &self.provider;
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or(BridgeError::GroupNotFound)?;
        group
            .merge_staged_commit(provider, *commit)
            .map_err(|_| BridgeError::CryptographicFailure)
    }

    pub fn member_count(&self, group_id: &[u8]) -> Result<usize, BridgeError> {
        validate_group_id(group_id)?;
        self.groups
            .get(group_id)
            .map(|group| group.members().count())
            .ok_or(BridgeError::GroupNotFound)
    }
}

impl Drop for MlsClient {
    fn drop(&mut self) {
        // OpenMLS and the credential provider zeroize their dedicated secret
        // types. Clearing map keys avoids retaining app-level group identifiers
        // in this wrapper after teardown.
        for (mut group_id, _) in std::mem::take(&mut self.groups) {
            group_id.zeroize();
        }
        for (mut group_id, _) in std::mem::take(&mut self.pending_inbound_commits) {
            group_id.zeroize();
        }
    }
}

fn validate_group_id(group_id: &[u8]) -> Result<(), BridgeError> {
    if group_id.len() < MIN_GROUP_ID_BYTES || group_id.len() > MAX_GROUP_ID_BYTES {
        return Err(BridgeError::InvalidInput);
    }
    Ok(())
}

fn group_create_config() -> MlsGroupCreateConfig {
    MlsGroupCreateConfig::builder()
        .ciphersuite(CIPHERSUITE)
        .wire_format_policy(PURE_CIPHERTEXT_WIRE_FORMAT_POLICY)
        .padding_size(256)
        .sender_ratchet_configuration(SenderRatchetConfiguration::new(32, 2048))
        .max_past_epochs(1)
        .use_ratchet_tree_extension(true)
        .build()
}

fn group_join_config() -> MlsGroupJoinConfig {
    MlsGroupJoinConfig::builder()
        .wire_format_policy(PURE_CIPHERTEXT_WIRE_FORMAT_POLICY)
        .padding_size(256)
        .sender_ratchet_configuration(SenderRatchetConfiguration::new(32, 2048))
        .max_past_epochs(1)
        .use_ratchet_tree_extension(true)
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    const GROUP_ID: &[u8] = b"privacy-chat-group-0001";
    const AAD: &[u8] = b"private-chat/message/v1|conversation-01|sequence-1";

    fn paired_clients() -> (MlsClient, MlsClient) {
        let mut alice = MlsClient::new(b"alice-device-01").unwrap();
        let mut bob = MlsClient::new(b"bob-device-01").unwrap();
        let bob_key_package = bob.generate_key_package().unwrap();
        alice.create_group(GROUP_ID).unwrap();
        let prepared = alice
            .prepare_add_member(GROUP_ID, &bob_key_package)
            .unwrap();
        alice.confirm_pending_commit(GROUP_ID).unwrap();
        assert_eq!(bob.join_from_welcome(&prepared.welcome).unwrap(), GROUP_ID);
        assert_eq!(alice.member_count(GROUP_ID).unwrap(), 2);
        assert_eq!(bob.member_count(GROUP_ID).unwrap(), 2);
        (alice, bob)
    }

    #[test]
    fn real_openmls_round_trip_authenticates_aad_and_hides_plaintext() {
        let (mut alice, mut bob) = paired_clients();
        let mut plaintext = b"sensitive message from alice".to_vec();
        let wire = alice.encrypt(GROUP_ID, AAD, &plaintext).unwrap();

        assert!(!wire
            .windows(plaintext.len())
            .any(|window| window == plaintext));
        let opened = bob
            .process_incoming(GROUP_ID, &wire)
            .unwrap()
            .expect("application message");
        assert_eq!(opened.authenticated_data, AAD);
        assert_eq!(opened.plaintext, plaintext);

        plaintext.zeroize();
        assert!(plaintext.iter().all(|byte| *byte == 0));
    }

    #[test]
    fn replay_and_tampering_fail_closed() {
        let (mut alice, mut bob) = paired_clients();
        let wire = alice.encrypt(GROUP_ID, AAD, b"one time").unwrap();
        assert!(bob.process_incoming(GROUP_ID, &wire).unwrap().is_some());
        assert_eq!(
            bob.process_incoming(GROUP_ID, &wire),
            Err(BridgeError::AuthenticationFailed)
        );

        let fresh = alice.encrypt(GROUP_ID, AAD, b"tamper me").unwrap();
        let mut tampered = fresh;
        let middle = tampered.len() / 2;
        tampered[middle] ^= 1;
        assert_eq!(
            bob.process_incoming(GROUP_ID, &tampered),
            Err(BridgeError::AuthenticationFailed)
        );
    }

    #[test]
    fn membership_commit_stays_pending_until_confirmed() {
        let mut alice = MlsClient::new(b"alice-device-01").unwrap();
        let bob = MlsClient::new(b"bob-device-01").unwrap();
        alice.create_group(GROUP_ID).unwrap();
        let prepared = alice
            .prepare_add_member(GROUP_ID, &bob.generate_key_package().unwrap())
            .unwrap();

        assert!(!prepared.commit.is_empty());
        assert!(!prepared.welcome.is_empty());
        assert_eq!(alice.member_count(GROUP_ID).unwrap(), 1);
        assert_eq!(
            alice.encrypt(GROUP_ID, AAD, b"must wait for commit ACK"),
            Err(BridgeError::GroupStateConflict)
        );
        alice.confirm_pending_commit(GROUP_ID).unwrap();
        assert_eq!(alice.member_count(GROUP_ID).unwrap(), 2);
    }

    #[test]
    fn echoed_own_commit_does_not_merge_before_durable_confirmation() {
        let mut alice = MlsClient::new(b"alice-device-01").unwrap();
        let bob = MlsClient::new(b"bob-device-01").unwrap();
        alice.create_group(GROUP_ID).unwrap();
        let prepared = alice
            .prepare_add_member(GROUP_ID, &bob.generate_key_package().unwrap())
            .unwrap();

        assert_eq!(alice.process_incoming(GROUP_ID, &prepared.commit), Ok(None));
        assert_eq!(alice.member_count(GROUP_ID).unwrap(), 1);
        assert_eq!(
            alice.encrypt(GROUP_ID, AAD, b"must wait for durable cursor"),
            Err(BridgeError::GroupStateConflict)
        );

        alice.confirm_pending_commit(GROUP_ID).unwrap();
        assert_eq!(alice.member_count(GROUP_ID).unwrap(), 2);
    }

    #[test]
    fn duplicate_group_welcome_is_rejected_before_provider_state_is_replaced() {
        let mut alice = MlsClient::new(b"alice-device-01").unwrap();
        let mut bob = MlsClient::new(b"bob-device-01").unwrap();
        alice.create_group(GROUP_ID).unwrap();
        let first = alice
            .prepare_add_member(GROUP_ID, &bob.generate_key_package().unwrap())
            .unwrap();
        alice.confirm_pending_commit(GROUP_ID).unwrap();
        assert_eq!(bob.join_from_welcome(&first.welcome).unwrap(), GROUP_ID);

        // A different valid group can deliberately reuse the public group id.
        // Joining it must not persist over Bob's already active group state.
        let mut mallory = MlsClient::new(b"mallory-device-01").unwrap();
        mallory.create_group(GROUP_ID).unwrap();
        let conflicting = mallory
            .prepare_add_member(GROUP_ID, &bob.generate_key_package().unwrap())
            .unwrap();
        mallory.confirm_pending_commit(GROUP_ID).unwrap();
        assert_eq!(
            bob.join_from_welcome(&conflicting.welcome),
            Err(BridgeError::GroupAlreadyExists)
        );

        let wire = alice
            .encrypt(GROUP_ID, AAD, b"original branch remains usable")
            .unwrap();
        let opened = bob
            .process_incoming(GROUP_ID, &wire)
            .unwrap()
            .expect("application message");
        assert_eq!(opened.plaintext, b"original branch remains usable");
    }

    #[test]
    fn staged_inbound_commit_blocks_competing_outbound_epoch_change() {
        let (mut alice, mut bob) = paired_clients();
        let charlie = MlsClient::new(b"charlie-device-01").unwrap();
        let prepared = alice
            .prepare_add_member(GROUP_ID, &charlie.generate_key_package().unwrap())
            .unwrap();
        alice.confirm_pending_commit(GROUP_ID).unwrap();
        assert_eq!(bob.process_incoming(GROUP_ID, &prepared.commit), Ok(None));

        let dave = MlsClient::new(b"dave-device-01").unwrap();
        assert_eq!(
            bob.prepare_add_member(GROUP_ID, &dave.generate_key_package().unwrap()),
            Err(BridgeError::GroupStateConflict)
        );
        assert_eq!(bob.member_count(GROUP_ID).unwrap(), 2);

        // The rejected outbound operation must not consume the staged commit.
        bob.confirm_inbound_commit(GROUP_ID).unwrap();
        assert_eq!(bob.member_count(GROUP_ID).unwrap(), 3);
    }

    #[test]
    fn malformed_key_package_is_rejected_before_group_mutation() {
        let mut alice = MlsClient::new(b"alice-device-01").unwrap();
        alice.create_group(GROUP_ID).unwrap();
        assert!(matches!(
            alice.prepare_add_member(GROUP_ID, b"not a key package"),
            Err(BridgeError::InvalidInput)
        ));
        assert_eq!(alice.member_count(GROUP_ID).unwrap(), 1);
    }
}
