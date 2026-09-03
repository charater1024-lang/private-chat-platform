import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:homeserver_client/homeserver_client.dart';

const testServerRef = 'server_reference_0001';
const testSecurityDomain = 'security_domain_0001';
const testPolicyVersion = 'policy.1';
const testConversationId = 'conversation_ref_0001';
const testDeviceRef = 'owner_device_00001';
const testToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

/// JSON-round-tripping CAS store used to model durable process restoration.
final class MemoryPreparedRequestStore implements PreparedRequestStore {
  MemoryPreparedRequestStore();

  MemoryPreparedRequestStore.restore(String persistenceRepresentation)
    : _serialized = persistenceRepresentation;

  String? _serialized;
  bool rejectWrites = false;
  void Function(PreparedRequestStoreSnapshot snapshot)? beforeWrite;

  @override
  Future<PreparedRequestStoreSnapshot?> read() async {
    final serialized = _serialized;
    if (serialized == null) return null;
    final decoded = jsonDecode(serialized)! as Map<String, Object?>;
    return PreparedRequestStoreSnapshot.fromJson(decoded);
  }

  @override
  Future<void> writeAtomically(
    PreparedRequestStoreSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if (rejectWrites) {
      throw const PreparedRequestStoreConflictException();
    }
    final serialized = _serialized;
    final currentGeneration = serialized == null
        ? 0
        : (jsonDecode(serialized)! as Map<String, Object?>)['generation']!
              as int;
    if (currentGeneration != expectedGeneration) {
      throw const PreparedRequestStoreConflictException();
    }
    beforeWrite?.call(snapshot);
    _serialized = jsonEncode(snapshot.toJson());
  }

  int get requestCount {
    final serialized = _serialized;
    if (serialized == null) return 0;
    final decoded = jsonDecode(serialized)! as Map<String, Object?>;
    return (decoded['requests']! as List<Object?>).length;
  }

  String get persistenceRepresentation => _serialized ?? '';

  void replacePersistenceRepresentationForTesting(String value) {
    _serialized = value;
  }

  @override
  String toString() => 'MemoryPreparedRequestStore(data: <redacted>)';
}

final class FakeHomeserver {
  HttpServer? _server;
  final Map<String, _StoredIdempotency> _idempotency = {};

  Map<String, Object?> profile = defaultProfile();
  final List<Map<String, Object?>> messages = [];
  final List<CapturedRequest> requests = [];
  int resourceVersion = 1;
  int conversationGets = 0;
  int? profileStatus;
  int? conversationStatus;
  int? sendStatus;
  int? pullStatus;
  String? retryAfter;
  bool redirectProfile = false;
  bool malformedProfile = false;
  bool oversizedProfile = false;
  bool chunkedOversizedProfile = false;
  bool loseFirstSendAcknowledgement = false;
  bool _acknowledgementLost = false;
  Duration responseDelay = Duration.zero;

  Uri get baseUri {
    final server = _server;
    if (server == null) throw StateError('not started');
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );
  }

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await _read(request);
    requests.add(
      CapturedRequest(
        method: request.method,
        path: request.uri.path,
        query: Map.unmodifiable(request.uri.queryParameters),
        authorization: request.headers.value(HttpHeaders.authorizationHeader),
        idempotencyKey: request.headers.value('idempotency-key'),
        body: body,
      ),
    );
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }

    if (request.uri.path == '/v1/homeserver/profile') {
      if (redirectProfile) {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/redirect-target');
        await request.response.close();
        return;
      }
      if (malformedProfile) {
        await _rawJson(request, HttpStatus.ok, utf8.encode('{malformed'));
        return;
      }
      if (oversizedProfile || chunkedOversizedProfile) {
        final bytes = Uint8List.fromList(List<int>.filled(70 * 1024, 65));
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json;
        if (!chunkedOversizedProfile) {
          request.response.contentLength = bytes.length;
        }
        request.response.add(bytes);
        await request.response.close();
        return;
      }
      await _json(
        request,
        profileStatus ?? HttpStatus.ok,
        profileStatus == null
            ? profile
            : {'error': 'secret-response-body-must-not-leak'},
      );
      return;
    }

    if (request.uri.path == '/v1/conversations/$testConversationId' &&
        request.method == 'GET') {
      conversationGets += 1;
      if (conversationStatus != null) {
        await _json(request, conversationStatus!, {'error': 'hidden'});
        return;
      }
      request.response.headers.set(
        HttpHeaders.etagHeader,
        '"$resourceVersion"',
      );
      await _json(request, HttpStatus.ok, {
        'conversation_id': testConversationId,
        'conversation_kind': 'DIRECT',
        'security_domain_id': testSecurityDomain,
        'product_kind': 'PRIVACY_CONSUMER',
        'mode': 'TRUE_E2EE',
        'policy_version': testPolicyVersion,
        'member_refs': ['owner_member_000001', 'peer_member_0000001'],
        'resource_version': resourceVersion,
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      });
      return;
    }

    if (request.uri.path == '/v1/conversations/$testConversationId/messages') {
      if (request.method == 'POST') {
        await _send(request, body);
        return;
      }
      if (request.method == 'GET') {
        if (pullStatus != null) {
          await _json(request, pullStatus!, {'error': 'hidden'});
          return;
        }
        final supplied = request.uri.queryParameters['sync_cursor'];
        final offset = supplied == null ? 0 : _cursorOffset(supplied);
        final limit = int.parse(request.uri.queryParameters['limit']!);
        final end = (offset + limit) < messages.length
            ? offset + limit
            : messages.length;
        final next = end == offset && supplied != null
            ? supplied
            : _cursor(end);
        await _json(request, HttpStatus.ok, {
          'messages': messages.sublist(offset, end),
          'next_sync_cursor': next,
          'has_more': end < messages.length,
        });
        return;
      }
    }

    await _json(request, HttpStatus.notFound, {'error': 'hidden'});
  }

  Future<void> _send(HttpRequest request, Uint8List body) async {
    if (sendStatus != null) {
      if (retryAfter != null) {
        request.response.headers.set(HttpHeaders.retryAfterHeader, retryAfter!);
      }
      await _json(request, sendStatus!, {'error': 'hidden'});
      return;
    }
    final key = request.headers.value('idempotency-key')!;
    final prior = _idempotency[key];
    if (prior != null) {
      if (!_same(body, prior.body)) {
        await _json(request, HttpStatus.conflict, {'error': 'hidden'});
        return;
      }
      request.response.headers.set(
        HttpHeaders.etagHeader,
        '"${prior.response['resource_version']}"',
      );
      await _json(request, HttpStatus.accepted, prior.response);
      return;
    }
    final decoded = jsonDecode(utf8.decode(body))! as Map<String, Object?>;
    if (decoded['expected_version'] != resourceVersion) {
      await _json(request, HttpStatus.preconditionFailed, {'error': 'hidden'});
      return;
    }
    final sequence = messages.length + 1;
    final serverEventId = 'server_event_${sequence.toString().padLeft(8, '0')}';
    resourceVersion += 1;
    final response = <String, Object?>{
      'receipt_ref': 'receipt_ref_${sequence.toString().padLeft(8, '0')}',
      'server_event_id': serverEventId,
      'conversation_sequence': sequence,
      'resource_version': resourceVersion,
      'accepted_at': DateTime.utc(2026, 1, 1, 0, sequence).toIso8601String(),
    };
    messages.add({
      ...decoded,
      'server_event_id': serverEventId,
      'conversation_sequence': sequence,
    });
    _idempotency[key] = _StoredIdempotency(body, response);

    if (loseFirstSendAcknowledgement && !_acknowledgementLost) {
      _acknowledgementLost = true;
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    request.response.headers.set(HttpHeaders.etagHeader, '"$resourceVersion"');
    await _json(request, HttpStatus.accepted, response);
  }

  Future<Uint8List> _read(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) => _rawJson(request, status, utf8.encode(jsonEncode(body)));

  Future<void> _rawJson(HttpRequest request, int status, List<int> body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..contentLength = body.length
      ..add(body);
    await request.response.close();
  }

  static String _cursor(int offset) =>
      'cursor_reference_${offset.toString().padLeft(8, '0')}';

  static int _cursorOffset(String value) => int.parse(value.split('_').last);

  static Map<String, Object?> defaultProfile() => {
    'server_ref': testServerRef,
    'display_name': 'Test home server',
    'product_kind': 'PRIVACY_CONSUMER',
    'mode': 'TRUE_E2EE',
    'security_domain_id': testSecurityDomain,
    'policy_version': testPolicyVersion,
    'ownership_model': 'PERSONALLY_OWNED',
    'network_scope': 'CLOSED_HOMESERVER',
    'federation_enabled': false,
    'registration_mode': 'INVITE_ONLY',
    'member_conversation_creation': 'ENABLED_FOR_ACTIVE_MEMBERS',
    'server_can_decrypt_message_content': false,
    'default_locale': 'ko',
    'supported_locales': ['ko', 'en'],
    'encrypted_media_enabled': true,
    'key_transparency_enabled': true,
    'blockchain_checkpoint_anchoring': 'DISABLED',
  };
}

final class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.idempotencyKey,
    required Uint8List body,
  }) : body = Uint8List.fromList(body);

  final String method;
  final String path;
  final Map<String, String> query;
  final String? authorization;
  final String? idempotencyKey;
  final Uint8List body;

  @override
  String toString() => 'CapturedRequest(<redacted>)';
}

final class _StoredIdempotency {
  _StoredIdempotency(Uint8List body, Map<String, Object?> response)
    : body = Uint8List.fromList(body),
      response = Map.unmodifiable(response);

  final Uint8List body;
  final Map<String, Object?> response;
}

bool _same(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
