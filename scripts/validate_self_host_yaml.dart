import 'dart:io';

import 'package:yaml/yaml.dart';

void main() {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final composeFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}deploy'
    '${Platform.pathSeparator}self-host${Platform.pathSeparator}'
    'docker-compose.yml',
  );
  final backendProfileFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}deploy'
    '${Platform.pathSeparator}self-host${Platform.pathSeparator}'
    'backend-profile.yaml',
  );
  final synapseFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}deploy'
    '${Platform.pathSeparator}self-host${Platform.pathSeparator}synapse'
    '${Platform.pathSeparator}closed-private.yaml',
  );
  final synapseLogFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}deploy'
    '${Platform.pathSeparator}self-host${Platform.pathSeparator}synapse'
    '${Platform.pathSeparator}log.config',
  );

  final compose = _loadMap(composeFile);
  final backendProfile = _loadMap(backendProfileFile);
  if (backendProfile['profile_version'] != 1 ||
      backendProfile['protocol'] != 'matrix-reference' ||
      backendProfile['application_backend'] != false ||
      backendProfile['custom_v1_routed'] != false ||
      backendProfile['release_eligible'] != false ||
      backendProfile['custom_v1_failure_status'] != 503) {
    throw const FormatException(
      'The Matrix reference must remain explicitly incompatible and release-blocked.',
    );
  }
  final services = compose['services'];
  if (services is! YamlMap ||
      !services.containsKey('postgres') ||
      !services.containsKey('synapse') ||
      !services.containsKey('caddy') ||
      services.containsKey('app_homeserver')) {
    throw const FormatException(
      'Compose must contain postgres, synapse, and caddy services.',
    );
  }

  final synapseService = services['synapse'];
  if (synapseService is! YamlMap) {
    throw const FormatException('The Synapse service must be a mapping.');
  }

  final caddyService = services['caddy'];
  if (caddyService is! YamlMap) {
    throw const FormatException('The Caddy service must be a mapping.');
  }

  final caddyPorts = caddyService['ports'];
  if (caddyPorts is! YamlList ||
      !caddyPorts.contains(r'${CADDY_BIND_IP:-127.0.0.1}:80:80') ||
      !caddyPorts.contains(r'${CADDY_BIND_IP:-127.0.0.1}:443:443')) {
    throw const FormatException(
      'Caddy ports must use an explicit bind IP with a loopback default.',
    );
  }

  final networks = compose['networks'];
  if (networks is! YamlMap ||
      networks['proxy'] is! YamlMap ||
      (networks['proxy'] as YamlMap)['internal'] != true ||
      networks['database'] is! YamlMap ||
      (networks['database'] as YamlMap)['internal'] != true) {
    throw const FormatException(
      'Proxy and database networks must be internal.',
    );
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

  if (synapse['registration_shared_secret'] != null ||
      synapse['enable_authenticated_media'] != true ||
      synapse['max_upload_size'] != '256M' ||
      synapse['log_config'] != '/etc/synapse/log.config') {
    throw const FormatException(
      'Registration, media, upload, and log security settings are invalid.',
    );
  }

  for (final requiredLimit in <String>[
    'rc_message',
    'rc_login',
    'rc_invites',
    'rc_media_create',
  ]) {
    if (synapse[requiredLimit] is! YamlMap) {
      throw FormatException('$requiredLimit must be explicitly configured.');
    }
  }

  final synapseLog = _loadMap(synapseLogFile);
  final loggers = synapseLog['loggers'];
  final accessLogger = loggers is YamlMap
      ? loggers['synapse.access.http']
      : null;
  if (accessLogger is! YamlMap || accessLogger['level'] != 'WARNING') {
    throw const FormatException(
      'Successful Synapse access metadata must not be logged.',
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
