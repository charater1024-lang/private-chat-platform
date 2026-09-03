import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_sync/chat_sync.dart';

import 'ciphertext_frame.dart';

/// Exact POST metadata persisted before an idempotent message send.
///
/// [toJson] contains ciphertext and routing metadata and is a persistence
/// representation, never a diagnostic representation. Production adapters
/// should encrypt it at rest.
final class PreparedHomeserverRequest {
  factory PreparedHomeserverRequest({
    required ConversationId conversationId,
    required ClientMessageId clientMessageId,
    required int resourceVersion,
    required Iterable<int> framedEnvelopeBytes,
    required Iterable<int> requestBodyBytes,
  }) {
    if (resourceVersion < 1 || resourceVersion > 9007199254740991) {
      throw ArgumentError.value(
        resourceVersion,
        'resourceVersion',
        'must be a positive safe integer',
      );
    }
    final envelope = _copyBounded(
      framedEnvelopeBytes,
      maximum:
          HomeserverCiphertextFrame.defaultMaximumCiphertextBytes +
          30 +
          48 +
          96,
    );
    try {
      HomeserverCiphertextFrame.decode(envelope);
    } on HomeserverFrameException {
      throw ArgumentError.value(
        '<redacted>',
        'framedEnvelopeBytes',
        'must be a canonical ciphertext frame',
      );
    }
    final body = _copyBounded(requestBodyBytes, maximum: 3 * 1024 * 1024);
    return PreparedHomeserverRequest._(
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      resourceVersion: resourceVersion,
      framedEnvelopeBytes: envelope,
      requestBodyBytes: body,
    );
  }

  const PreparedHomeserverRequest._({
    required this.conversationId,
    required this.clientMessageId,
    required this.resourceVersion,
    required this._framedEnvelopeBytes,
    required this._requestBodyBytes,
  });

  factory PreparedHomeserverRequest.fromJson(Map<String, Object?> json) {
    try {
      if (json.keys.toSet().difference(const {
            'conversationId',
            'clientMessageId',
            'resourceVersion',
            'framedEnvelope',
            'requestBody',
          }).isNotEmpty ||
          json.length != 5) {
        throw const FormatException();
      }
      return PreparedHomeserverRequest(
        conversationId: ConversationId(json['conversationId']! as String),
        clientMessageId: ClientMessageId(json['clientMessageId']! as String),
        resourceVersion: json['resourceVersion']! as int,
        framedEnvelopeBytes: base64Decode(json['framedEnvelope']! as String),
        requestBodyBytes: base64Decode(json['requestBody']! as String),
      );
    } on Object {
      throw const FormatException('Invalid prepared-request record');
    }
  }

  final ConversationId conversationId;
  final ClientMessageId clientMessageId;
  final int resourceVersion;
  final Uint8List _framedEnvelopeBytes;
  final Uint8List _requestBodyBytes;

  Uint8List copyFramedEnvelopeBytes() =>
      Uint8List.fromList(_framedEnvelopeBytes);
  Uint8List copyRequestBodyBytes() => Uint8List.fromList(_requestBodyBytes);

  bool matches(OutboundCiphertextMessage message) =>
      message.conversationId == conversationId &&
      message.clientMessageId == clientMessageId &&
      _constantTimeEquals(_framedEnvelopeBytes, message.ciphertext.copyBytes());

  Map<String, Object?> toJson() => {
    'conversationId': conversationId.value,
    'clientMessageId': clientMessageId.value,
    'resourceVersion': resourceVersion,
    'framedEnvelope': base64Encode(_framedEnvelopeBytes),
    'requestBody': base64Encode(_requestBodyBytes),
  };

  @override
  String toString() => 'PreparedHomeserverRequest(data: <redacted>)';
}

/// Complete atomic state for prepared message requests.
final class PreparedRequestStoreSnapshot {
  PreparedRequestStoreSnapshot({
    required this.generation,
    required Iterable<PreparedHomeserverRequest> requests,
  }) : requests = List.unmodifiable(requests) {
    if (generation < 0 || generation > 9007199254740991) {
      throw ArgumentError.value(
        generation,
        'generation',
        'must be a non-negative safe integer',
      );
    }
    final ids = <String>{};
    if (this.requests.any(
      (request) => !ids.add(request.clientMessageId.value),
    )) {
      throw ArgumentError('prepared request ids must be unique');
    }
  }

  factory PreparedRequestStoreSnapshot.initial() =>
      PreparedRequestStoreSnapshot(generation: 0, requests: const []);

  factory PreparedRequestStoreSnapshot.fromJson(Map<String, Object?> json) {
    try {
      if (json['schemaVersion'] != schemaVersion || json.length != 3) {
        throw const FormatException();
      }
      final raw = json['requests']! as List<Object?>;
      return PreparedRequestStoreSnapshot(
        generation: json['generation']! as int,
        requests: raw.map(
          (value) => PreparedHomeserverRequest.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );
    } on Object {
      throw const FormatException('Invalid prepared-request snapshot');
    }
  }

  static const int schemaVersion = 1;

  final int generation;
  final List<PreparedHomeserverRequest> requests;

  PreparedRequestStoreSnapshot copyWith({
    int? generation,
    Iterable<PreparedHomeserverRequest>? requests,
  }) => PreparedRequestStoreSnapshot(
    generation: generation ?? this.generation,
    requests: requests ?? this.requests,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generation': generation,
    'requests': requests.map((request) => request.toJson()).toList(),
  };

  @override
  String toString() {
    return 'PreparedRequestStoreSnapshot(generation: $generation, '
        'count: ${requests.length}, data: <redacted>)';
  }
}

/// Atomic compare-and-swap store for exact idempotent HTTP request bytes.
///
/// An absent snapshot has generation zero. [writeAtomically] must reject when
/// the stored generation differs from [expectedGeneration].
abstract interface class PreparedRequestStore {
  Future<PreparedRequestStoreSnapshot?> read();

  Future<void> writeAtomically(
    PreparedRequestStoreSnapshot snapshot, {
    required int expectedGeneration,
  });
}

final class PreparedRequestStoreConflictException implements Exception {
  const PreparedRequestStoreConflictException();

  @override
  String toString() =>
      'PreparedRequestStoreConflictException(data: <redacted>)';
}

Uint8List _copyBounded(Iterable<int> values, {required int maximum}) {
  final copied = List<int>.of(values, growable: false);
  if (copied.isEmpty ||
      copied.length > maximum ||
      copied.any((value) => value < 0 || value > 255)) {
    throw ArgumentError.value(
      '<redacted>',
      'values',
      'must contain bounded bytes',
    );
  }
  return Uint8List.fromList(copied);
}

bool _constantTimeEquals(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
