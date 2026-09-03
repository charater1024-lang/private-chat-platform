import 'dart:typed_data';

import 'package:chat_sync/chat_sync.dart';

enum HomeserverCipherSuite {
  mls10,
  signalDoubleRatchet;

  String get wireName => switch (this) {
    mls10 => 'MLS_1_0',
    signalDoubleRatchet => 'SIGNAL_DOUBLE_RATCHET',
  };
}

/// Strict canonical framing for data already protected by an external E2EE
/// implementation.
///
/// This type does not encrypt, authenticate, derive keys, or verify the
/// protocol ciphertext. It only preserves the fields required by the runtime
/// API inside [CiphertextEnvelope].
final class HomeserverCiphertextFrame {
  factory HomeserverCiphertextFrame({
    required DateTime sentAt,
    required HomeserverCipherSuite cipherSuite,
    required int keyEpoch,
    required Iterable<int> protocolCiphertext,
    required Iterable<int> nonce,
    required Iterable<int> authenticationTag,
    int maximumCiphertextBytes = defaultMaximumCiphertextBytes,
  }) {
    if (!sentAt.isUtc) {
      throw const HomeserverFrameException();
    }
    if (keyEpoch < 0 || keyEpoch > maximumSafeInteger) {
      throw const HomeserverFrameException();
    }
    if (maximumCiphertextBytes < 1 ||
        maximumCiphertextBytes > defaultMaximumCiphertextBytes) {
      throw const HomeserverFrameException();
    }
    final ciphertextCopy = _copyBytes(protocolCiphertext);
    final nonceCopy = _copyBytes(nonce);
    final tagCopy = _copyBytes(authenticationTag);
    if (ciphertextCopy.isEmpty ||
        ciphertextCopy.length > maximumCiphertextBytes ||
        nonceCopy.length < 12 ||
        nonceCopy.length > 48 ||
        tagCopy.length < 16 ||
        tagCopy.length > 96) {
      throw const HomeserverFrameException();
    }
    return HomeserverCiphertextFrame._(
      sentAt: sentAt,
      cipherSuite: cipherSuite,
      keyEpoch: keyEpoch,
      protocolCiphertext: ciphertextCopy,
      nonce: nonceCopy,
      authenticationTag: tagCopy,
    );
  }

  const HomeserverCiphertextFrame._({
    required this.sentAt,
    required this.cipherSuite,
    required this.keyEpoch,
    required this._protocolCiphertext,
    required this._nonce,
    required this._authenticationTag,
  });

  static const int defaultMaximumCiphertextBytes = 1024 * 1024;
  static const int maximumSafeInteger = 9007199254740991;
  static const int _headerBytes = 30;
  static const List<int> _magic = [0x48, 0x53, 0x43, 0x46]; // HSCF
  static const int _version = 1;

  final DateTime sentAt;
  final HomeserverCipherSuite cipherSuite;
  final int keyEpoch;
  final Uint8List _protocolCiphertext;
  final Uint8List _nonce;
  final Uint8List _authenticationTag;

  int get protocolCiphertextLength => _protocolCiphertext.length;
  int get nonceLength => _nonce.length;
  int get authenticationTagLength => _authenticationTag.length;

  Uint8List copyProtocolCiphertext() => Uint8List.fromList(_protocolCiphertext);
  Uint8List copyNonce() => Uint8List.fromList(_nonce);
  Uint8List copyAuthenticationTag() => Uint8List.fromList(_authenticationTag);

  Uint8List encode() {
    final total =
        _headerBytes +
        _protocolCiphertext.length +
        _nonce.length +
        _authenticationTag.length;
    final output = Uint8List(total);
    output.setRange(0, _magic.length, _magic);
    final data = ByteData.sublistView(output);
    data.setUint8(4, _version);
    data.setUint8(5, switch (cipherSuite) {
      HomeserverCipherSuite.mls10 => 1,
      HomeserverCipherSuite.signalDoubleRatchet => 2,
    });
    data.setInt64(6, sentAt.microsecondsSinceEpoch, Endian.big);
    data.setUint64(14, keyEpoch, Endian.big);
    data.setUint32(22, _protocolCiphertext.length, Endian.big);
    data.setUint16(26, _nonce.length, Endian.big);
    data.setUint16(28, _authenticationTag.length, Endian.big);
    var offset = _headerBytes;
    output.setRange(
      offset,
      offset + _protocolCiphertext.length,
      _protocolCiphertext,
    );
    offset += _protocolCiphertext.length;
    output.setRange(offset, offset + _nonce.length, _nonce);
    offset += _nonce.length;
    output.setRange(
      offset,
      offset + _authenticationTag.length,
      _authenticationTag,
    );
    return output;
  }

  CiphertextEnvelope toSyncEnvelope() => CiphertextEnvelope(encode());

  static HomeserverCiphertextFrame decode(
    Iterable<int> encoded, {
    int maximumCiphertextBytes = defaultMaximumCiphertextBytes,
  }) {
    try {
      final bytes = _copyBytes(encoded);
      if (maximumCiphertextBytes < 1 ||
          maximumCiphertextBytes > defaultMaximumCiphertextBytes ||
          bytes.length < _headerBytes) {
        throw const HomeserverFrameException();
      }
      for (var index = 0; index < _magic.length; index += 1) {
        if (bytes[index] != _magic[index]) {
          throw const HomeserverFrameException();
        }
      }
      final data = ByteData.sublistView(bytes);
      if (data.getUint8(4) != _version) {
        throw const HomeserverFrameException();
      }
      final suite = switch (data.getUint8(5)) {
        1 => HomeserverCipherSuite.mls10,
        2 => HomeserverCipherSuite.signalDoubleRatchet,
        _ => throw const HomeserverFrameException(),
      };
      final timestampMicros = data.getInt64(6, Endian.big);
      final keyEpoch = data.getUint64(14, Endian.big);
      final ciphertextLength = data.getUint32(22, Endian.big);
      final nonceLength = data.getUint16(26, Endian.big);
      final tagLength = data.getUint16(28, Endian.big);
      if (keyEpoch > maximumSafeInteger ||
          ciphertextLength < 1 ||
          ciphertextLength > maximumCiphertextBytes ||
          nonceLength < 12 ||
          nonceLength > 48 ||
          tagLength < 16 ||
          tagLength > 96 ||
          _headerBytes + ciphertextLength + nonceLength + tagLength !=
              bytes.length) {
        throw const HomeserverFrameException();
      }
      final sentAt = DateTime.fromMicrosecondsSinceEpoch(
        timestampMicros,
        isUtc: true,
      );
      var offset = _headerBytes;
      final ciphertext = Uint8List.sublistView(
        bytes,
        offset,
        offset + ciphertextLength,
      );
      offset += ciphertextLength;
      final nonce = Uint8List.sublistView(bytes, offset, offset + nonceLength);
      offset += nonceLength;
      final tag = Uint8List.sublistView(bytes, offset, offset + tagLength);
      final frame = HomeserverCiphertextFrame(
        sentAt: sentAt,
        cipherSuite: suite,
        keyEpoch: keyEpoch,
        protocolCiphertext: ciphertext,
        nonce: nonce,
        authenticationTag: tag,
        maximumCiphertextBytes: maximumCiphertextBytes,
      );
      final canonical = frame.encode();
      if (!_sameBytes(bytes, canonical)) {
        throw const HomeserverFrameException();
      }
      return frame;
    } on HomeserverFrameException {
      rethrow;
    } on Object {
      throw const HomeserverFrameException();
    }
  }

  static HomeserverCiphertextFrame fromSyncEnvelope(
    CiphertextEnvelope envelope, {
    int maximumCiphertextBytes = defaultMaximumCiphertextBytes,
  }) => decode(
    envelope.copyBytes(),
    maximumCiphertextBytes: maximumCiphertextBytes,
  );

  @override
  String toString() {
    return 'HomeserverCiphertextFrame(cipherSuite: $cipherSuite, '
        'timestamp/keyEpoch/bytes: <redacted>)';
  }
}

final class HomeserverFrameException implements Exception {
  const HomeserverFrameException();

  @override
  String toString() => 'HomeserverFrameException(data: <redacted>)';
}

Uint8List _copyBytes(Iterable<int> values) {
  final list = List<int>.of(values, growable: false);
  if (list.any((value) => value < 0 || value > 255)) {
    throw const HomeserverFrameException();
  }
  return Uint8List.fromList(list);
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
