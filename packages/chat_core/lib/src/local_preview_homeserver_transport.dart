// ignore_for_file: prefer_initializing_formals

import 'encrypted_transport.dart';
import 'homeserver_connection.dart';
import 'homeserver_transport.dart';
import 'in_memory_homeserver.dart';
import 'product_policy.dart';

/// Local-only preview adapter for widget tests and UI demonstrations.
///
/// It simulates a successful platform TLS chain check for [servedEndpoint], but
/// does not open a socket, dereference credentials, or perform cryptography.
/// It is exported only by `chat_core_preview.dart` and must never be deployed.
final class LocalPreviewHomeserverTransport
    implements PrivacyHomeserverTransport {
  LocalPreviewHomeserverTransport(
    this._repository, {
    required Uri servedEndpoint,
    required CertificatePin observedPeerCertificateDigest,
    DateTime Function()? clock,
  }) : _servedEndpoint = servedEndpoint,
       _observedPeerCertificateDigest = observedPeerCertificateDigest,
       _clock = clock ?? DateTime.now {
    if (servedEndpoint.scheme.toLowerCase() != 'https' ||
        servedEndpoint.host.isEmpty ||
        servedEndpoint.userInfo.isNotEmpty ||
        servedEndpoint.hasQuery ||
        servedEndpoint.hasFragment) {
      throw ArgumentError(
        'preview endpoint must be an absolute safe HTTPS URI',
      );
    }
  }

  final InMemoryHomeserverRepository _repository;
  final Uri _servedEndpoint;
  final CertificatePin _observedPeerCertificateDigest;
  final DateTime Function() _clock;
  final Map<String, _LocalPreviewSession> _sessions = {};
  int _nextSession = 1;

  @override
  Future<HomeserverTransportSession> connect(
    ServerConnectionProfile profile,
  ) async {
    final descriptor = _repository.descriptor;
    if (profile.endpoint != _servedEndpoint) {
      throw StateError('connection endpoint does not match this adapter');
    }
    if (profile.serverId != descriptor.serverId ||
        profile.productKind != descriptor.productKind) {
      throw StateError('connection profile does not match this homeserver');
    }
    if (!profile.tlsPeerPolicy.accepts(_observedPeerCertificateDigest)) {
      throw StateError('TLS peer certificate pin mismatch');
    }
    final member = _repository.memberById(
      requestedBy: profile.memberId,
      memberId: profile.memberId,
    );
    final verifiedAt = _clock().toUtc();
    final evidence = TlsSessionEvidence.adapterVerified(
      endpoint: profile.endpoint,
      peerCertificateDigest: _observedPeerCertificateDigest,
      verifiedAt: verifiedAt,
      verificationMethod: profile.tlsPeerPolicy.kind,
    );
    final session = _LocalPreviewSession(
      sessionId: 'local-preview-session-${_nextSession++}',
      serverId: descriptor.serverId,
      memberId: member.memberId,
      productKind: descriptor.productKind,
      tlsEvidence: evidence,
    );
    _sessions[session.sessionId] = session;
    return session;
  }

  _LocalPreviewSession _requireSession(HomeserverTransportSession session) {
    final current = _sessions[session.sessionId];
    if (!identical(current, session)) {
      throw StateError('transport session is not active or adapter-issued');
    }
    if (current!.tlsEvidence.endpoint != _servedEndpoint) {
      throw StateError('transport session endpoint binding is invalid');
    }
    return current;
  }

  void _ensureEnvelopeMatchesSession(
    _LocalPreviewSession session,
    EncryptedMessageEnvelope envelope,
  ) {
    if (envelope.serverId != session.serverId ||
        envelope.senderId != session.memberId) {
      throw StateError(
        'encrypted envelope identity does not match the session',
      );
    }
  }

  @override
  Future<void> sendTrueE2ee(
    HomeserverTransportSession session,
    TrueE2eeMessageEnvelope envelope,
  ) async {
    final active = _requireSession(session);
    _ensureEnvelopeMatchesSession(active, envelope);
    _repository.storeTrueE2eeMessage(envelope);
  }

  @override
  Future<List<TrueE2eeMessageEnvelope>> synchronizeTrueE2ee(
    HomeserverTransportSession session, {
    required String conversationId,
  }) async {
    final active = _requireSession(session);
    return _repository.listTrueE2eeMessages(
      requestedBy: active.memberId,
      conversationId: conversationId,
    );
  }

  @override
  Future<void> disconnect(HomeserverTransportSession session) async {
    final active = _requireSession(session);
    _sessions.remove(active.sessionId);
  }
}

final class _LocalPreviewSession implements HomeserverTransportSession {
  const _LocalPreviewSession({
    required this.sessionId,
    required this.serverId,
    required this.memberId,
    required this.productKind,
    required this.tlsEvidence,
  });

  @override
  final String sessionId;
  @override
  final String serverId;
  @override
  final String memberId;
  final ProductKind productKind;
  @override
  final TlsSessionEvidence tlsEvidence;

  @override
  String toString() {
    return 'LocalPreviewHomeserverSession('
        'sessionId: [REDACTED], serverId: [REDACTED], '
        'memberId: [REDACTED], productKind: $productKind, '
        'tlsEvidence: [REDACTED])';
  }
}
