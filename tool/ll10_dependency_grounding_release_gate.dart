import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/installed_dependency_grounding_service.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_builder.dart';

const _schemaName = 'll10_dependency_grounding_release_gate';

Future<void> main(List<String> args) async {
  late final Ll10DependencyGroundingGateOptions options;
  try {
    options = Ll10DependencyGroundingGateOptions.parse(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(ll10DependencyGroundingGateUsage);
    exitCode = 64;
    return;
  }

  if (options.showHelp) {
    stdout.writeln(ll10DependencyGroundingGateUsage);
    return;
  }

  final result = await buildLl10DependencyGroundingReleaseGate(
    generatedAt: DateTime.now().toUtc(),
  );
  final encoded = const JsonEncoder.withIndent('  ').convert(result.toJson());
  if (options.outJsonPath == null) {
    stdout.writeln(encoded);
  } else {
    final outJson = File(options.outJsonPath!);
    await outJson.parent.create(recursive: true);
    await outJson.writeAsString(encoded);
    stdout.writeln(
      'LL10 dependency grounding gate JSON written to ${outJson.path}',
    );
  }

  if (options.outMarkdownPath != null) {
    final outMarkdown = File(options.outMarkdownPath!);
    await outMarkdown.parent.create(recursive: true);
    await outMarkdown.writeAsString(result.toMarkdown());
    stdout.writeln(
      'LL10 dependency grounding gate Markdown written to ${outMarkdown.path}',
    );
  }

  stdout.writeln(result.toMarkdown());
  if (!result.isReady) {
    stderr.writeln(
      'LL10 dependency grounding gate blocked: '
      '${result.blockedGateIds.join(', ')}',
    );
    exitCode = 1;
  }
}

Future<Ll10DependencyGroundingGateResult>
buildLl10DependencyGroundingReleaseGate({DateTime? generatedAt}) async {
  final fixture = await Directory.systemTemp.createTemp(
    'll10_dependency_grounding_gate_',
  );
  try {
    _writeLl10Fixture(fixture);
    final service = const InstalledDependencyGroundingService();
    final dartPackage = await _resolve(service, {
      'project_path': fixture.path,
      'ecosystem': 'dart',
      'package_name': 'legacy_widget',
      'symbol': 'LegacyWidgetBuilder',
    });
    final dartSymbolOnly = await _resolve(service, {
      'project_path': fixture.path,
      'ecosystem': 'dart',
      'symbol': 'LegacyWidgetBuilder',
    });
    final dartMissingFutureSymbol = await _resolve(service, {
      'project_path': fixture.path,
      'ecosystem': 'dart',
      'package_name': 'legacy_widget',
      'symbol': 'FutureWidgetBuilder',
    });
    final nodePackage = await _resolve(service, {
      'project_path': fixture.path,
      'ecosystem': 'node',
      'package_name': '@legacy/tool',
      'symbol': 'LegacyToolClient',
    });
    final pythonPackage = await _resolve(service, {
      'project_path': fixture.path,
      'ecosystem': 'python',
      'package_name': 'legacy-requests',
      'symbol': 'LegacySession',
    });
    final vendoredPackage = await _resolve(service, {
      'project_path': fixture.path,
      'ecosystem': 'vendored',
      'package_name': 'legacy_vendor',
      'symbol': 'LegacyVendorClient',
    });
    final missingPackage = await _resolve(service, {
      'project_path': fixture.path,
      'ecosystem': 'dart',
      'package_name': 'future_widget',
    });
    final prompt = SystemPromptBuilder.build(
      now: DateTime.utc(2026, 6, 19),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      toolNames: const [
        'read_file',
        InstalledDependencyGroundingService.toolName,
      ],
      projectName: 'll10-fixture',
      projectRootPath: fixture.path,
    );

    final gates = [
      _gate(
        id: 'dart_lockfile_exact_source',
        label:
            'Dart package lookup returns the locked installed source and docs.',
        ready:
            _ok(dartPackage) &&
            _packageVersion(dartPackage) == '0.4.0' &&
            _symbolFound(dartPackage) &&
            _lockfileAccuracy(dartPackage) == 'pubspec.lock',
        evidence: [
          'ok=${dartPackage['ok']}',
          'version=${_packageVersion(dartPackage)}',
          'symbolFound=${dartPackage['symbol_found']}',
          'lockfileAccuracy=${_lockfileAccuracy(dartPackage)}',
        ],
        nextAction:
            'Fix Dart pubspec.lock/package_config source resolution for LL10.',
      ),
      _gate(
        id: 'dart_symbol_only_resolution',
        label: 'Symbol-only lookup can identify the locked Dart package.',
        ready:
            _ok(dartSymbolOnly) &&
            _packageName(dartSymbolOnly) == 'legacy_widget' &&
            _symbolFound(dartSymbolOnly),
        evidence: [
          'ok=${dartSymbolOnly['ok']}',
          'package=${_packageName(dartSymbolOnly)}',
          'symbolFound=${dartSymbolOnly['symbol_found']}',
        ],
        nextAction:
            'Search installed dependency packages when package_name is omitted.',
      ),
      _gate(
        id: 'newer_upstream_symbol_not_claimed',
        label:
            'A future-only API symbol is not reported as present in the locked package.',
        ready:
            _ok(dartMissingFutureSymbol) &&
            dartMissingFutureSymbol['symbol_found'] == false &&
            !_encoded(
              dartMissingFutureSymbol,
            ).contains('FutureWidgetBuilder()'),
        evidence: [
          'ok=${dartMissingFutureSymbol['ok']}',
          'symbolFound=${dartMissingFutureSymbol['symbol_found']}',
          'containsFutureApi=${_encoded(dartMissingFutureSymbol).contains('FutureWidgetBuilder()')}',
        ],
        nextAction:
            'Return explicit missing-symbol evidence instead of guessing upstream APIs.',
      ),
      _gate(
        id: 'node_lockfile_exact_source',
        label:
            'Node package lookup returns package-lock and node_modules data.',
        ready:
            _ok(nodePackage) &&
            _packageVersion(nodePackage) == '2.1.0' &&
            _symbolFound(nodePackage) &&
            _lockfileAccuracy(nodePackage) == 'package-lock.json',
        evidence: [
          'ok=${nodePackage['ok']}',
          'version=${_packageVersion(nodePackage)}',
          'symbolFound=${nodePackage['symbol_found']}',
          'lockfileAccuracy=${_lockfileAccuracy(nodePackage)}',
        ],
        nextAction: 'Fix package-lock/node_modules dependency grounding.',
      ),
      _gate(
        id: 'python_lockfile_exact_source',
        label:
            'Python package lookup returns requirements and site-packages data.',
        ready:
            _ok(pythonPackage) &&
            _packageVersion(pythonPackage) == '3.2.1' &&
            _symbolFound(pythonPackage) &&
            _lockfileAccuracy(pythonPackage) == 'requirements.txt',
        evidence: [
          'ok=${pythonPackage['ok']}',
          'version=${_packageVersion(pythonPackage)}',
          'symbolFound=${pythonPackage['symbol_found']}',
          'lockfileAccuracy=${_lockfileAccuracy(pythonPackage)}',
        ],
        nextAction: 'Fix requirements/site-packages dependency grounding.',
      ),
      _gate(
        id: 'vendored_source_resolution',
        label:
            'Vendored dependency lookup returns the local vendored source tree.',
        ready:
            _ok(vendoredPackage) &&
            _packageName(vendoredPackage) == 'legacy_vendor' &&
            _symbolFound(vendoredPackage) &&
            _lockfileAccuracy(vendoredPackage) == 'vendored_directory',
        evidence: [
          'ok=${vendoredPackage['ok']}',
          'package=${_packageName(vendoredPackage)}',
          'symbolFound=${vendoredPackage['symbol_found']}',
          'lockfileAccuracy=${_lockfileAccuracy(vendoredPackage)}',
        ],
        nextAction: 'Fix vendored dependency directory grounding.',
      ),
      _gate(
        id: 'offline_missing_package_blocks',
        label: 'Missing packages fail offline instead of using online docs.',
        ready:
            missingPackage['ok'] == false &&
            _encoded(missingPackage).contains('locked_package_not_found'),
        evidence: [
          'ok=${missingPackage['ok']}',
          'code=${missingPackage['code']}',
          'attempts=${_encoded(missingPackage).contains('locked_package_not_found')}',
        ],
        nextAction:
            'Keep LL10 offline-only and lockfile-bound for missing packages.',
      ),
      _gate(
        id: 'coding_prompt_guidance',
        label:
            'Coding prompts tell agents to ground third-party APIs before guessing.',
        ready:
            prompt.contains('resolve_installed_dependency') &&
            prompt.contains('before guessing') &&
            prompt.contains('lockfile-matched source and docs'),
        evidence: [
          'hasToolName=${prompt.contains('resolve_installed_dependency')}',
          'hasBeforeGuessing=${prompt.contains('before guessing')}',
          'hasLockfileDocs=${prompt.contains('lockfile-matched source and docs')}',
        ],
        nextAction:
            'Restore LL10 coding prompt guidance for dependency API lookups.',
      ),
    ];

    return Ll10DependencyGroundingGateResult(
      generatedAt: generatedAt ?? DateTime.now().toUtc(),
      fixturePath: fixture.path,
      gates: gates,
    );
  } finally {
    if (fixture.existsSync()) {
      await fixture.delete(recursive: true);
    }
  }
}

Future<Map<String, dynamic>> _resolve(
  InstalledDependencyGroundingService service,
  Map<String, dynamic> arguments,
) async {
  final decoded = jsonDecode(await service.resolve(arguments));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('LL10 grounding result was not a JSON object.');
  }
  return decoded;
}

void _writeLl10Fixture(Directory root) {
  final dartPackage = Directory.fromUri(
    root.uri.resolve('cache/legacy_widget-0.4.0/'),
  )..createSync(recursive: true);
  File.fromUri(dartPackage.uri.resolve('README.md')).writeAsStringSync(
    '# legacy_widget\n\nUse LegacyWidgetBuilder for widgets on 0.4.x.',
  );
  File.fromUri(dartPackage.uri.resolve('lib/legacy_widget.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('class LegacyWidgetBuilder {}\n');
  Directory.fromUri(root.uri.resolve('.dart_tool/')).createSync();
  File.fromUri(
    root.uri.resolve('.dart_tool/package_config.json'),
  ).writeAsStringSync(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'legacy_widget',
          'rootUri': dartPackage.uri.toString(),
          'packageUri': 'lib/',
        },
      ],
    }),
  );
  File.fromUri(root.uri.resolve('pubspec.lock')).writeAsStringSync('''
packages:
  legacy_widget:
    dependency: "direct main"
    description:
      name: legacy_widget
      url: "https://pub.dev"
    source: hosted
    version: "0.4.0"
''');

  final nodePackage = Directory.fromUri(
    root.uri.resolve('node_modules/@legacy/tool/'),
  )..createSync(recursive: true);
  File.fromUri(
    nodePackage.uri.resolve('package.json'),
  ).writeAsStringSync(jsonEncode({'name': '@legacy/tool', 'version': '2.1.0'}));
  File.fromUri(
    nodePackage.uri.resolve('index.d.ts'),
  ).writeAsStringSync('export class LegacyToolClient {}\n');
  File.fromUri(root.uri.resolve('package-lock.json')).writeAsStringSync(
    jsonEncode({
      'name': 'll10-fixture',
      'lockfileVersion': 3,
      'packages': {
        '': {'name': 'll10-fixture', 'version': '1.0.0'},
        'node_modules/@legacy/tool': {
          'version': '2.1.0',
          'resolved': 'https://registry.npmjs.org/@legacy/tool/-/tool.tgz',
          'integrity': 'sha512-fixture',
        },
      },
    }),
  );

  File.fromUri(
    root.uri.resolve('requirements.txt'),
  ).writeAsStringSync('legacy-requests==3.2.1\n');
  final sitePackages = Directory.fromUri(
    root.uri.resolve('.venv/lib/python3.11/site-packages/'),
  )..createSync(recursive: true);
  final pythonPackage = Directory.fromUri(
    sitePackages.uri.resolve('legacy_requests/'),
  )..createSync(recursive: true);
  File.fromUri(
    pythonPackage.uri.resolve('README.md'),
  ).writeAsStringSync('Use LegacySession with legacy-requests 3.2.x.');
  File.fromUri(
    pythonPackage.uri.resolve('client.py'),
  ).writeAsStringSync('class LegacySession:\n    pass\n');
  final distInfo = Directory.fromUri(
    sitePackages.uri.resolve('legacy_requests-3.2.1.dist-info/'),
  )..createSync();
  File.fromUri(
    distInfo.uri.resolve('top_level.txt'),
  ).writeAsStringSync('legacy_requests\n');

  final vendoredPackage = Directory.fromUri(
    root.uri.resolve('third_party/legacy_vendor/'),
  )..createSync(recursive: true);
  File.fromUri(
    vendoredPackage.uri.resolve('README.md'),
  ).writeAsStringSync('Use LegacyVendorClient from the vendored source tree.');
  File.fromUri(vendoredPackage.uri.resolve('lib/client.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('class LegacyVendorClient {}\n');
}

Ll10Gate _gate({
  required String id,
  required String label,
  required bool ready,
  required List<String> evidence,
  required String nextAction,
}) {
  return Ll10Gate(
    id: id,
    label: label,
    ready: ready,
    evidence: evidence,
    nextAction: nextAction,
  );
}

bool _ok(Map<String, dynamic> result) => result['ok'] == true;

bool _symbolFound(Map<String, dynamic> result) =>
    result['symbol_found'] == true;

String? _packageName(Map<String, dynamic> result) {
  final package = result['package'];
  return package is Map<String, dynamic> ? package['name'] as String? : null;
}

String? _packageVersion(Map<String, dynamic> result) {
  final package = result['package'];
  return package is Map<String, dynamic> ? package['version'] as String? : null;
}

String? _lockfileAccuracy(Map<String, dynamic> result) {
  return result['lockfile_accuracy'] as String?;
}

String _encoded(Map<String, dynamic> result) => jsonEncode(result);

class Ll10DependencyGroundingGateOptions {
  const Ll10DependencyGroundingGateOptions({
    required this.showHelp,
    this.outJsonPath,
    this.outMarkdownPath,
  });

  final bool showHelp;
  final String? outJsonPath;
  final String? outMarkdownPath;

  static Ll10DependencyGroundingGateOptions parse(List<String> args) {
    var showHelp = false;
    String? outJsonPath;
    String? outMarkdownPath;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--help':
        case '-h':
          showHelp = true;
        case '--out-json':
          i++;
          if (i >= args.length) {
            throw const FormatException('--out-json requires a path.');
          }
          outJsonPath = args[i];
        case '--out-md':
          i++;
          if (i >= args.length) {
            throw const FormatException('--out-md requires a path.');
          }
          outMarkdownPath = args[i];
        default:
          throw FormatException('Unknown argument: $arg');
      }
    }
    return Ll10DependencyGroundingGateOptions(
      showHelp: showHelp,
      outJsonPath: outJsonPath,
      outMarkdownPath: outMarkdownPath,
    );
  }
}

class Ll10DependencyGroundingGateResult {
  const Ll10DependencyGroundingGateResult({
    required this.generatedAt,
    required this.fixturePath,
    required this.gates,
  });

  final DateTime generatedAt;
  final String fixturePath;
  final List<Ll10Gate> gates;

  bool get isReady => blockedGateIds.isEmpty;

  List<String> get blockedGateIds => [
    for (final gate in gates)
      if (!gate.ready) gate.id,
  ];

  String get status => isReady ? 'ready_for_ll10_release' : 'blocked';

  Map<String, dynamic> toJson() => {
    'schemaName': _schemaName,
    'schemaVersion': 1,
    'generatedAt': generatedAt.toIso8601String(),
    'status': status,
    'fixturePath': fixturePath,
    'blockedGateIds': blockedGateIds,
    'gates': [for (final gate in gates) gate.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL10 Dependency Grounding Release Gate')
      ..writeln()
      ..writeln('- Status: `$status`')
      ..writeln('- Generated at: `${generatedAt.toIso8601String()}`')
      ..writeln('- Fixture path: `$fixturePath`')
      ..writeln();
    for (final gate in gates) {
      buffer
        ..writeln('## ${gate.label}')
        ..writeln()
        ..writeln('- Gate: `${gate.id}`')
        ..writeln('- Ready: `${gate.ready}`')
        ..writeln('- Evidence:');
      for (final item in gate.evidence) {
        buffer.writeln('  - `$item`');
      }
      if (!gate.ready) {
        buffer.writeln('- Next action: ${gate.nextAction}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}

class Ll10Gate {
  const Ll10Gate({
    required this.id,
    required this.label,
    required this.ready,
    required this.evidence,
    required this.nextAction,
  });

  final String id;
  final String label;
  final bool ready;
  final List<String> evidence;
  final String nextAction;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'ready': ready,
    'evidence': evidence,
    'nextAction': nextAction,
  };
}

const ll10DependencyGroundingGateUsage = '''
Usage: dart run tool/ll10_dependency_grounding_release_gate.dart [options]

Options:
  --out-json PATH  Write the release gate JSON report.
  --out-md PATH    Write the release gate Markdown report.
  -h, --help       Show this help.
''';
