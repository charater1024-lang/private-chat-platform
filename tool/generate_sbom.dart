import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _supportedSdkPackages = <String>{
  'flutter',
  'flutter_localizations',
  'flutter_test',
  'flutter_web_plugins',
  'sky_engine',
};

void main(List<String> arguments) {
  try {
    final options = _Options.parse(arguments);
    final workspace = Directory.current;
    final document = _buildBom(workspace);
    final output = '${const JsonEncoder.withIndent('  ').convert(document)}\n';

    // Parse our own output before publishing it so serialization regressions
    // cannot leave a malformed release artifact behind.
    final decoded = jsonDecode(output) as Map<String, Object?>;
    final components = decoded['components']! as List<Object?>;
    if (options.checkOnly) {
      stdout.writeln(
        'CycloneDX SBOM input validated: ${components.length} locked components.',
      );
      return;
    }

    final target = File(_resolveOutput(workspace, options.outputPath!));
    target.parent.createSync(recursive: true);
    final temporary = File('${target.path}.tmp.$pid');
    try {
      temporary.writeAsStringSync(output, flush: true);
      // File.rename replaces an existing file on supported Dart platforms.
      // Keeping replacement in one operation avoids an avoidable no-SBOM gap.
      temporary.renameSync(target.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
    stdout.writeln(
      'CycloneDX SBOM written with ${components.length} locked components.',
    );
  } on _SbomException catch (error) {
    stderr.writeln('SBOM generation failed: ${error.message}');
    exitCode = 1;
  } on Object {
    // Input paths and dependency contents can be sensitive on developer
    // machines. Keep failures deliberately generic at this boundary.
    stderr.writeln('SBOM generation failed: invalid release input.');
    exitCode = 1;
  }
}

Map<String, Object?> _buildBom(Directory workspace) {
  final lockFile = File(
    '${workspace.path}${Platform.pathSeparator}pubspec.lock',
  );
  final rootManifest = File(
    '${workspace.path}${Platform.pathSeparator}pubspec.yaml',
  );
  final everydayManifest = File(
    '${workspace.path}${Platform.pathSeparator}apps'
    '${Platform.pathSeparator}everyday_chat${Platform.pathSeparator}pubspec.yaml',
  );
  final collabManifest = File(
    '${workspace.path}${Platform.pathSeparator}apps'
    '${Platform.pathSeparator}secure_collab${Platform.pathSeparator}pubspec.yaml',
  );
  final cargoLocks = <({String relativePath, File file, String rootPackage})>[
    (
      relativePath: 'native/openmls_bridge/Cargo.lock',
      file: File(
        '${workspace.path}${Platform.pathSeparator}native'
        '${Platform.pathSeparator}openmls_bridge'
        '${Platform.pathSeparator}Cargo.lock',
      ),
      rootPackage: 'privacy_chat_openmls_bridge',
    ),
    (
      relativePath: 'native/collab_crdt_bridge/Cargo.lock',
      file: File(
        '${workspace.path}${Platform.pathSeparator}native'
        '${Platform.pathSeparator}collab_crdt_bridge'
        '${Platform.pathSeparator}Cargo.lock',
      ),
      rootPackage: 'privacy_chat_collab_crdt',
    ),
  ];
  if (!lockFile.existsSync() ||
      !rootManifest.existsSync() ||
      !everydayManifest.existsSync() ||
      !collabManifest.existsSync() ||
      cargoLocks.any((lock) => !lock.file.existsSync())) {
    throw const _SbomException('run this tool from the workspace root');
  }

  final root = _yamlMap(lockFile.readAsStringSync(), 'lockfile');
  final packages = root['packages'];
  if (packages is! YamlMap || packages.isEmpty) {
    throw const _SbomException('lockfile packages are missing');
  }
  final sdkConstraints = root['sdks'];
  if (sdkConstraints is! YamlMap ||
      sdkConstraints['dart'] is! String ||
      sdkConstraints['flutter'] is! String) {
    throw const _SbomException('lockfile SDK constraints are missing');
  }

  final everydayVersion = _manifestVersion(everydayManifest);
  final collabVersion = _manifestVersion(collabManifest);
  if (everydayVersion != collabVersion) {
    throw const _SbomException('release app versions must match');
  }

  final components = <Map<String, Object?>>[];
  for (final entry in packages.entries) {
    final lockName = entry.key;
    final value = entry.value;
    if (lockName is! String || value is! YamlMap) {
      throw const _SbomException('lockfile contains a malformed package');
    }
    final version = value['version'];
    final dependency = value['dependency'];
    final source = value['source'];
    if (version is! String || dependency is! String || source is! String) {
      throw const _SbomException('lockfile package metadata is incomplete');
    }
    switch (source) {
      case 'hosted':
        components.add(
          _hostedComponent(
            lockName: lockName,
            version: version,
            dependency: dependency,
            description: value['description'],
          ),
        );
      case 'sdk':
        if (!_supportedSdkPackages.contains(lockName)) {
          throw const _SbomException(
            'lockfile contains an unknown SDK package',
          );
        }
        components.add(
          _sdkComponent(
            name: lockName,
            version: version,
            dependency: dependency,
          ),
        );
      default:
        // Git/path dependencies are not reproducible from this lockfile alone.
        // A future reviewed source-provenance format must be implemented before
        // they are permitted in a release SBOM.
        throw const _SbomException('lockfile contains an unsupported source');
    }
  }
  components.addAll(_cargoComponents(cargoLocks));
  components.sort(
    (left, right) =>
        (left['bom-ref']! as String).compareTo(right['bom-ref']! as String),
  );

  final applicationRef =
      'pkg:generic/private-chat-platform@${Uri.encodeComponent(everydayVersion)}';
  return <String, Object?>{
    r'$schema': 'https://cyclonedx.org/schema/bom-1.5.schema.json',
    'bomFormat': 'CycloneDX',
    'specVersion': '1.5',
    'version': 1,
    'metadata': <String, Object?>{
      'component': <String, Object?>{
        'type': 'application',
        'bom-ref': applicationRef,
        'name': 'private-chat-platform',
        'version': everydayVersion,
        'purl': applicationRef,
        'properties': <Map<String, String>>[
          {
            'name': 'chat-platform:products',
            'value': 'everyday_chat,secure_collab',
          },
          {
            'name': 'chat-platform:dart-constraint',
            'value': sdkConstraints['dart']! as String,
          },
          {
            'name': 'chat-platform:flutter-constraint',
            'value': sdkConstraints['flutter']! as String,
          },
        ],
      },
    },
    'components': components,
    'dependencies': <Map<String, Object?>>[
      <String, Object?>{
        'ref': applicationRef,
        'dependsOn': components
            .map((component) => component['bom-ref']! as String)
            .toList(growable: false),
      },
    ],
  };
}

List<Map<String, Object?>> _cargoComponents(
  List<({String relativePath, File file, String rootPackage})> locks,
) {
  final packagesByReference = <String, _CargoLockedPackage>{};
  for (final lock in locks) {
    final packages = _parseCargoLock(
      lock.file.readAsStringSync(),
      relativePath: lock.relativePath,
      expectedRootPackage: lock.rootPackage,
    );
    for (final package in packages) {
      final existing = packagesByReference[package.reference];
      if (existing == null) {
        packagesByReference[package.reference] = package;
        continue;
      }
      if (existing.name != package.name ||
          existing.version != package.version ||
          existing.checksum != package.checksum ||
          existing.isWorkspacePackage != package.isWorkspacePackage) {
        throw const _SbomException(
          'Cargo lockfiles disagree about a package identity',
        );
      }
      existing.lockfiles.addAll(package.lockfiles);
    }
  }

  return packagesByReference.values
      .map((package) {
        final lockfiles = package.lockfiles.toList()..sort();
        final properties = <Map<String, String>>[
          {'name': 'chat-platform:dependency-scope', 'value': 'native-runtime'},
          {
            'name': 'chat-platform:source',
            'value': package.isWorkspacePackage ? 'workspace' : 'crates.io',
          },
          {'name': 'chat-platform:lockfiles', 'value': lockfiles.join(',')},
        ];
        if (package.isWorkspacePackage) {
          return <String, Object?>{
            'type': 'library',
            'bom-ref': package.reference,
            'group': 'chat-platform-native',
            'name': package.name,
            'version': package.version,
            'purl': package.reference,
            'properties': properties,
          };
        }
        return <String, Object?>{
          'type': 'library',
          'bom-ref': package.reference,
          'group': 'crates.io',
          'name': package.name,
          'version': package.version,
          'hashes': <Map<String, String>>[
            {'alg': 'SHA-256', 'content': package.checksum!},
          ],
          'purl': package.reference,
          'externalReferences': <Map<String, String>>[
            {
              'type': 'distribution',
              'url':
                  'https://crates.io/crates/${package.name}/${package.version}',
            },
          ],
          'properties': properties,
        };
      })
      .toList(growable: false);
}

List<_CargoLockedPackage> _parseCargoLock(
  String source, {
  required String relativePath,
  required String expectedRootPackage,
}) {
  if (!RegExp(r'^version\s*=\s*4\s*$', multiLine: true).hasMatch(source)) {
    throw const _SbomException('Cargo lockfile version must be 4');
  }
  final blocks = source
      .split(RegExp(r'^\[\[package\]\]\r?$', multiLine: true))
      .skip(1);
  final result = <_CargoLockedPackage>[];
  var rootCount = 0;
  for (final body in blocks) {
    final name = _requiredTomlString(body, 'name');
    final version = _requiredTomlString(body, 'version');
    if (!_cargoPackageName.hasMatch(name) || !_version.hasMatch(version)) {
      throw const _SbomException('Cargo package name or version is invalid');
    }
    final packageSource = _optionalTomlString(body, 'source');
    final checksum = _optionalTomlString(body, 'checksum');
    if (packageSource == null) {
      if (name != expectedRootPackage || checksum != null) {
        throw const _SbomException(
          'Cargo lockfile contains an unexpected workspace package',
        );
      }
      rootCount += 1;
      result.add(
        _CargoLockedPackage.workspace(
          name: name,
          version: version,
          lockfile: relativePath,
        ),
      );
      continue;
    }
    if (packageSource !=
            'registry+https://github.com/rust-lang/crates.io-index' ||
        checksum == null ||
        !_sha256.hasMatch(checksum)) {
      throw const _SbomException(
        'Cargo dependency must use the checksummed crates.io registry',
      );
    }
    result.add(
      _CargoLockedPackage.registry(
        name: name,
        version: version,
        checksum: checksum,
        lockfile: relativePath,
      ),
    );
  }
  if (rootCount != 1 || result.isEmpty) {
    throw const _SbomException('Cargo lockfile package set is incomplete');
  }
  return result;
}

String _requiredTomlString(String body, String field) {
  final value = _optionalTomlString(body, field);
  if (value == null) {
    throw _SbomException('Cargo package metadata is missing $field');
  }
  return value;
}

String? _optionalTomlString(String body, String field) {
  final prefix = '$field = "';
  for (final rawLine in const LineSplitter().convert(body)) {
    final line = rawLine.trim();
    if (!line.startsWith(prefix) || !line.endsWith('"')) continue;
    final value = line.substring(prefix.length, line.length - 1);
    if (value.isEmpty || value.contains('"')) return null;
    return value;
  }
  return null;
}

Map<String, Object?> _hostedComponent({
  required String lockName,
  required String version,
  required String dependency,
  required Object? description,
}) {
  if (description is! YamlMap ||
      description['name'] != lockName ||
      description['url'] != 'https://pub.dev') {
    throw const _SbomException('hosted package identity is not canonical');
  }
  final digest = description['sha256'];
  if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
    throw const _SbomException('hosted package digest is not canonical');
  }
  if (!_packageName.hasMatch(lockName) || !_version.hasMatch(version)) {
    throw const _SbomException('hosted package name or version is invalid');
  }
  final purl =
      'pkg:pub/${Uri.encodeComponent(lockName)}@${Uri.encodeComponent(version)}';
  return <String, Object?>{
    'type': 'library',
    'bom-ref': purl,
    'group': 'pub.dev',
    'name': lockName,
    'version': version,
    'hashes': <Map<String, String>>[
      {'alg': 'SHA-256', 'content': digest},
    ],
    'purl': purl,
    'externalReferences': <Map<String, String>>[
      {'type': 'distribution', 'url': 'https://pub.dev/packages/$lockName'},
    ],
    'properties': <Map<String, String>>[
      {'name': 'chat-platform:dependency-scope', 'value': dependency},
      {'name': 'chat-platform:source', 'value': 'hosted'},
    ],
  };
}

Map<String, Object?> _sdkComponent({
  required String name,
  required String version,
  required String dependency,
}) {
  final reference = 'urn:chat-platform:sdk-package:$name';
  return <String, Object?>{
    'type': 'framework',
    'bom-ref': reference,
    'group': 'dart.dev',
    'name': name,
    'version': version,
    'properties': <Map<String, String>>[
      {'name': 'chat-platform:dependency-scope', 'value': dependency},
      {'name': 'chat-platform:source', 'value': 'sdk'},
    ],
  };
}

String _manifestVersion(File file) {
  final manifest = _yamlMap(file.readAsStringSync(), 'manifest');
  final version = manifest['version'];
  if (version is! String || !_appVersion.hasMatch(version)) {
    throw const _SbomException('release app version is missing or invalid');
  }
  return version;
}

YamlMap _yamlMap(String source, String label) {
  final value = loadYaml(source);
  if (value is! YamlMap) {
    throw _SbomException('$label root must be a mapping');
  }
  return value;
}

String _resolveOutput(Directory workspace, String path) {
  final separator = Platform.pathSeparator;
  final normalized = path.replaceAll(RegExp(r'[/\\]'), separator);
  final segments = normalized.split(separator);
  if (File(path).isAbsolute ||
      segments.length < 2 ||
      segments.first.toLowerCase() != 'build' ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw const _SbomException(
      'output must stay under the workspace build directory',
    );
  }

  final canonicalWorkspace = Directory(workspace.resolveSymbolicLinksSync());
  final buildDirectory = Directory('${workspace.path}${separator}build')
      .absolute;
  if (!buildDirectory.existsSync()) {
    buildDirectory.createSync();
  }
  final canonicalBuild = Directory(buildDirectory.resolveSymbolicLinksSync());
  final expectedCanonicalBuild = Directory(
    '${canonicalWorkspace.path}${separator}build',
  ).absolute;
  if (!_samePath(canonicalBuild.path, expectedCanonicalBuild.path)) {
    throw const _SbomException(
      'workspace build directory must not redirect through a link',
    );
  }

  final target = File('${workspace.path}$separator$normalized').absolute;
  var existingAncestor = target.parent;
  while (!existingAncestor.existsSync()) {
    final parent = existingAncestor.parent;
    if (_samePath(parent.path, existingAncestor.path)) {
      throw const _SbomException('output parent cannot be resolved safely');
    }
    existingAncestor = parent;
  }
  final canonicalAncestor = Directory(
    existingAncestor.resolveSymbolicLinksSync(),
  );
  if (!_isWithin(canonicalBuild.path, canonicalAncestor.path)) {
    throw const _SbomException(
      'output parent must not redirect outside the workspace build directory',
    );
  }
  return target.path;
}

bool _samePath(String left, String right) =>
    _normalizedAbsolutePath(left) == _normalizedAbsolutePath(right);

bool _isWithin(String root, String candidate) {
  final normalizedRoot = _normalizedAbsolutePath(root);
  final normalizedCandidate = _normalizedAbsolutePath(candidate);
  return normalizedCandidate == normalizedRoot ||
      normalizedCandidate.startsWith(
        '$normalizedRoot${Platform.pathSeparator}',
      );
}

String _normalizedAbsolutePath(String path) {
  var result = File(path).absolute.path;
  while (result.length > 1 && (result.endsWith('/') || result.endsWith(r'\'))) {
    result = result.substring(0, result.length - 1);
  }
  return Platform.isWindows ? result.toLowerCase() : result;
}

final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');
final _cargoPackageName = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.+-]*$');
final _version = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,127}$');
final _appVersion = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$');
final _sha256 = RegExp(r'^[a-f0-9]{64}$');

final class _CargoLockedPackage {
  _CargoLockedPackage._({
    required this.name,
    required this.version,
    required this.checksum,
    required this.isWorkspacePackage,
    required String lockfile,
  }) : lockfiles = {lockfile};

  factory _CargoLockedPackage.registry({
    required String name,
    required String version,
    required String checksum,
    required String lockfile,
  }) => _CargoLockedPackage._(
    name: name,
    version: version,
    checksum: checksum,
    isWorkspacePackage: false,
    lockfile: lockfile,
  );

  factory _CargoLockedPackage.workspace({
    required String name,
    required String version,
    required String lockfile,
  }) => _CargoLockedPackage._(
    name: name,
    version: version,
    checksum: null,
    isWorkspacePackage: true,
    lockfile: lockfile,
  );

  final String name;
  final String version;
  final String? checksum;
  final bool isWorkspacePackage;
  final Set<String> lockfiles;

  String get reference => isWorkspacePackage
      ? 'pkg:generic/${Uri.encodeComponent(name)}@${Uri.encodeComponent(version)}'
      : 'pkg:cargo/${Uri.encodeComponent(name)}@${Uri.encodeComponent(version)}';
}

final class _Options {
  const _Options._({required this.checkOnly, required this.outputPath});

  factory _Options.parse(List<String> arguments) {
    var checkOnly = false;
    String? output;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument == '--check') {
        checkOnly = true;
        continue;
      }
      if (argument == '--output' && index + 1 < arguments.length) {
        output = arguments[++index];
        continue;
      }
      throw const _SbomException('usage: --check or --output <build path>');
    }
    if (checkOnly == (output != null)) {
      throw const _SbomException('choose exactly one of --check or --output');
    }
    return _Options._(checkOnly: checkOnly, outputPath: output);
  }

  final bool checkOnly;
  final String? outputPath;
}

final class _SbomException implements Exception {
  const _SbomException(this.message);

  final String message;
}
