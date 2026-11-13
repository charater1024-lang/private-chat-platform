use std::collections::{BTreeSet, HashSet};
use std::fmt;
use std::mem;

use automerge::transaction::Transactable;
use automerge::{
    ActorId, AutoCommit, Change, ChangeHash, LoadOptions, ObjType, ReadDoc, TextEncoding, Value,
    ROOT,
};
use thiserror::Error;
use unicode_segmentation::UnicodeSegmentation;
use zeroize::Zeroize;

const SCHEMA_KEY: &str = "schema";
const DOCUMENT_ID_KEY: &str = "document_id";
const TITLE_KEY: &str = "title";
const BODY_KEY: &str = "body";
const SCHEMA_ID: &str = "private-chat-collab-document/v1";

/// Maximum compact Automerge snapshot accepted from an untrusted peer.
pub const MAX_SNAPSHOT_BYTES: usize = 8 * 1024 * 1024;
/// Maximum encoded Automerge change accepted in one transport item.
pub const MAX_CHANGE_BYTES: usize = 256 * 1024;
/// Maximum sum of encoded change bytes accepted atomically.
pub const MAX_CHANGE_BATCH_BYTES: usize = 2 * 1024 * 1024;
/// Maximum changes accepted atomically.
pub const MAX_CHANGES_PER_BATCH: usize = 512;
/// Maximum causal heads accepted or produced for one document.
pub const MAX_HEADS: usize = 64;
/// Maximum UTF-8 title size after a change is applied.
pub const MAX_TITLE_BYTES: usize = 1024;
/// Maximum UTF-8 body size after a change is applied.
pub const MAX_BODY_BYTES: usize = 2 * 1024 * 1024;
/// Maximum UTF-8 insertion in one local edit.
pub const MAX_INSERT_BYTES: usize = 64 * 1024;
/// Maximum accumulated CRDT operations in one loaded document.
pub const MAX_TOTAL_OPERATIONS: u64 = 2_000_000;
/// Maximum accumulated changes in one loaded document.
pub const MAX_TOTAL_CHANGES: u64 = 100_000;
/// Maximum distinct Automerge actors in one loaded document.
pub const MAX_TOTAL_ACTORS: u64 = 1024;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum DocumentError {
    #[error("document and actor identifiers must be non-zero 32-byte values")]
    InvalidIdentifier,
    #[error("the requested grapheme edit is outside the document")]
    InvalidTextRange,
    #[error("the document title exceeds its UTF-8 limit")]
    TitleTooLarge,
    #[error("the document body exceeds its UTF-8 limit")]
    BodyTooLarge,
    #[error("one local insertion exceeds its UTF-8 limit")]
    InsertionTooLarge,
    #[error("the encoded snapshot is empty, malformed, or over its limit")]
    InvalidSnapshot,
    #[error("an encoded change is empty, malformed, or over its limit")]
    InvalidChange,
    #[error("the encoded change batch is empty or over its count/byte limit")]
    InvalidChangeBatch,
    #[error("a duplicate or already-applied change was rejected")]
    DuplicateChange,
    #[error("a requested causal head is unknown, duplicated, or over its limit")]
    InvalidHeadSet,
    #[error("documents with different identifiers cannot be merged")]
    DocumentMismatch,
    #[error("the fixed collaborative-document schema was violated")]
    SchemaViolation,
    #[error("the CRDT engine rejected the operation")]
    EngineRejected,
}

/// Opaque random document identifier. It is also authenticated by the MLS AAD
/// layer; embedding it here prevents accidental cross-document merge locally.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct DocumentId([u8; 32]);

impl DocumentId {
    pub fn new(bytes: [u8; 32]) -> Result<Self, DocumentError> {
        if bytes == [0; 32] {
            return Err(DocumentError::InvalidIdentifier);
        }
        Ok(Self(bytes))
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Debug for DocumentId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("DocumentId([REDACTED])")
    }
}

/// Device-unique actor identifier. Reusing an actor concurrently is forbidden.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct DeviceActorId([u8; 32]);

impl DeviceActorId {
    pub fn new(bytes: [u8; 32]) -> Result<Self, DocumentError> {
        if bytes == [0; 32] {
            return Err(DocumentError::InvalidIdentifier);
        }
        Ok(Self(bytes))
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    fn automerge_id(self) -> ActorId {
        ActorId::from(self.0)
    }
}

impl fmt::Debug for DeviceActorId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("DeviceActorId([REDACTED])")
    }
}

/// Fixed-size causal head for the MLS-encrypted, device-signed document
/// payload. It must not be exposed as server routing metadata or put on-chain.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct DocumentHead([u8; 32]);

impl DocumentHead {
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    fn to_change_hash(self) -> ChangeHash {
        ChangeHash::try_from(self.0.as_slice()).expect("fixed-size head")
    }
}

impl fmt::Debug for DocumentHead {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("DocumentHead([REDACTED])")
    }
}

impl From<ChangeHash> for DocumentHead {
    fn from(value: ChangeHash) -> Self {
        let mut bytes = [0; 32];
        bytes.copy_from_slice(value.as_ref());
        Self(bytes)
    }
}

/// Compact plaintext CRDT snapshot. The outer application must encrypt this
/// before persistence. The owned bytes are wiped when this value is dropped.
pub struct DocumentSnapshot {
    bytes: Vec<u8>,
}

impl fmt::Debug for DocumentSnapshot {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DocumentSnapshot")
            .field("byte_length", &self.bytes.len())
            .finish()
    }
}

impl DocumentSnapshot {
    pub fn try_from_bytes(bytes: Vec<u8>) -> Result<Self, DocumentError> {
        if bytes.is_empty() || bytes.len() > MAX_SNAPSHOT_BYTES {
            return Err(DocumentError::InvalidSnapshot);
        }
        Ok(Self { bytes })
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn into_bytes(mut self) -> Vec<u8> {
        mem::take(&mut self.bytes)
    }
}

impl Drop for DocumentSnapshot {
    fn drop(&mut self) {
        self.bytes.zeroize();
    }
}

/// One compressed Automerge change. It is plaintext until the application
/// seals it as an MLS application message, so the buffer is wiped on drop.
pub struct EncodedChange {
    bytes: Vec<u8>,
}

impl fmt::Debug for EncodedChange {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("EncodedChange")
            .field("byte_length", &self.bytes.len())
            .finish()
    }
}

impl EncodedChange {
    pub fn try_from_bytes(bytes: Vec<u8>) -> Result<Self, DocumentError> {
        if bytes.is_empty() || bytes.len() > MAX_CHANGE_BYTES {
            return Err(DocumentError::InvalidChange);
        }
        Ok(Self { bytes })
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn into_bytes(mut self) -> Vec<u8> {
        mem::take(&mut self.bytes)
    }
}

impl Drop for EncodedChange {
    fn drop(&mut self) {
        self.bytes.zeroize();
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct DocumentView {
    pub document_id: DocumentId,
    pub title: String,
    pub body: String,
    pub heads: Vec<DocumentHead>,
}

impl fmt::Debug for DocumentView {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DocumentView")
            .field("document_id", &self.document_id)
            .field("title_utf8_bytes", &self.title.len())
            .field("body_utf8_bytes", &self.body.len())
            .field("head_count", &self.heads.len())
            .finish()
    }
}

/// A bounded Automerge document with a deliberately tiny fixed schema.
///
/// This type provides convergence only. Authentication, authorization,
/// confidentiality, permission epochs and replay protection belong to the
/// signed MLS transport envelope and are intentionally outside this crate.
pub struct CollaborativeDocument {
    document_id: DocumentId,
    doc: AutoCommit,
}

impl CollaborativeDocument {
    pub fn new(document_id: DocumentId, local_actor: DeviceActorId) -> Result<Self, DocumentError> {
        let mut doc = AutoCommit::new_with_encoding(TextEncoding::GraphemeCluster)
            .with_actor(local_actor.automerge_id());
        doc.put(ROOT, SCHEMA_KEY, SCHEMA_ID)
            .map_err(|_| DocumentError::EngineRejected)?;
        doc.put(ROOT, DOCUMENT_ID_KEY, document_id.0.to_vec())
            .map_err(|_| DocumentError::EngineRejected)?;
        doc.put_object(ROOT, TITLE_KEY, ObjType::Text)
            .map_err(|_| DocumentError::EngineRejected)?;
        doc.put_object(ROOT, BODY_KEY, ObjType::Text)
            .map_err(|_| DocumentError::EngineRejected)?;

        let mut result = Self { document_id, doc };
        result.validate_current_state()?;
        Ok(result)
    }

    pub fn load(
        expected_document_id: DocumentId,
        local_actor: DeviceActorId,
        snapshot: &DocumentSnapshot,
    ) -> Result<Self, DocumentError> {
        let mut doc = AutoCommit::load_with_options(
            snapshot.as_bytes(),
            LoadOptions::new().text_encoding(TextEncoding::GraphemeCluster),
        )
        .map_err(|_| DocumentError::InvalidSnapshot)?;
        doc.set_actor(local_actor.automerge_id());
        let mut result = Self {
            document_id: expected_document_id,
            doc,
        };
        result
            .validate_current_state()
            .map_err(|_| DocumentError::InvalidSnapshot)?;
        Ok(result)
    }

    pub fn document_id(&self) -> DocumentId {
        self.document_id
    }

    pub fn view(&mut self) -> Result<DocumentView, DocumentError> {
        self.validate_current_state()?;
        let title_id = self.text_object(TITLE_KEY)?;
        let body_id = self.text_object(BODY_KEY)?;
        Ok(DocumentView {
            document_id: self.document_id,
            title: self
                .doc
                .text(&title_id)
                .map_err(|_| DocumentError::EngineRejected)?,
            body: self
                .doc
                .text(&body_id)
                .map_err(|_| DocumentError::EngineRejected)?,
            heads: self.heads()?,
        })
    }

    pub fn heads(&mut self) -> Result<Vec<DocumentHead>, DocumentError> {
        let mut heads = self
            .doc
            .get_heads()
            .into_iter()
            .map(DocumentHead::from)
            .collect::<Vec<_>>();
        if heads.len() > MAX_HEADS {
            return Err(DocumentError::InvalidHeadSet);
        }
        heads.sort_unstable();
        Ok(heads)
    }

    pub fn replace_title(&mut self, title: &str) -> Result<(), DocumentError> {
        if title.len() > MAX_TITLE_BYTES {
            return Err(DocumentError::TitleTooLarge);
        }
        if title.len() > MAX_INSERT_BYTES {
            return Err(DocumentError::InsertionTooLarge);
        }
        let mut candidate = self.clone_preserving_actor();
        let title_id = candidate.text_object(TITLE_KEY)?;
        let length = candidate.doc.length(&title_id);
        candidate
            .doc
            .splice_text(&title_id, 0, length as isize, title)
            .map_err(|_| DocumentError::EngineRejected)?;
        candidate.validate_current_state()?;
        self.doc = candidate.doc;
        Ok(())
    }

    /// Applies one local edit using Unicode grapheme-cluster indexes. Korean
    /// jamo sequences and multi-code-point emoji are never split by the API.
    pub fn splice_body(
        &mut self,
        position: usize,
        delete_count: usize,
        insertion: &str,
    ) -> Result<(), DocumentError> {
        if insertion.len() > MAX_INSERT_BYTES {
            return Err(DocumentError::InsertionTooLarge);
        }
        let mut candidate = self.clone_preserving_actor();
        let body_id = candidate.text_object(BODY_KEY)?;
        let current = candidate
            .doc
            .text(&body_id)
            .map_err(|_| DocumentError::EngineRejected)?;
        let (delete_start, delete_end) = grapheme_byte_range(&current, position, delete_count)
            .ok_or(DocumentError::InvalidTextRange)?;
        let next_bytes = current
            .len()
            .checked_sub(delete_end - delete_start)
            .and_then(|size| size.checked_add(insertion.len()))
            .ok_or(DocumentError::BodyTooLarge)?;
        if next_bytes > MAX_BODY_BYTES {
            return Err(DocumentError::BodyTooLarge);
        }
        candidate
            .doc
            .splice_text(&body_id, position, delete_count as isize, insertion)
            .map_err(|_| DocumentError::EngineRejected)?;
        candidate.validate_current_state()?;
        self.doc = candidate.doc;
        Ok(())
    }

    pub fn fork_for_actor(&mut self, actor: DeviceActorId) -> Result<Self, DocumentError> {
        if self.doc.get_actor().as_ref() == actor.as_bytes() {
            return Err(DocumentError::InvalidIdentifier);
        }
        self.validate_current_state()?;
        let mut doc = self.doc.fork();
        doc.set_actor(actor.automerge_id());
        let mut result = Self {
            document_id: self.document_id,
            doc,
        };
        result.validate_current_state()?;
        Ok(result)
    }

    /// Atomically merges another valid replica. A failed schema/bounds check
    /// leaves this replica unchanged.
    pub fn merge(&mut self, other: &mut Self) -> Result<(), DocumentError> {
        if self.document_id != other.document_id {
            return Err(DocumentError::DocumentMismatch);
        }
        self.validate_current_state()?;
        other.validate_current_state()?;
        let mut candidate = self.clone_preserving_actor();
        let mut remote = other.clone_preserving_actor();
        candidate
            .doc
            .merge(&mut remote.doc)
            .map_err(|_| DocumentError::EngineRejected)?;
        candidate.validate_current_state()?;
        self.doc = candidate.doc;
        Ok(())
    }

    pub fn save(&mut self) -> Result<DocumentSnapshot, DocumentError> {
        self.validate_current_state()?;
        let bytes = self.doc.save();
        if bytes.is_empty() || bytes.len() > MAX_SNAPSHOT_BYTES {
            return Err(DocumentError::InvalidSnapshot);
        }
        DocumentSnapshot::try_from_bytes(bytes)
    }

    pub fn export_changes_since(
        &mut self,
        known_heads: &[DocumentHead],
    ) -> Result<Vec<EncodedChange>, DocumentError> {
        self.validate_current_state()?;
        let heads = self.validate_known_heads(known_heads)?;
        let changes = self.doc.get_changes(&heads);
        if changes.is_empty() {
            return Ok(Vec::new());
        }
        if changes.len() > MAX_CHANGES_PER_BATCH {
            return Err(DocumentError::InvalidChangeBatch);
        }

        let mut total = 0usize;
        let mut encoded = Vec::with_capacity(changes.len());
        for mut change in changes {
            let bytes = change.bytes().into_owned();
            if bytes.is_empty() || bytes.len() > MAX_CHANGE_BYTES {
                return Err(DocumentError::InvalidChange);
            }
            total = total
                .checked_add(bytes.len())
                .ok_or(DocumentError::InvalidChangeBatch)?;
            if total > MAX_CHANGE_BATCH_BYTES {
                return Err(DocumentError::InvalidChangeBatch);
            }
            encoded.push(EncodedChange { bytes });
        }
        Ok(encoded)
    }

    /// Atomically applies an untrusted, MLS-authenticated change batch. The
    /// caller must still check signer role, permission epoch, replay sequence,
    /// document ID and causal heads before invoking this method.
    pub fn apply_encoded_changes(
        &mut self,
        mut encoded: Vec<EncodedChange>,
    ) -> Result<(), DocumentError> {
        if encoded.is_empty() || encoded.len() > MAX_CHANGES_PER_BATCH {
            return Err(DocumentError::InvalidChangeBatch);
        }
        let total = encoded.iter().try_fold(0usize, |sum, item| {
            sum.checked_add(item.bytes.len())
                .filter(|size| *size <= MAX_CHANGE_BATCH_BYTES)
                .ok_or(DocumentError::InvalidChangeBatch)
        })?;
        if total == 0 {
            return Err(DocumentError::InvalidChangeBatch);
        }

        let mut hashes = HashSet::with_capacity(encoded.len());
        let mut changes = Vec::with_capacity(encoded.len());
        for item in &mut encoded {
            let bytes = mem::take(&mut item.bytes);
            let change = Change::from_bytes(bytes).map_err(|_| DocumentError::InvalidChange)?;
            let hash = change.hash();
            if !hashes.insert(hash) || self.doc.get_change_by_hash(&hash).is_some() {
                return Err(DocumentError::DuplicateChange);
            }
            changes.push(change);
        }

        let mut candidate = self.clone_preserving_actor();
        candidate
            .doc
            .apply_changes_batch(changes)
            .map_err(|_| DocumentError::EngineRejected)?;
        candidate.validate_current_state()?;
        self.doc = candidate.doc;
        Ok(())
    }

    fn validate_known_heads(
        &mut self,
        known_heads: &[DocumentHead],
    ) -> Result<Vec<ChangeHash>, DocumentError> {
        if known_heads.len() > MAX_HEADS {
            return Err(DocumentError::InvalidHeadSet);
        }
        let mut seen = HashSet::with_capacity(known_heads.len());
        let mut result = Vec::with_capacity(known_heads.len());
        for head in known_heads {
            let hash = head.to_change_hash();
            if !seen.insert(hash) || self.doc.get_change_by_hash(&hash).is_none() {
                return Err(DocumentError::InvalidHeadSet);
            }
            result.push(hash);
        }
        Ok(result)
    }

    fn clone_preserving_actor(&mut self) -> Self {
        let actor = self.doc.get_actor().clone();
        let mut doc = self.doc.fork();
        doc.set_actor(actor);
        Self {
            document_id: self.document_id,
            doc,
        }
    }

    fn text_object(&self, key: &str) -> Result<automerge::ObjId, DocumentError> {
        let values = self
            .doc
            .get_all(ROOT, key)
            .map_err(|_| DocumentError::SchemaViolation)?;
        if values.len() != 1 || values[0].0 != Value::Object(ObjType::Text) {
            return Err(DocumentError::SchemaViolation);
        }
        Ok(values[0].1.clone())
    }

    fn validate_current_state(&mut self) -> Result<(), DocumentError> {
        if self.doc.text_encoding() != TextEncoding::GraphemeCluster {
            return Err(DocumentError::SchemaViolation);
        }
        let keys = self.doc.keys(ROOT).collect::<BTreeSet<_>>();
        let expected = [SCHEMA_KEY, DOCUMENT_ID_KEY, TITLE_KEY, BODY_KEY]
            .into_iter()
            .map(str::to_owned)
            .collect::<BTreeSet<_>>();
        if keys != expected {
            return Err(DocumentError::SchemaViolation);
        }

        let schema = self
            .doc
            .get_all(ROOT, SCHEMA_KEY)
            .map_err(|_| DocumentError::SchemaViolation)?;
        if schema.len() != 1 || schema[0].0.as_str() != Some(SCHEMA_ID) {
            return Err(DocumentError::SchemaViolation);
        }

        let document_ids = self
            .doc
            .get_all(ROOT, DOCUMENT_ID_KEY)
            .map_err(|_| DocumentError::SchemaViolation)?;
        if document_ids.len() != 1
            || document_ids[0].0.as_bytes() != Some(self.document_id.as_bytes().as_slice())
        {
            return Err(DocumentError::DocumentMismatch);
        }

        let title_id = self.text_object(TITLE_KEY)?;
        let body_id = self.text_object(BODY_KEY)?;
        self.validate_plain_text_object(&title_id)?;
        self.validate_plain_text_object(&body_id)?;

        let title = self
            .doc
            .text(&title_id)
            .map_err(|_| DocumentError::SchemaViolation)?;
        let body = self
            .doc
            .text(&body_id)
            .map_err(|_| DocumentError::SchemaViolation)?;
        if title.len() > MAX_TITLE_BYTES {
            return Err(DocumentError::TitleTooLarge);
        }
        if body.len() > MAX_BODY_BYTES {
            return Err(DocumentError::BodyTooLarge);
        }

        let stats = self.doc.stats();
        if stats.num_ops > MAX_TOTAL_OPERATIONS
            || stats.num_changes > MAX_TOTAL_CHANGES
            || stats.num_actors > MAX_TOTAL_ACTORS
        {
            return Err(DocumentError::SchemaViolation);
        }
        if self.doc.get_heads().len() > MAX_HEADS {
            return Err(DocumentError::InvalidHeadSet);
        }
        Ok(())
    }

    fn validate_plain_text_object(&self, object: &automerge::ObjId) -> Result<(), DocumentError> {
        if self
            .doc
            .values(object)
            .any(|(value, _)| matches!(value, Value::Object(_)))
        {
            return Err(DocumentError::SchemaViolation);
        }
        if !self
            .doc
            .marks(object)
            .map_err(|_| DocumentError::SchemaViolation)?
            .is_empty()
        {
            return Err(DocumentError::SchemaViolation);
        }
        Ok(())
    }
}

fn grapheme_byte_range(text: &str, start: usize, count: usize) -> Option<(usize, usize)> {
    let graphemes = text.grapheme_indices(true).collect::<Vec<_>>();
    if start > graphemes.len() || count > graphemes.len().saturating_sub(start) {
        return None;
    }
    let start_byte = graphemes.get(start).map_or(text.len(), |(index, _)| *index);
    let end_index = start + count;
    let end_byte = graphemes
        .get(end_index)
        .map_or(text.len(), |(index, _)| *index);
    Some((start_byte, end_byte))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn document_id(value: u8) -> DocumentId {
        DocumentId::new([value; 32]).unwrap()
    }

    fn actor(value: u8) -> DeviceActorId {
        DeviceActorId::new([value; 32]).unwrap()
    }

    fn new_document() -> CollaborativeDocument {
        CollaborativeDocument::new(document_id(7), actor(1)).unwrap()
    }

    fn raw_changes_since(doc: &mut AutoCommit, heads: &[DocumentHead]) -> Vec<EncodedChange> {
        let hashes = heads
            .iter()
            .copied()
            .map(DocumentHead::to_change_hash)
            .collect::<Vec<_>>();
        doc.get_changes(&hashes)
            .into_iter()
            .map(|mut change| EncodedChange {
                bytes: change.bytes().into_owned(),
            })
            .collect()
    }

    #[test]
    fn rejects_zero_identifiers() {
        assert_eq!(
            DocumentId::new([0; 32]),
            Err(DocumentError::InvalidIdentifier)
        );
        assert_eq!(
            DeviceActorId::new([0; 32]),
            Err(DocumentError::InvalidIdentifier)
        );
    }

    #[test]
    fn edits_korean_and_emoji_by_grapheme_cluster() {
        let mut doc = new_document();
        doc.replace_title("보안 회의 🛡️").unwrap();
        doc.splice_body(0, 0, "안녕하세요 👨‍👩‍👧‍👦").unwrap();

        let before = doc.view().unwrap();
        let family_index = before
            .body
            .graphemes(true)
            .position(|grapheme| grapheme == "👨‍👩‍👧‍👦")
            .unwrap();
        doc.splice_body(family_index, 1, "🙂").unwrap();

        let view = doc.view().unwrap();
        assert_eq!(view.title, "보안 회의 🛡️");
        assert_eq!(view.body, "안녕하세요 🙂");
    }

    #[test]
    fn diagnostics_never_render_document_plaintext_or_identifiers() {
        let mut doc = new_document();
        doc.replace_title("기밀 제목").unwrap();
        doc.splice_body(0, 0, "기밀 본문").unwrap();
        let view = doc.view().unwrap();
        let snapshot = doc.save().unwrap();
        let changes = doc.export_changes_since(&[]).unwrap();

        let rendered = format!("{view:?} {snapshot:?} {:?}", changes[0]);
        assert!(!rendered.contains("기밀"));
        assert!(!rendered.contains(&"07".repeat(32)));
        assert!(rendered.contains("byte_length"));
    }

    #[test]
    fn concurrent_offline_edits_converge() {
        let mut alice = new_document();
        alice.splice_body(0, 0, "공동 문서").unwrap();
        let mut bob = alice.fork_for_actor(actor(2)).unwrap();

        let end = alice.view().unwrap().body.graphemes(true).count();
        alice.splice_body(end, 0, " · 앨리스").unwrap();
        bob.splice_body(end, 0, " · 밥").unwrap();

        alice.merge(&mut bob).unwrap();
        bob.merge(&mut alice).unwrap();
        let alice_view = alice.view().unwrap();
        let bob_view = bob.view().unwrap();
        assert_eq!(alice_view.body, bob_view.body);
        assert!(alice_view.body.contains("앨리스"));
        assert!(alice_view.body.contains("밥"));
    }

    #[test]
    fn snapshot_round_trip_requires_expected_document_id() {
        let mut source = new_document();
        source.replace_title("회의록").unwrap();
        source.splice_body(0, 0, "결정 사항 ✅").unwrap();
        let snapshot = source.save().unwrap();

        let mut restored =
            CollaborativeDocument::load(document_id(7), actor(3), &snapshot).unwrap();
        assert_eq!(source.view().unwrap(), restored.view().unwrap());
        assert_eq!(
            CollaborativeDocument::load(document_id(8), actor(3), &snapshot)
                .err()
                .unwrap(),
            DocumentError::InvalidSnapshot
        );
    }

    #[test]
    fn changes_export_and_import_after_known_heads() {
        let mut source = new_document();
        let mut replica = source.fork_for_actor(actor(2)).unwrap();
        let known_heads = replica.heads().unwrap();

        source.splice_body(0, 0, "오프라인 변경").unwrap();
        let changes = source.export_changes_since(&known_heads).unwrap();
        assert_eq!(changes.len(), 1);
        replica.apply_encoded_changes(changes).unwrap();
        assert_eq!(source.view().unwrap().body, replica.view().unwrap().body);
    }

    #[test]
    fn duplicate_change_batch_is_rejected_atomically() {
        let mut source = new_document();
        let mut replica = source.fork_for_actor(actor(2)).unwrap();
        let known_heads = replica.heads().unwrap();
        source.splice_body(0, 0, "중복 금지").unwrap();
        let changes = source.export_changes_since(&known_heads).unwrap();
        let duplicate = EncodedChange::try_from_bytes(changes[0].as_bytes().to_vec()).unwrap();
        let original = EncodedChange::try_from_bytes(changes[0].as_bytes().to_vec()).unwrap();
        let before = replica.view().unwrap();

        assert_eq!(
            replica.apply_encoded_changes(vec![original, duplicate]),
            Err(DocumentError::DuplicateChange)
        );
        assert_eq!(replica.view().unwrap(), before);
    }

    #[test]
    fn already_applied_change_is_rejected() {
        let mut source = new_document();
        let mut replica = source.fork_for_actor(actor(2)).unwrap();
        let known_heads = replica.heads().unwrap();
        source.splice_body(0, 0, "한 번만").unwrap();
        let first = source.export_changes_since(&known_heads).unwrap();
        let replay = first
            .iter()
            .map(|item| EncodedChange::try_from_bytes(item.as_bytes().to_vec()).unwrap())
            .collect();
        replica.apply_encoded_changes(first).unwrap();
        let accepted = replica.view().unwrap();
        assert_eq!(
            replica.apply_encoded_changes(replay),
            Err(DocumentError::DuplicateChange)
        );
        assert_eq!(replica.view().unwrap(), accepted);
    }

    #[test]
    fn corrupt_and_oversized_inputs_fail_closed() {
        let mut doc = new_document();
        let before = doc.view().unwrap();
        let corrupt = EncodedChange::try_from_bytes(vec![1, 2, 3]).unwrap();
        assert_eq!(
            doc.apply_encoded_changes(vec![corrupt]),
            Err(DocumentError::InvalidChange)
        );
        assert_eq!(doc.view().unwrap(), before);
        assert_eq!(
            EncodedChange::try_from_bytes(vec![0; MAX_CHANGE_BYTES + 1]).err(),
            Some(DocumentError::InvalidChange)
        );
        assert_eq!(
            DocumentSnapshot::try_from_bytes(vec![0; MAX_SNAPSHOT_BYTES + 1]).err(),
            Some(DocumentError::InvalidSnapshot)
        );
        let corrupt_snapshot = DocumentSnapshot::try_from_bytes(vec![1, 2, 3]).unwrap();
        assert_eq!(
            CollaborativeDocument::load(document_id(7), actor(4), &corrupt_snapshot)
                .err()
                .unwrap(),
            DocumentError::InvalidSnapshot
        );
    }

    #[test]
    fn malicious_schema_change_is_rejected_atomically() {
        let mut target = new_document();
        let mut attacker = target.fork_for_actor(actor(9)).unwrap();
        let known_heads = target.heads().unwrap();
        attacker.doc.put(ROOT, "plaintext_secret", "leak").unwrap();
        let changes = raw_changes_since(&mut attacker.doc, &known_heads);
        let before = target.view().unwrap();
        assert_eq!(
            target.apply_encoded_changes(changes),
            Err(DocumentError::SchemaViolation)
        );
        assert_eq!(target.view().unwrap(), before);
    }

    #[test]
    fn malformed_text_schema_is_rejected() {
        let mut target = new_document();
        let mut attacker = target.fork_for_actor(actor(9)).unwrap();
        let known_heads = target.heads().unwrap();
        attacker.doc.put(ROOT, TITLE_KEY, "not text").unwrap();
        let changes = raw_changes_since(&mut attacker.doc, &known_heads);
        assert_eq!(
            target.apply_encoded_changes(changes),
            Err(DocumentError::SchemaViolation)
        );
    }

    #[test]
    fn bounds_and_unknown_heads_are_rejected() {
        let mut doc = new_document();
        assert_eq!(
            doc.splice_body(1, 0, "x"),
            Err(DocumentError::InvalidTextRange)
        );
        assert_eq!(
            doc.replace_title(&"x".repeat(MAX_TITLE_BYTES + 1)),
            Err(DocumentError::TitleTooLarge)
        );
        assert_eq!(
            doc.splice_body(0, 0, &"x".repeat(MAX_INSERT_BYTES + 1)),
            Err(DocumentError::InsertionTooLarge)
        );
        assert!(matches!(
            doc.export_changes_since(&[DocumentHead([42; 32])]),
            Err(DocumentError::InvalidHeadSet)
        ));
    }

    #[test]
    fn different_documents_never_merge() {
        let mut first = new_document();
        let mut second = CollaborativeDocument::new(document_id(8), actor(2)).unwrap();
        assert_eq!(
            first.merge(&mut second),
            Err(DocumentError::DocumentMismatch)
        );
    }

    #[test]
    fn excessive_batch_count_is_rejected_before_decode() {
        let mut doc = new_document();
        let batch = (0..=MAX_CHANGES_PER_BATCH)
            .map(|_| EncodedChange { bytes: vec![1] })
            .collect();
        assert_eq!(
            doc.apply_encoded_changes(batch),
            Err(DocumentError::InvalidChangeBatch)
        );
    }
}
