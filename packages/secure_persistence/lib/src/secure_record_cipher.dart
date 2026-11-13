// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'security_boundaries.dart';

enum SecureRecordError {
  invalidConfiguration,
  sizeLimitExceeded,
  malformedRecord,
  authenticationFailed,
  keyUnavailable,
}

/// Sanitized failure which never retains keys, paths, record bytes, or causes.
final class SecureRecordException implements Exception {
  const SecureRecordException(this.code);

  final SecureRecordError code;

  @override
  String toString() =>
      'SecureRecordException(code: $code, details: <redacted>)';
}

/// Versioned ChaCha20-Poly1305 envelope with per-namespace HKDF key separation.
final class SecureRecordCipher {
  SecureRecordCipher({
    required String namespace,
    required SecureRecordKeyProvider keyProvider,
    int maximumPlaintextBytes = 64 * 1024 * 1024,
  }) : _namespace = _validatedNamespace(namespace),
       _keyProvider = keyProvider,
       _maximumPlaintextBytes = _validatedMaximum(maximumPlaintextBytes),
       _cipher = const DartChacha20.poly1305Aead(),
       _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static const List<int> _magic = <int>[
    0x50,
    0x43,
    0x53,
    0x50,
    0x41,
    0x45,
    0x30,
    0x31,
  ]; // PCSPAE01
  static const int _version = 1;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _headerLength = 8 + 1 + _nonceLength + 4;
  static const int envelopeOverhead = _headerLength + _macLength;
  static final Uint8List _hkdfSalt = Uint8List.fromList(
    utf8.encode('private-chat/secure-persistence/hkdf-sha256/v1'),
  );
  static final Uint8List _aadDomain = Uint8List.fromList(
    utf8.encode('private-chat/secure-persistence/record/v1'),
  );

  final String _namespace;
  final SecureRecordKeyProvider _keyProvider;
  final int _maximumPlaintextBytes;
  final Cipher _cipher;
  final Hkdf _kdf;
  final Random _random = Random.secure();

  int get maximumPlaintextBytes => _maximumPlaintextBytes;

  Future<Uint8List> seal(
    List<int> plaintext, {
    List<int> additionalAssociatedData = const <int>[],
  }) async {
    final cleartext = _boundedCopy(plaintext, allowEmpty: false);
    final extra = _boundedAssociatedData(additionalAssociatedData);
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceLength, (_) => _random.nextInt(256)),
    );
    final header = _header(nonce, cleartext.length);
    final aad = _associatedData(header, extra);
    SecretKeyData? derived;
    try {
      derived = await _deriveKey();
      final box = await _cipher.encrypt(
        cleartext,
        secretKey: derived,
        nonce: nonce,
        aad: aad,
      );
      if (box.cipherText.length != cleartext.length ||
          box.mac.bytes.length != _macLength) {
        throw const SecureRecordException(
          SecureRecordError.authenticationFailed,
        );
      }
      return Uint8List.fromList(<int>[
        ...header,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
    } on SecureRecordException {
      rethrow;
    } on Object {
      throw const SecureRecordException(SecureRecordError.keyUnavailable);
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
      extra.fillRange(0, extra.length, 0);
      aad.fillRange(0, aad.length, 0);
      derived?.destroy();
    }
  }

  Future<Uint8List> open(
    List<int> envelope, {
    List<int> additionalAssociatedData = const <int>[],
  }) async {
    final bytes = _boundedEnvelopeCopy(envelope);
    final extra = _boundedAssociatedData(additionalAssociatedData);
    SecretKeyData? derived;
    List<int>? opened;
    try {
      if (bytes.length < envelopeOverhead || !_hasMagic(bytes)) {
        throw const SecureRecordException(SecureRecordError.malformedRecord);
      }
      final data = ByteData.sublistView(bytes);
      if (data.getUint8(8) != _version) {
        throw const SecureRecordException(SecureRecordError.malformedRecord);
      }
      final ciphertextLength = data.getUint32(21, Endian.big);
      if (ciphertextLength < 1 ||
          ciphertextLength > _maximumPlaintextBytes ||
          bytes.length != _headerLength + ciphertextLength + _macLength) {
        throw const SecureRecordException(SecureRecordError.malformedRecord);
      }
      final nonce = Uint8List.sublistView(bytes, 9, 21);
      final header = Uint8List.sublistView(bytes, 0, _headerLength);
      final ciphertext = Uint8List.sublistView(
        bytes,
        _headerLength,
        _headerLength + ciphertextLength,
      );
      final mac = Mac(
        Uint8List.sublistView(bytes, _headerLength + ciphertextLength),
      );
      final aad = _associatedData(header, extra);
      try {
        derived = await _deriveKey();
        opened = await _cipher.decrypt(
          SecretBox(ciphertext, nonce: nonce, mac: mac),
          secretKey: derived,
          aad: aad,
        );
        if (opened.length != ciphertextLength) {
          throw const SecureRecordException(
            SecureRecordError.authenticationFailed,
          );
        }
        return Uint8List.fromList(opened);
      } on SecretBoxAuthenticationError {
        throw const SecureRecordException(
          SecureRecordError.authenticationFailed,
        );
      } finally {
        aad.fillRange(0, aad.length, 0);
      }
    } on SecureRecordException {
      rethrow;
    } on Object {
      throw const SecureRecordException(SecureRecordError.keyUnavailable);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      extra.fillRange(0, extra.length, 0);
      opened?.fillRange(0, opened.length, 0);
      derived?.destroy();
    }
  }

  Future<SecretKeyData> _deriveKey() async {
    List<int>? extracted;
    Uint8List? owned;
    SecretKeyData? validatedMaster;
    try {
      final master = await _keyProvider.loadMasterKey();
      extracted = await master.extractBytes();
      owned = Uint8List.fromList(extracted);
      if (owned.length < 32) {
        throw const SecureRecordException(SecureRecordError.keyUnavailable);
      }
      validatedMaster = SecretKeyData(owned);
      return await _kdf.deriveKey(
        secretKey: validatedMaster,
        nonce: _hkdfSalt,
        info: utf8.encode('namespace:$_namespace'),
      );
    } on SecureRecordException {
      rethrow;
    } on Object {
      throw const SecureRecordException(SecureRecordError.keyUnavailable);
    } finally {
      validatedMaster?.destroy();
      owned?.fillRange(0, owned.length, 0);
      final providerCopy = extracted;
      if (providerCopy != null) {
        try {
          providerCopy.fillRange(0, providerCopy.length, 0);
        } on Object {
          // Some providers return an immutable copy. The owned copy and
          // derived key are still explicitly destroyed above.
        }
      }
    }
  }

  Uint8List _boundedCopy(List<int> input, {required bool allowEmpty}) {
    if ((!allowEmpty && input.isEmpty) ||
        input.length > _maximumPlaintextBytes ||
        input.any((value) => value < 0 || value > 255)) {
      throw const SecureRecordException(SecureRecordError.sizeLimitExceeded);
    }
    return Uint8List.fromList(input);
  }

  Uint8List _boundedEnvelopeCopy(List<int> input) {
    if (input.length < envelopeOverhead ||
        input.length > _maximumPlaintextBytes + envelopeOverhead ||
        input.any((value) => value < 0 || value > 255)) {
      throw const SecureRecordException(SecureRecordError.sizeLimitExceeded);
    }
    return Uint8List.fromList(input);
  }

  Uint8List _boundedAssociatedData(List<int> input) {
    if (input.length > 64 * 1024 ||
        input.any((value) => value < 0 || value > 255)) {
      throw const SecureRecordException(SecureRecordError.sizeLimitExceeded);
    }
    return Uint8List.fromList(input);
  }

  Uint8List _header(Uint8List nonce, int plaintextLength) {
    final header = Uint8List(_headerLength);
    header.setRange(0, _magic.length, _magic);
    final data = ByteData.sublistView(header);
    data.setUint8(8, _version);
    header.setRange(9, 21, nonce);
    data.setUint32(21, plaintextLength, Endian.big);
    return header;
  }

  Uint8List _associatedData(Uint8List header, Uint8List extra) {
    final namespaceBytes = utf8.encode(_namespace);
    final lengths = ByteData(8)
      ..setUint32(0, namespaceBytes.length, Endian.big)
      ..setUint32(4, extra.length, Endian.big);
    return Uint8List.fromList(<int>[
      ..._aadDomain,
      ...lengths.buffer.asUint8List(),
      ...namespaceBytes,
      ...header,
      ...extra,
    ]);
  }

  bool _hasMagic(Uint8List bytes) {
    var difference = 0;
    for (var index = 0; index < _magic.length; index += 1) {
      difference |= bytes[index] ^ _magic[index];
    }
    return difference == 0;
  }

  @override
  String toString() =>
      'SecureRecordCipher(namespace/key/plaintext: <redacted>)';
}

String _validatedNamespace(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$').hasMatch(value)) {
    throw const SecureRecordException(SecureRecordError.invalidConfiguration);
  }
  return value;
}

int _validatedMaximum(int value) {
  if (value < 1 || value > 512 * 1024 * 1024) {
    throw const SecureRecordException(SecureRecordError.invalidConfiguration);
  }
  return value;
}
