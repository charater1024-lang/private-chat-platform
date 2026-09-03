import 'encrypted_transport.dart';
import 'homeserver_connection.dart';

/// Adapter-issued session. Callers cannot construct a package session or attach
/// TLS evidence to a connection profile.
abstract interface class HomeserverTransportSession {
  String get sessionId;
  String get serverId;
  String get memberId;
  TlsSessionEvidence get tlsEvidence;
}

abstract interface class HomeserverTransport {
  /// The adapter must perform a fresh TLS handshake, enforce [profile]'s peer
  /// policy, authenticate its credential reference, then issue the session.
  Future<HomeserverTransportSession> connect(ServerConnectionProfile profile);

  Future<void> disconnect(HomeserverTransportSession session);
}

abstract interface class PrivacyHomeserverTransport
    implements HomeserverTransport {
  Future<void> sendTrueE2ee(
    HomeserverTransportSession session,
    TrueE2eeMessageEnvelope envelope,
  );

  Future<List<TrueE2eeMessageEnvelope>> synchronizeTrueE2ee(
    HomeserverTransportSession session, {
    required String conversationId,
  });
}
