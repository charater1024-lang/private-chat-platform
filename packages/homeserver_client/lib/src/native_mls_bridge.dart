import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_sync/chat_sync.dart';

import 'ciphertext_frame.dart';
import 'conversation_sync_controller.dart';

/// Strict application-owned boundary for a reviewed native OpenMLS bridge.
///
/// The repository intentionally provides no Dart fallback and no test key in
/// production code. Platform integrations must implement both protection and
/// unprotection against one persistent MLS state machine, serialize access,
/// and keep epoch secrets in OS-protected encrypted storage.
abstract interface class AuditedMlsNativeBridge {
  Future<ProductionTextProtectionReadiness> verifyReadiness();

  Future<HomeserverCiphertextFrame> protectApplicationMessage({
    required ConversationId conversationId,
    required Uint8List plaintextUtf8,
    required DateTime sentAt,
  });

  Future<Uint8List> unprotectApplicationMessage({
    required ConversationId conversationId,
    required HomeserverCiphertextFrame frame,
  });

  Future<void> close();
}

/// Converts the application text contract to the reviewed native MLS bridge.
final class NativeMlsTextProtectionAdapter
    implements ProductionHomeserverTextProtectionPort {
  NativeMlsTextProtectionAdapter(this._bridge);

  final AuditedMlsNativeBridge _bridge;

  @override
  Future<ProductionTextProtectionReadiness> verifyProductionReadiness() =>
      _bridge.verifyReadiness();

  @override
  Future<HomeserverCiphertextFrame> protectText({
    required ConversationId conversationId,
    required String plaintext,
    required DateTime sentAt,
  }) async {
    if (!sentAt.isUtc) throw const HomeserverFrameException();
    final encoded = Uint8List.fromList(utf8.encode(plaintext));
    try {
      final frame = await _bridge.protectApplicationMessage(
        conversationId: conversationId,
        plaintextUtf8: encoded,
        sentAt: sentAt,
      );
      if (frame.cipherSuite != HomeserverCipherSuite.mls10 ||
          frame.sentAt != sentAt ||
          frame.keyEpoch < 0) {
        throw const HomeserverFrameException();
      }
      // Round-trip canonical framing before accepting native output.
      return HomeserverCiphertextFrame.decode(frame.encode());
    } finally {
      encoded.fillRange(0, encoded.length, 0);
    }
  }

  @override
  String toString() =>
      'NativeMlsTextProtectionAdapter(bridge/state: <redacted>)';
}
