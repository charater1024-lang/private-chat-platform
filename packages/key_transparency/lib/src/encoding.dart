import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'sha256_digest.dart';

const int maxPortableInteger = 9007199254740991;

Sha256Digest sha256Of(Iterable<int> bytes) =>
    Sha256Digest(crypto.sha256.convert(List<int>.of(bytes)).bytes);

List<int> domainBytes(String domain) => <int>[...utf8.encode(domain), 0];

List<int> encodeUint64(int value, String fieldName) {
  validatePortableInteger(value, fieldName);
  final result = List<int>.filled(8, 0);
  var remaining = value;
  for (var index = result.length - 1; index >= 0; index--) {
    result[index] = remaining % 256;
    remaining ~/= 256;
  }
  return result;
}

void validatePortableInteger(int value, String fieldName) {
  if (value < 0 || value > maxPortableInteger) {
    throw RangeError.range(value, 0, maxPortableInteger, fieldName);
  }
}

DateTime validateProtocolTime(DateTime value, String fieldName) {
  final utc = value.toUtc();
  final milliseconds = utc.millisecondsSinceEpoch;
  validatePortableInteger(milliseconds, fieldName);
  if (utc.microsecondsSinceEpoch % Duration.microsecondsPerMillisecond != 0) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must have millisecond precision',
    );
  }
  return utc;
}

List<int> checkedBytes(
  List<int> value,
  String fieldName, {
  int? exactLength,
  int? maximumLength,
  bool allowEmpty = true,
}) {
  if (exactLength != null && value.length != exactLength) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must contain exactly $exactLength bytes',
    );
  }
  if (maximumLength != null && value.length > maximumLength) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must contain at most $maximumLength bytes',
    );
  }
  if (!allowEmpty && value.isEmpty) {
    throw ArgumentError.value('<redacted>', fieldName, 'must not be empty');
  }
  for (final byte in value) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError.value(
        '<redacted>',
        fieldName,
        'must contain only byte values',
      );
    }
  }
  return List<int>.unmodifiable(value);
}

void validatePublicReference(
  String value,
  String fieldName, {
  int maximumLength = 256,
}) {
  if (value.isEmpty || value.length > maximumLength) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must contain 1 to $maximumLength characters',
    );
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x21 || codeUnit > 0x7e) {
      throw ArgumentError.value(
        '<redacted>',
        fieldName,
        'must contain printable ASCII without spaces',
      );
    }
  }
}
