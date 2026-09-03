import 'dart:io';

import 'package:yaml/yaml.dart';

void main() {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final composeFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}deploy'
    '${Platform.pathSeparator}self-host${Platform.pathSeparator}'
    'docker-compose.yml',
  );
  final synapseFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}deploy'
    '${Platform.pathSeparator}self-host${Platform.pathSeparator}synapse'
    '${Platform.pathSeparator}closed-private.yaml',
  );

  final compose = _loadMap(composeFile);
  final services = compose['services'];
  if (services is! YamlMap ||
      !services.containsKey('postgres') ||
      !services.containsKey('synapse') ||
      !services.containsKey('caddy')) {
    throw const FormatException(
      'Compose must contain postgres, synapse, and caddy services.',
    );
  }

  final synapseService = services['synapse'];
  if (synapseService is! YamlMap) {
    throw const FormatException('The Synapse service must be a mapping.');
  }

  final synapseCommand = synapseService['command'];
  if (synapseCommand is! YamlList ||
      synapseCommand.isEmpty ||
      synapseCommand.last !=
          '--config-path=/run/secrets/synapse_database.yaml') {
    throw const FormatException(
      'Synapse must load its database Docker secret as the final config.',
    );
  }

  final synapseSecrets = synapseService['secrets'];
  final mountsDatabaseSecret =
      synapseSecrets is YamlList &&
      synapseSecrets.any(
        (entry) => entry is YamlMap && entry['source'] == 'synapse_database',
      );
  if (!mountsDatabaseSecret) {
    throw const FormatException(
      'Synapse must mount the synapse_database Compose secret.',
    );
  }

  final composeSecrets = compose['secrets'];
  final databaseSecret = composeSecrets is YamlMap
      ? composeSecrets['synapse_database']
      : null;
  if (databaseSecret is! YamlMap ||
      databaseSecret['file'] != './runtime/secrets/synapse_database.yaml') {
    throw const FormatException(
      'Compose must declare the gitignored Synapse database secret file.',
    );
  }

  final synapse = _loadMap(synapseFile);
  final listeners = synapse['listeners'];
  if (listeners is! YamlList || listeners.length != 1) {
    throw const FormatException(
      'The closed profile must define exactly one listener.',
    );
  }

  final listener = listeners.single;
  if (listener is! YamlMap || listener['port'] != 8008) {
    throw const FormatException(
      'The closed listener must use internal port 8008.',
    );
  }

  final push = synapse['push'];
  if (push is! YamlMap ||
      push['enabled'] != false ||
      push['include_content'] != false) {
    throw const FormatException(
      'Native Synapse push must remain disabled and exclude content.',
    );
  }

  stdout.writeln('Self-host YAML syntax and structure passed.');
}

YamlMap _loadMap(File file) {
  if (!file.existsSync()) {
    throw FileSystemException('Required YAML file does not exist', file.path);
  }

  final document = loadYaml(file.readAsStringSync());
  if (document is! YamlMap) {
    throw FormatException('${file.path} must contain a YAML mapping.');
  }
  return document;
}
