import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = _findPackageRoot();

  test(
    'broad and homeserver sources cannot import client plaintext models',
    () {
      final guardedFiles = <File>[
        File('${packageRoot.path}/lib/chat_core.dart'),
        ...Directory('${packageRoot.path}/lib/src')
            .listSync()
            .whereType<File>()
            .where((file) {
              final name = file.uri.pathSegments.last;
              return name.contains('homeserver') ||
                  name == 'encrypted_transport.dart' ||
                  name == 'invitation_proof.dart';
            }),
      ];

      for (final file in guardedFiles) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('local_message_features.dart')),
          reason: '${file.path} must not import or export plaintext models',
        );
        expect(
          source,
          isNot(contains('chat_client.dart')),
          reason: '${file.path} must not import the client-only barrel',
        );
      }
    },
  );

  test('plaintext contracts are exported only by client product barrels', () {
    final broad = File('${packageRoot.path}/lib/chat_core.dart')
        .readAsStringSync();
    final client = File('${packageRoot.path}/lib/chat_client.dart')
        .readAsStringSync();
    final privacy = File('${packageRoot.path}/lib/privacy_chat_core.dart')
        .readAsStringSync();
    final secure = File('${packageRoot.path}/lib/secure_chat_core.dart')
        .readAsStringSync();

    expect(broad, isNot(contains('local_message_features.dart')));
    expect(client, contains("export 'src/local_message_features.dart';"));
    expect(privacy, contains("export 'src/local_message_features.dart';"));
    expect(secure, contains("export 'src/local_message_features.dart';"));
  });
}

Directory _findPackageRoot() {
  final direct = Directory.current;
  if (File('${direct.path}/lib/chat_core.dart').existsSync()) {
    return direct;
  }
  final workspaceRelative = Directory('${direct.path}/packages/chat_core');
  if (File('${workspaceRelative.path}/lib/chat_core.dart').existsSync()) {
    return workspaceRelative;
  }
  throw StateError('chat_core package root was not found');
}
