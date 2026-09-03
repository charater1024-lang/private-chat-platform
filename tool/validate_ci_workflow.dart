import 'dart:io';

import 'package:yaml/yaml.dart';

Never _fail(String message) {
  stderr.writeln('CI workflow validation failed: $message');
  exit(1);
}

YamlMap _requiredMap(Object? value, String path, String label) {
  if (value is! YamlMap) {
    _fail('$path: $label must be an explicit mapping');
  }
  return value;
}

void _validateReadOnlyPermissions(YamlMap document, String path) {
  final permissions = _requiredMap(
    document['permissions'],
    path,
    'permissions',
  );
  if (permissions.length != 1 || permissions['contents'] != 'read') {
    _fail('$path: permissions must contain only contents: read');
  }
}

void _validateTriggers(YamlMap document, String path, Set<String> expected) {
  final triggers = _requiredMap(document['on'], path, 'workflow triggers');
  final actual = triggers.keys.map((key) => key.toString()).toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    _fail(
      '$path: workflow triggers must be exactly ${expected.toList()..sort()}',
    );
  }
}

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    _fail('expected at least one YAML path');
  }

  for (final path in arguments) {
    final yamlFile = File(path);
    if (!yamlFile.existsSync()) {
      _fail('file not found: $path');
    }

    late final Object? document;
    try {
      document = loadYaml(yamlFile.readAsStringSync());
    } on YamlException catch (error) {
      _fail('$path: ${error.message}');
    }

    if (document is! YamlMap) {
      _fail('$path: document root must be a mapping');
    }
    final normalizedPath = path.replaceAll('\\', '/');
    if (normalizedPath.endsWith('/source-validation.yml')) {
      _validateTriggers(document, path, const {
        'push',
        'pull_request',
        'workflow_dispatch',
      });
      _validateReadOnlyPermissions(document, path);
    } else if (normalizedPath.endsWith('/release-gate.yml')) {
      _validateTriggers(document, path, const {'workflow_dispatch'});
      _validateReadOnlyPermissions(document, path);
    }
    if (normalizedPath.endsWith('/source-validation.yml') ||
        normalizedPath.endsWith('/release-gate.yml')) {
      final jobs = _requiredMap(document['jobs'], path, 'jobs');
      if (jobs.isEmpty) {
        _fail('$path: workflow must declare at least one job');
      }
    }
  }

  stdout.writeln('CI YAML parsed successfully (${arguments.length} files).');
}
