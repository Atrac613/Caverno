import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_session_registry.dart';
import 'package:caverno/features/chat/data/datasources/lsp_server_command_resolver.dart';
import 'package:caverno/features/chat/domain/services/dart_project_tooling.dart';
import 'package:caverno/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart';

const ll11LspLanguageServerSmokeSchemaName =
    'll11_lsp_language_server_smoke_summary';
const ll11LspLanguageServerSmokeCanaryName = 'll11_lsp_language_server_smoke';
const ll11LspLanguageServerSmokeSurface = 'lsp_language_server_bridge';

const ll11LspLanguageServerSmokeUsage = '''
Usage: dart run tool/ll11_lsp_language_server_smoke.dart [options]

Runs real local language-server processes through the LL11 JSON-RPC bridge.

Options:
  --language LANGUAGE       Language to probe. Can be repeated or comma-separated.
  --languages LIST         Alias for comma-separated --language values.
  --require-language-server
                            Fail when no selected language server passes.
  --work-root PATH         Keep smoke fixtures under PATH.
  --out-json PATH          Write the JSON summary to PATH.
  --out-md PATH            Write the Markdown summary to PATH.
  --diagnostic-timeout-ms N
                            Milliseconds to wait for publishDiagnostics.
  --symbol-timeout-ms N    Milliseconds to wait for documentSymbol responses.
  --definition-timeout-ms N
                            Milliseconds to wait for go-to-definition responses.
  --command TEXT           Command string recorded in the summary.
  --help                   Show this help.

Supported languages: dart, typescript, python, swift.
''';

Future<void> main(List<String> args) async {
  late final Ll11LspLanguageServerSmokeOptions options;
  try {
    options = Ll11LspLanguageServerSmokeOptions.parse(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(ll11LspLanguageServerSmokeUsage);
    exitCode = 64;
    return;
  }

  if (options.showHelp) {
    stdout.writeln(ll11LspLanguageServerSmokeUsage);
    return;
  }

  try {
    final result = await buildLl11LspLanguageServerSmokeReport(
      options: options,
      generatedAt: DateTime.now().toUtc(),
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(result.toJson());
    if (options.outJsonPath == null) {
      stdout.writeln(encoded);
    } else {
      final outJson = File(options.outJsonPath!);
      await outJson.parent.create(recursive: true);
      await outJson.writeAsString(encoded);
      stdout.writeln('LL11 LSP smoke JSON written to ${outJson.path}');
    }

    if (options.outMarkdownPath != null) {
      final outMarkdown = File(options.outMarkdownPath!);
      await outMarkdown.parent.create(recursive: true);
      await outMarkdown.writeAsString(result.toMarkdown());
      stdout.writeln('LL11 LSP smoke Markdown written to ${outMarkdown.path}');
    }

    stdout.writeln(result.toMarkdown());
    if (result.shouldFail) {
      stderr.writeln(
        'LL11 LSP language-server smoke blocked: '
        '${result.blockedGateIds.join(', ')}',
      );
      exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on Object catch (error, stackTrace) {
    stderr.writeln('LL11 LSP language-server smoke failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

Future<Ll11LspLanguageServerSmokeResult> buildLl11LspLanguageServerSmokeReport({
  required Ll11LspLanguageServerSmokeOptions options,
  DateTime? generatedAt,
  Ll11LspLanguageServerSmokeProbe? probe,
}) async {
  final reportTime = generatedAt ?? DateTime.now().toUtc();
  final fixtureRoot = await _createFixtureRoot(options);
  final deleteFixtureRoot = options.workRootPath == null;
  final smokeProbe = probe ?? const RealLl11LspLanguageServerSmokeProbe();
  final scenarios = <Ll11LspLanguageServerSmokeScenarioResult>[];

  try {
    for (final languageId in options.languages) {
      final scenario = _scenarioForLanguage(languageId);
      final scenarioRoot = Directory(
        '${fixtureRoot.path}/${scenario.languageId}',
      );
      if (scenarioRoot.existsSync()) {
        await scenarioRoot.delete(recursive: true);
      }
      await scenarioRoot.create(recursive: true);
      await scenario.writeTo(scenarioRoot);
      final changedFile = File.fromUri(
        scenarioRoot.uri.resolve(scenario.changedPath),
      );

      final stopwatch = Stopwatch()..start();
      final probeResult = await smokeProbe.run(
        scenario: scenario,
        projectRoot: scenarioRoot.path,
        changedPath: changedFile.path,
        diagnosticTimeout: Duration(milliseconds: options.diagnosticTimeoutMs),
        symbolTimeout: Duration(milliseconds: options.symbolTimeoutMs),
        definitionTimeout: Duration(milliseconds: options.definitionTimeoutMs),
      );
      stopwatch.stop();

      scenarios.add(
        Ll11LspLanguageServerSmokeScenarioResult.fromProbe(
          scenario: scenario,
          fixtureRoot: scenarioRoot.path,
          changedPath: changedFile.path,
          elapsedMs: stopwatch.elapsedMilliseconds,
          probeResult: probeResult,
        ),
      );
    }

    return Ll11LspLanguageServerSmokeResult(
      generatedAt: reportTime,
      command: options.command,
      fixtureRoot: fixtureRoot.path,
      requireLanguageServer: options.requireLanguageServer,
      scenarios: scenarios,
    );
  } finally {
    if (deleteFixtureRoot && fixtureRoot.existsSync()) {
      await fixtureRoot.delete(recursive: true);
    }
  }
}

abstract interface class Ll11LspLanguageServerSmokeProbe {
  Future<Ll11LspLanguageServerProbeResult> run({
    required Ll11LspLanguageServerSmokeScenario scenario,
    required String projectRoot,
    required String changedPath,
    required Duration diagnosticTimeout,
    required Duration symbolTimeout,
    required Duration definitionTimeout,
  });
}

class RealLl11LspLanguageServerSmokeProbe
    implements Ll11LspLanguageServerSmokeProbe {
  const RealLl11LspLanguageServerSmokeProbe();

  @override
  Future<Ll11LspLanguageServerProbeResult> run({
    required Ll11LspLanguageServerSmokeScenario scenario,
    required String projectRoot,
    required String changedPath,
    required Duration diagnosticTimeout,
    required Duration symbolTimeout,
    required Duration definitionTimeout,
  }) async {
    final resolver = const LspServerCommandResolver();
    final resolvedCommand = resolver.resolve(
      projectRoot: projectRoot,
      changedPaths: [changedPath],
    );
    if (resolvedCommand == null) {
      return Ll11LspLanguageServerProbeResult.unavailable(
        languageId: scenario.languageId,
        status: 'unavailable',
        code: 'language_server_not_resolved',
        error: 'No language server command could be resolved.',
      );
    }

    final registry = LspJsonRpcSessionRegistry(
      commandResolver: resolver,
      diagnosticSettleTimeout: diagnosticTimeout,
      symbolRequestTimeout: symbolTimeout,
      definitionRequestTimeout: definitionTimeout,
    );
    try {
      final readiness = await registry.ensureReady(
        projectRoot: projectRoot,
        changedPaths: [changedPath],
      );
      if (!readiness.ok) {
        return Ll11LspLanguageServerProbeResult.unavailable(
          languageId: readiness.languageId ?? resolvedCommand.languageId,
          status: readiness.status,
          code: readiness.code,
          error: readiness.error,
          command: resolvedCommand.command,
          workingDirectory: resolvedCommand.workingDirectory,
          metadata: readiness.metadata,
        );
      }

      final diagnostics =
          await registry.collectDiagnostics(
            projectRoot: projectRoot,
            changedPaths: [changedPath],
          ) ??
          const <LspDiagnostic>[];
      final symbols =
          await registry.collectDocumentSymbols(
            projectRoot: projectRoot,
            changedPaths: [changedPath],
          ) ??
          const <LspDocumentSymbol>[];
      final definitionTarget = scenario.definitionTargetFor(
        File(changedPath).readAsStringSync(),
      );
      final definitions = definitionTarget == null
          ? const <LspDefinitionLocation>[]
          : await registry.collectDefinitions(
                  projectRoot: projectRoot,
                  path: changedPath,
                  line: definitionTarget.line,
                  character: definitionTarget.character,
                ) ??
                const <LspDefinitionLocation>[];
      return Ll11LspLanguageServerProbeResult.ready(
        languageId: readiness.languageId ?? resolvedCommand.languageId,
        status: readiness.status,
        diagnostics: diagnostics,
        documentSymbols: symbols,
        definitions: definitions,
        command: resolvedCommand.command,
        workingDirectory: resolvedCommand.workingDirectory,
        metadata: readiness.metadata,
      );
    } on Object catch (error) {
      return Ll11LspLanguageServerProbeResult.unavailable(
        languageId: resolvedCommand.languageId,
        status: 'unavailable',
        code: 'language_server_probe_failed',
        error: error.toString(),
        command: resolvedCommand.command,
        workingDirectory: resolvedCommand.workingDirectory,
      );
    } finally {
      await registry.close();
    }
  }
}

class Ll11LspLanguageServerProbeResult {
  const Ll11LspLanguageServerProbeResult({
    required this.ready,
    required this.languageId,
    required this.status,
    this.code,
    this.error,
    this.command,
    this.workingDirectory,
    this.metadata,
    this.diagnostics = const [],
    this.documentSymbols = const [],
    this.definitions = const [],
  });

  factory Ll11LspLanguageServerProbeResult.ready({
    required String languageId,
    required String status,
    required List<LspDiagnostic> diagnostics,
    required List<LspDocumentSymbol> documentSymbols,
    required List<LspDefinitionLocation> definitions,
    String? command,
    String? workingDirectory,
    Map<String, dynamic>? metadata,
  }) {
    return Ll11LspLanguageServerProbeResult(
      ready: true,
      languageId: languageId,
      status: status,
      command: command,
      workingDirectory: workingDirectory,
      metadata: metadata,
      diagnostics: diagnostics,
      documentSymbols: documentSymbols,
      definitions: definitions,
    );
  }

  factory Ll11LspLanguageServerProbeResult.unavailable({
    required String languageId,
    required String status,
    String? code,
    String? error,
    String? command,
    String? workingDirectory,
    Map<String, dynamic>? metadata,
  }) {
    return Ll11LspLanguageServerProbeResult(
      ready: false,
      languageId: languageId,
      status: status,
      code: code,
      error: error,
      command: command,
      workingDirectory: workingDirectory,
      metadata: metadata,
    );
  }

  final bool ready;
  final String languageId;
  final String status;
  final String? code;
  final String? error;
  final String? command;
  final String? workingDirectory;
  final Map<String, dynamic>? metadata;
  final List<LspDiagnostic> diagnostics;
  final List<LspDocumentSymbol> documentSymbols;
  final List<LspDefinitionLocation> definitions;
}

class Ll11LspLanguageServerSmokeResult {
  const Ll11LspLanguageServerSmokeResult({
    required this.generatedAt,
    required this.command,
    required this.fixtureRoot,
    required this.requireLanguageServer,
    required this.scenarios,
  });

  final DateTime generatedAt;
  final String command;
  final String fixtureRoot;
  final bool requireLanguageServer;
  final List<Ll11LspLanguageServerSmokeScenarioResult> scenarios;

  int get passedCount =>
      scenarios.where((scenario) => scenario.status == 'passed').length;

  int get failedCount =>
      scenarios.where((scenario) => scenario.status == 'failed').length;

  int get skippedCount =>
      scenarios.where((scenario) => scenario.status == 'skipped').length;

  String get status {
    if (shouldFail) {
      return 'failed';
    }
    return passedCount > 0 ? 'passed' : 'skipped';
  }

  bool get shouldFail => blockedGateIds.isNotEmpty;

  List<String> get blockedGateIds {
    final gates = <String>[];
    if (failedCount > 0) {
      gates.add('language_server_probe_failed');
    }
    if (requireLanguageServer && passedCount == 0) {
      gates.add('no_language_server_passed');
    }
    return gates;
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaName': ll11LspLanguageServerSmokeSchemaName,
      'canaryName': ll11LspLanguageServerSmokeCanaryName,
      'surface': ll11LspLanguageServerSmokeSurface,
      'generatedAt': generatedAt.toIso8601String(),
      'status': status,
      'passed': passedCount,
      'failed': failedCount,
      'skipped': skippedCount,
      'total': scenarios.length,
      'requireLanguageServer': requireLanguageServer,
      'blockedGateIds': blockedGateIds,
      'command': command,
      'fixtureRoot': fixtureRoot,
      'scenarios': scenarios
          .map((scenario) => scenario.toJson(projectRoot: fixtureRoot))
          .toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL11 LSP Language Server Smoke')
      ..writeln()
      ..writeln('- Status: `$status`')
      ..writeln('- Generated: `${generatedAt.toIso8601String()}`')
      ..writeln('- Command: `$command`')
      ..writeln('- Fixture root: `$fixtureRoot`')
      ..writeln('- Require language server: `$requireLanguageServer`')
      ..writeln()
      ..writeln(
        '| Language | Status | Diagnostics | Symbols | Definitions | Command | Note |',
      )
      ..writeln('| --- | --- | ---: | ---: | ---: | --- | --- |');
    for (final scenario in scenarios) {
      buffer.writeln(
        '| ${scenario.languageId} | ${scenario.status} | '
        '${scenario.diagnosticCount} | ${scenario.symbolCount} | '
        '${scenario.definitionCount} | '
        '${_markdownCode(scenario.command ?? '')} | '
        '${_escapeMarkdownCell(scenario.note)} |',
      );
    }
    if (blockedGateIds.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Blocked gates: `${blockedGateIds.join(', ')}`');
    }
    return buffer.toString();
  }
}

class Ll11LspLanguageServerSmokeScenarioResult {
  const Ll11LspLanguageServerSmokeScenarioResult({
    required this.languageId,
    required this.status,
    required this.fixtureRoot,
    required this.changedPath,
    required this.elapsedMs,
    required this.diagnostics,
    required this.documentSymbols,
    required this.definitions,
    this.code,
    this.error,
    this.command,
    this.workingDirectory,
    this.metadata,
  });

  factory Ll11LspLanguageServerSmokeScenarioResult.fromProbe({
    required Ll11LspLanguageServerSmokeScenario scenario,
    required String fixtureRoot,
    required String changedPath,
    required int elapsedMs,
    required Ll11LspLanguageServerProbeResult probeResult,
  }) {
    final flattenedSymbols = probeResult.documentSymbols
        .expand((symbol) => symbol.flatten())
        .toList(growable: false);
    final status = _scenarioStatus(
      ready: probeResult.ready,
      diagnostics: probeResult.diagnostics,
      symbols: flattenedSymbols,
      definitions: probeResult.definitions,
    );
    return Ll11LspLanguageServerSmokeScenarioResult(
      languageId: scenario.languageId,
      status: status,
      fixtureRoot: fixtureRoot,
      changedPath: changedPath,
      elapsedMs: elapsedMs,
      diagnostics: probeResult.diagnostics,
      documentSymbols: flattenedSymbols,
      definitions: probeResult.definitions,
      code: probeResult.code,
      error: probeResult.error,
      command: probeResult.command,
      workingDirectory: probeResult.workingDirectory,
      metadata: probeResult.metadata,
    );
  }

  final String languageId;
  final String status;
  final String fixtureRoot;
  final String changedPath;
  final int elapsedMs;
  final List<LspDiagnostic> diagnostics;
  final List<LspDocumentSymbol> documentSymbols;
  final List<LspDefinitionLocation> definitions;
  final String? code;
  final String? error;
  final String? command;
  final String? workingDirectory;
  final Map<String, dynamic>? metadata;

  int get diagnosticCount => diagnostics.length;

  int get symbolCount => documentSymbols.length;

  int get definitionCount => definitions.length;

  String get note {
    if (status == 'passed') {
      return 'diagnostics, document symbols, and definitions observed';
    }
    if (status == 'skipped') {
      return error ?? code ?? 'language server unavailable';
    }
    if (diagnostics.isEmpty && documentSymbols.isEmpty && definitions.isEmpty) {
      return 'no diagnostics, document symbols, or definitions observed';
    }
    if (diagnostics.isEmpty) {
      return 'no diagnostics observed';
    }
    if (documentSymbols.isEmpty) {
      return 'no document symbols observed';
    }
    if (definitions.isEmpty) {
      return 'no definitions observed';
    }
    return 'language server evidence incomplete';
  }

  Map<String, dynamic> toJson({required String projectRoot}) {
    final root = Directory(fixtureRoot).absolute.path;
    return {
      'languageId': languageId,
      'status': status,
      'fixtureRoot': fixtureRoot,
      'changedPath': changedPath,
      'relativeChangedPath': DartProjectPath.relativePath(
        changedPath,
        root,
      ).replaceAll('\\', '/'),
      'elapsedMs': elapsedMs,
      'diagnosticCount': diagnosticCount,
      'symbolCount': symbolCount,
      'definitionCount': definitionCount,
      if (code != null) 'code': code,
      if (error != null) 'error': error,
      if (command != null) 'command': command,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      if (metadata != null) 'metadata': metadata,
      'diagnostics': diagnostics
          .map((diagnostic) => _diagnosticToJson(diagnostic, root))
          .toList(growable: false),
      'documentSymbols': documentSymbols
          .map((symbol) => _symbolToJson(symbol, root))
          .toList(growable: false),
      'definitions': definitions
          .map((definition) => _definitionToJson(definition, root))
          .toList(growable: false),
    };
  }

  static String _scenarioStatus({
    required bool ready,
    required List<LspDiagnostic> diagnostics,
    required List<LspDocumentSymbol> symbols,
    required List<LspDefinitionLocation> definitions,
  }) {
    if (!ready) {
      return 'skipped';
    }
    if (diagnostics.isNotEmpty &&
        symbols.isNotEmpty &&
        definitions.isNotEmpty) {
      return 'passed';
    }
    return 'failed';
  }
}

class Ll11LspLanguageServerSmokeOptions {
  const Ll11LspLanguageServerSmokeOptions({
    required this.languages,
    required this.requireLanguageServer,
    required this.diagnosticTimeoutMs,
    required this.symbolTimeoutMs,
    required this.definitionTimeoutMs,
    required this.command,
    this.workRootPath,
    this.outJsonPath,
    this.outMarkdownPath,
    this.showHelp = false,
  });

  factory Ll11LspLanguageServerSmokeOptions.parse(
    List<String> args, {
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final envLanguages =
        _parseLanguageList(env['CAVERNO_LL11_LSP_SMOKE_LANGUAGES']) ??
        _supportedLanguages;
    List<String>? cliLanguages;
    var requireLanguageServer = _isTruthy(
      env['CAVERNO_LL11_LSP_SMOKE_REQUIRE_LANGUAGE_SERVER'],
    );
    var diagnosticTimeoutMs =
        _positiveInt(
          env['CAVERNO_LL11_LSP_SMOKE_DIAGNOSTIC_TIMEOUT_MS'],
          'CAVERNO_LL11_LSP_SMOKE_DIAGNOSTIC_TIMEOUT_MS',
        ) ??
        2500;
    var symbolTimeoutMs =
        _positiveInt(
          env['CAVERNO_LL11_LSP_SMOKE_SYMBOL_TIMEOUT_MS'],
          'CAVERNO_LL11_LSP_SMOKE_SYMBOL_TIMEOUT_MS',
        ) ??
        1500;
    var definitionTimeoutMs =
        _positiveInt(
          env['CAVERNO_LL11_LSP_SMOKE_DEFINITION_TIMEOUT_MS'],
          'CAVERNO_LL11_LSP_SMOKE_DEFINITION_TIMEOUT_MS',
        ) ??
        1500;
    var command = 'dart run tool/ll11_lsp_language_server_smoke.dart';
    String? workRootPath = env['CAVERNO_LL11_LSP_SMOKE_WORK_ROOT']?.trim();
    if (workRootPath != null && workRootPath.isEmpty) {
      workRootPath = null;
    }
    String? outJsonPath;
    String? outMarkdownPath;
    var showHelp = false;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      String nextValue(String name) {
        if (index + 1 >= args.length) {
          throw FormatException('$name requires a value.');
        }
        index += 1;
        return args[index];
      }

      void addLanguages(String raw) {
        cliLanguages = [...?cliLanguages, ..._parseLanguageList(raw)!];
      }

      if (arg == '--help' || arg == '-h') {
        showHelp = true;
      } else if (arg == '--language') {
        addLanguages(nextValue(arg));
      } else if (arg.startsWith('--language=')) {
        addLanguages(arg.substring('--language='.length));
      } else if (arg == '--languages') {
        addLanguages(nextValue(arg));
      } else if (arg.startsWith('--languages=')) {
        addLanguages(arg.substring('--languages='.length));
      } else if (arg == '--require-language-server') {
        requireLanguageServer = true;
      } else if (arg == '--work-root') {
        workRootPath = nextValue(arg);
      } else if (arg.startsWith('--work-root=')) {
        workRootPath = arg.substring('--work-root='.length);
      } else if (arg == '--out-json') {
        outJsonPath = nextValue(arg);
      } else if (arg.startsWith('--out-json=')) {
        outJsonPath = arg.substring('--out-json='.length);
      } else if (arg == '--out-md') {
        outMarkdownPath = nextValue(arg);
      } else if (arg.startsWith('--out-md=')) {
        outMarkdownPath = arg.substring('--out-md='.length);
      } else if (arg == '--diagnostic-timeout-ms') {
        diagnosticTimeoutMs = _positiveInt(nextValue(arg), arg)!;
      } else if (arg.startsWith('--diagnostic-timeout-ms=')) {
        diagnosticTimeoutMs = _positiveInt(
          arg.substring('--diagnostic-timeout-ms='.length),
          '--diagnostic-timeout-ms',
        )!;
      } else if (arg == '--symbol-timeout-ms') {
        symbolTimeoutMs = _positiveInt(nextValue(arg), arg)!;
      } else if (arg.startsWith('--symbol-timeout-ms=')) {
        symbolTimeoutMs = _positiveInt(
          arg.substring('--symbol-timeout-ms='.length),
          '--symbol-timeout-ms',
        )!;
      } else if (arg == '--definition-timeout-ms') {
        definitionTimeoutMs = _positiveInt(nextValue(arg), arg)!;
      } else if (arg.startsWith('--definition-timeout-ms=')) {
        definitionTimeoutMs = _positiveInt(
          arg.substring('--definition-timeout-ms='.length),
          '--definition-timeout-ms',
        )!;
      } else if (arg == '--command') {
        command = nextValue(arg);
      } else if (arg.startsWith('--command=')) {
        command = arg.substring('--command='.length);
      } else {
        throw FormatException('Unknown option: $arg');
      }
    }

    final languages = List<String>.unmodifiable({
      ...(cliLanguages ?? envLanguages),
    });
    if (languages.isEmpty) {
      throw const FormatException('At least one language is required.');
    }

    return Ll11LspLanguageServerSmokeOptions(
      languages: languages,
      requireLanguageServer: requireLanguageServer,
      diagnosticTimeoutMs: diagnosticTimeoutMs,
      symbolTimeoutMs: symbolTimeoutMs,
      definitionTimeoutMs: definitionTimeoutMs,
      command: command,
      workRootPath: workRootPath,
      outJsonPath: outJsonPath,
      outMarkdownPath: outMarkdownPath,
      showHelp: showHelp,
    );
  }

  final List<String> languages;
  final bool requireLanguageServer;
  final int diagnosticTimeoutMs;
  final int symbolTimeoutMs;
  final int definitionTimeoutMs;
  final String command;
  final String? workRootPath;
  final String? outJsonPath;
  final String? outMarkdownPath;
  final bool showHelp;
}

class Ll11LspLanguageServerSmokeScenario {
  const Ll11LspLanguageServerSmokeScenario({
    required this.languageId,
    required this.changedPath,
    required this.files,
    required this.definitionReference,
    this.definitionReferenceOffset = 0,
  });

  final String languageId;
  final String changedPath;
  final Map<String, String> files;
  final String definitionReference;
  final int definitionReferenceOffset;

  Ll11LspTextPosition? definitionTargetFor(String content) {
    final index = content.indexOf(definitionReference);
    if (index < 0) {
      return null;
    }
    return _positionForOffset(content, index + definitionReferenceOffset);
  }

  Future<void> writeTo(Directory root) async {
    for (final entry in files.entries) {
      final file = File.fromUri(root.uri.resolve(entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
  }
}

Future<Directory> _createFixtureRoot(
  Ll11LspLanguageServerSmokeOptions options,
) async {
  final rootPath = options.workRootPath?.trim();
  if (rootPath != null && rootPath.isNotEmpty) {
    final root = Directory(rootPath);
    await root.create(recursive: true);
    return root;
  }
  return Directory.systemTemp.createTemp('ll11_lsp_language_server_smoke_');
}

Ll11LspLanguageServerSmokeScenario _scenarioForLanguage(String languageId) {
  return switch (languageId) {
    'dart' => const Ll11LspLanguageServerSmokeScenario(
      languageId: 'dart',
      changedPath: 'lib/main.dart',
      definitionReference: 'SmokeSymbol().read',
      files: {
        'pubspec.yaml': '''
name: ll11_lsp_smoke_dart
environment:
  sdk: '>=3.0.0 <4.0.0'
''',
        'lib/main.dart': '''
class SmokeSymbol {
  int read() => missingValue;
}

void main() {
  SmokeSymbol().read();
}
''',
      },
    ),
    'typescript' => const Ll11LspLanguageServerSmokeScenario(
      languageId: 'typescript',
      changedPath: 'src/app.ts',
      definitionReference: 'new SmokeSymbol',
      definitionReferenceOffset: 4,
      files: {
        'tsconfig.json': '''
{
  "compilerOptions": {
    "module": "commonjs",
    "strict": true,
    "target": "ES2020"
  }
}
''',
        'src/app.ts': '''
export class SmokeSymbol {
  read(): number {
    return missingValue;
  }
}

const smoke = new SmokeSymbol();
smoke.read();
''',
      },
    ),
    'python' => const Ll11LspLanguageServerSmokeScenario(
      languageId: 'python',
      changedPath: 'src/app.py',
      definitionReference: 'SmokeSymbol().read',
      files: {
        'src/app.py': '''
class SmokeSymbol:
    def read(self):
        return missing_value

SmokeSymbol().read()
''',
      },
    ),
    'swift' => const Ll11LspLanguageServerSmokeScenario(
      languageId: 'swift',
      changedPath: 'Sources/App/main.swift',
      definitionReference: 'SmokeSymbol().read',
      files: {
        'Package.swift': '''
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ll11LspSmokeSwift",
    targets: [
        .executableTarget(name: "App")
    ]
)
''',
        'Sources/App/main.swift': '''
struct SmokeSymbol {
    func read() -> Int {
        return missingValue
    }
}

func main() {
    SmokeSymbol().read()
}
''',
      },
    ),
    _ => throw FormatException('Unsupported language: $languageId'),
  };
}

Map<String, dynamic> _definitionToJson(
  LspDefinitionLocation definition,
  String projectRoot,
) {
  final path = _filePathFromUri(definition.uri);
  return {
    'uri': definition.uri,
    if (path != null)
      'relativePath': DartProjectPath.relativePath(
        path,
        projectRoot,
      ).replaceAll('\\', '/'),
    'line': definition.startLine + 1,
    'column': definition.startCharacter + 1,
    if (definition.endLine != null) 'endLine': definition.endLine! + 1,
    if (definition.endCharacter != null)
      'endColumn': definition.endCharacter! + 1,
  };
}

Ll11LspTextPosition _positionForOffset(String content, int offset) {
  var line = 0;
  var character = 0;
  for (var index = 0; index < offset && index < content.length; index += 1) {
    if (content.codeUnitAt(index) == 10) {
      line += 1;
      character = 0;
    } else {
      character += 1;
    }
  }
  return Ll11LspTextPosition(line: line, character: character);
}

class Ll11LspTextPosition {
  const Ll11LspTextPosition({required this.line, required this.character});

  final int line;
  final int character;
}

Map<String, dynamic> _diagnosticToJson(
  LspDiagnostic diagnostic,
  String projectRoot,
) {
  final path = _filePathFromUri(diagnostic.uri);
  return {
    'uri': diagnostic.uri,
    if (path != null)
      'relativePath': DartProjectPath.relativePath(
        path,
        projectRoot,
      ).replaceAll('\\', '/'),
    'line': diagnostic.startLine + 1,
    'column': diagnostic.startCharacter + 1,
    if (diagnostic.severity != null) 'severity': diagnostic.severity,
    if (diagnostic.code != null) 'code': diagnostic.code.toString(),
    if (diagnostic.source != null) 'source': diagnostic.source,
    'message': diagnostic.message,
  };
}

Map<String, dynamic> _symbolToJson(
  LspDocumentSymbol symbol,
  String projectRoot,
) {
  final path = _filePathFromUri(symbol.uri);
  return {
    'name': symbol.name,
    'kind': symbol.kind,
    'kindLabel': symbol.kindLabel,
    'line': symbol.startLine + 1,
    'column': symbol.startCharacter + 1,
    'uri': symbol.uri,
    if (path != null)
      'relativePath': DartProjectPath.relativePath(
        path,
        projectRoot,
      ).replaceAll('\\', '/'),
    if (symbol.detail != null) 'detail': symbol.detail,
    if (symbol.containerName != null) 'containerName': symbol.containerName,
  };
}

String? _filePathFromUri(String uri) {
  try {
    final parsed = Uri.parse(uri);
    if (parsed.scheme == 'file') {
      return File.fromUri(parsed).absolute.path;
    }
  } on FormatException {
    return null;
  }
  return null;
}

String _markdownCode(String value) {
  if (value.trim().isEmpty) {
    return '';
  }
  return '`${_escapeMarkdownCell(value)}`';
}

String _escapeMarkdownCell(String value) {
  return value.replaceAll('|', '\\|').replaceAll('\n', ' ');
}

List<String>? _parseLanguageList(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final languages = trimmed
      .split(',')
      .map((item) => _normalizeLanguage(item.trim()))
      .whereType<String>()
      .toList(growable: false);
  if (languages.isEmpty) {
    throw FormatException('Language list is empty: $raw');
  }
  return List<String>.unmodifiable({...languages});
}

String? _normalizeLanguage(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  return switch (normalized) {
    'dart' => 'dart',
    'ts' || 'typescript' || 'javascript' || 'js' => 'typescript',
    'py' || 'python' => 'python',
    'swift' => 'swift',
    _ => throw FormatException('Unsupported language: $raw'),
  };
}

bool _isTruthy(String? raw) {
  final normalized = raw?.trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

int? _positiveInt(String? raw, String name) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(trimmed);
  if (parsed == null || parsed <= 0) {
    throw FormatException('$name must be a positive integer.');
  }
  return parsed;
}

const _supportedLanguages = ['dart', 'typescript', 'python', 'swift'];
