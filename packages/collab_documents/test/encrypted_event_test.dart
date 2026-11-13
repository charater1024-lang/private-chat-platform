import 'dart:convert';

import 'package:collab_documents/collab_documents.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  test('wire round trip contains no plaintext content fields', () {
    final original = event();
    final wire = original.toServerMap();

    expect(
      wire.keys,
      isNot(
        containsAll(<String>['title', 'body', 'text', 'filename', 'email']),
      ),
    );
    final decoded = SignedCiphertextDocumentEvent.fromServerMap(wire);
    expect(decoded.metadata.documentId, original.metadata.documentId);
    expect(decoded.metadata.eventId, original.metadata.eventId);
    expect(wire['event_kind'], 'CONTENT_CHANGE');
    expect(wire, isNot(contains('causal_heads')));
    expect(decoded.ciphertext, original.ciphertext);
    expect(decoded.signature, original.signature);
  });

  test('unknown wire fields including plaintext fail closed', () {
    final wire = event().toServerMap()..['body'] = 'server-visible secret';
    expect(
      () => SignedCiphertextDocumentEvent.fromServerMap(wire),
      throwsA(
        isA<DocumentEventWireException>().having(
          (error) => error.code,
          'code',
          'invalid-field-set',
        ),
      ),
    );
    final leakedHead = event().toServerMap()
      ..['causal_heads'] = ['must-remain-inside-mls-ciphertext'];
    expect(
      () => SignedCiphertextDocumentEvent.fromServerMap(leakedHead),
      throwsA(
        isA<DocumentEventWireException>().having(
          (error) => error.code,
          'code',
          'invalid-field-set',
        ),
      ),
    );
  });

  test('non-canonical base64 and unknown algorithms are rejected', () {
    final padded = event().toServerMap();
    padded['ciphertext_b64'] = base64Url.encode([1]);
    expect(
      () => SignedCiphertextDocumentEvent.fromServerMap(padded),
      throwsA(isA<DocumentEventWireException>()),
    );

    final algorithm = event().toServerMap()..['signature_algorithm'] = 'none';
    expect(
      () => SignedCiphertextDocumentEvent.fromServerMap(algorithm),
      throwsA(isA<DocumentEventWireException>()),
    );
  });

  test('AAD is deterministic and binds domain and sequence', () {
    final first = event().metadata;
    final second = event().metadata;
    expect(first.authenticationData(), second.authenticationData());
    expect(
      first.authenticationData(),
      isNot(event(securityDomain: 2).metadata.authenticationData()),
    );
    expect(
      first.authenticationData(),
      isNot(event(sequence: 2).metadata.authenticationData()),
    );
  });

  test('malformed decrypted CRDT causal heads fail closed', () {
    expect(() => CausalHead(List<int>.filled(31, 1)), throwsArgumentError);
  });

  test('document IDs require canonical unpadded 32-byte base64url', () {
    expect(documentId().value, hasLength(43));
    expect(
      () => DocumentId(List<String>.filled(22, 'A').join()),
      throwsArgumentError,
    );
    expect(
      () => DocumentId('${List<String>.filled(42, 'A').join()}B'),
      throwsArgumentError,
    );
  });

  test('relay ciphertext uses exact 1 MiB and unpadded base64url limits', () {
    expect(SignedCiphertextDocumentEvent.maximumCiphertextBytes, 1024 * 1024);
    expect(
      SignedCiphertextDocumentEvent.maximumCiphertextBase64UrlLength,
      1398102,
    );
    final maximumEvent = event(
      ciphertext: List<int>.filled(
        SignedCiphertextDocumentEvent.maximumCiphertextBytes,
        1,
      ),
    );
    final maximumWire = maximumEvent.toServerMap();
    final maximum = maximumWire['ciphertext_b64']! as String;
    expect(
      maximum.length,
      SignedCiphertextDocumentEvent.maximumCiphertextBase64UrlLength,
    );
    expect(maximum, isNot(contains('=')));
    expect(
      SignedCiphertextDocumentEvent.fromServerMap(maximumWire)
          .ciphertext
          .length,
      SignedCiphertextDocumentEvent.maximumCiphertextBytes,
    );
    final overEncodedLimit = event().toServerMap()
      ..['ciphertext_b64'] = List.filled(
        SignedCiphertextDocumentEvent.maximumCiphertextBase64UrlLength + 1,
        'A',
      ).join();
    expect(
      () => SignedCiphertextDocumentEvent.fromServerMap(overEncodedLimit),
      throwsA(isA<DocumentEventWireException>()),
    );
    expect(
      () => event(
        ciphertext: List<int>.filled(
          SignedCiphertextDocumentEvent.maximumCiphertextBytes + 1,
          1,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('signature payload covers ciphertext and metadata', () {
    final original = event(ciphertext: [1, 2, 3]);
    final changedCiphertext = event(ciphertext: [1, 2, 4]);
    final changedSequence = event(sequence: 2, ciphertext: [1, 2, 3]);
    expect(
      original.signaturePayload(),
      isNot(changedCiphertext.signaturePayload()),
    );
    expect(
      original.signaturePayload(),
      isNot(changedSequence.signaturePayload()),
    );
  });

  test('sensitive values are redacted from string output', () {
    expect(documentId().toString(), isNot(contains(documentId().value)));
    expect(event().toString(), isNot(contains('ciphertext')));
    expect(head(7).toString(), 'CausalHead(<redacted>)');
  });

  test('wire parser checks integer types and signature size', () {
    final wrongType = event().toServerMap()..['device_sequence'] = 1.0;
    expect(
      () => SignedCiphertextDocumentEvent.fromServerMap(wrongType),
      throwsA(isA<DocumentEventWireException>()),
    );
    expect(
      () => event(signature: List<int>.filled(63, 1)),
      throwsArgumentError,
    );
  });
}
