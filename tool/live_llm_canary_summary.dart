import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _LiveLlmCanarySummaryOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/live_llm_canary_summary.dart '
      '--log PATH --out-dir PATH --canary-name NAME --surface NAME '
      '--base-url URL --model MODEL --command COMMAND',
    );
    exitCode = 64;
    return;
  }

  final logFile = File(options.logPath);
  if (!logFile.existsSync()) {
    stderr.writeln('Log file not found: ${logFile.path}');
    exitCode = 66;
    return;
  }

  final outputDirectory = Directory(options.outDir);
  outputDirectory.createSync(recursive: true);
  final summary = await buildLiveLlmCanarySummary(
    logFile: logFile,
    canaryName: options.canaryName,
    surface: options.surface,
    baseUrl: options.baseUrl,
    model: options.model,
    command: options.command,
  );

  final jsonFile = File('${outputDirectory.path}/canary_summary.json');
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  final markdownFile = File('${outputDirectory.path}/canary_summary.md');
  await markdownFile.writeAsString(summary.toMarkdown());

  stdout.writeln('Live LLM canary summary written to ${jsonFile.path}');
  stdout.writeln(summary.toMarkdown());

  if (!summary.isSuccessful) {
    exitCode = 1;
  }
}

Future<LiveLlmCanarySummary> buildLiveLlmCanarySummary({
  required File logFile,
  required String canaryName,
  required String surface,
  required String baseUrl,
  required String model,
  required String command,
  DateTime? generatedAt,
}) async {
  final rawLog = await logFile.readAsString();
  final parser = _FlutterJsonTestLogParser(rawLog);
  final parsed = parser.parse();
  final tests = parsed.tests.where((test) => !test.hidden).toList();
  final failedCount = tests.where((test) => test.result == 'failed').length;
  final skippedCount = tests.where((test) => test.skipped).length;
  final passedCount = tests
      .where((test) => test.result == 'passed' && !test.skipped)
      .length;
  final result = _summaryResult(
    doneSeen: parsed.doneSeen,
    runnerSuccess: parsed.runnerSuccess,
    failedCount: failedCount,
    skippedCount: skippedCount,
  );
  return LiveLlmCanarySummary(
    schemaName: 'live_llm_canary_summary',
    schemaVersion: 1,
    generatedAt: generatedAt ?? DateTime.now(),
    canaryName: canaryName,
    surface: surface,
    baseUrl: baseUrl,
    model: model,
    command: command,
    logPath: logFile.path,
    result: result,
    runnerSuccess: parsed.runnerSuccess,
    doneSeen: parsed.doneSeen,
    durationMs: parsed.durationMs,
    testCount: tests.length,
    passedCount: passedCount,
    failedCount: failedCount,
    skippedCount: skippedCount,
    hiddenTestCount: parsed.hiddenTestCount,
    malformedJsonLineCount: parsed.malformedJsonLineCount,
    signals: LiveLlmCanarySignals.fromLog(rawLog),
    tests: tests,
  );
}

String _summaryResult({
  required bool doneSeen,
  required bool? runnerSuccess,
  required int failedCount,
  required int skippedCount,
}) {
  if (!doneSeen || runnerSuccess != true || failedCount > 0) {
    return 'failed';
  }
  if (skippedCount > 0) {
    return 'skipped';
  }
  return 'passed';
}

class LiveLlmCanarySummary {
  const LiveLlmCanarySummary({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.canaryName,
    required this.surface,
    required this.baseUrl,
    required this.model,
    required this.command,
    required this.logPath,
    required this.result,
    required this.runnerSuccess,
    required this.doneSeen,
    required this.durationMs,
    required this.testCount,
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.hiddenTestCount,
    required this.malformedJsonLineCount,
    required this.signals,
    required this.tests,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String canaryName;
  final String surface;
  final String baseUrl;
  final String model;
  final String command;
  final String logPath;
  final String result;
  final bool? runnerSuccess;
  final bool doneSeen;
  final int? durationMs;
  final int testCount;
  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final int hiddenTestCount;
  final int malformedJsonLineCount;
  final LiveLlmCanarySignals signals;
  final List<LiveLlmCanaryTestResult> tests;

  bool get isSuccessful => result == 'passed';

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'canaryName': canaryName,
      'surface': surface,
      'baseUrl': baseUrl,
      'model': model,
      'command': command,
      'logPath': logPath,
      'result': result,
      'runnerSuccess': runnerSuccess,
      'doneSeen': doneSeen,
      'durationMs': durationMs,
      'testCount': testCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'skippedCount': skippedCount,
      'hiddenTestCount': hiddenTestCount,
      'malformedJsonLineCount': malformedJsonLineCount,
      'signals': signals.toJson(),
      'tests': tests.map((test) => test.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Live LLM Canary Summary')
      ..writeln()
      ..writeln('- Canary: `$canaryName`')
      ..writeln('- Surface: `$surface`')
      ..writeln('- Result: `$result`')
      ..writeln('- Model: `$model`')
      ..writeln('- Base URL: `$baseUrl`')
      ..writeln('- Command: `$command`')
      ..writeln('- Flutter JSON log: `$logPath`')
      ..writeln(
        '- Tests: `$passedCount/$testCount` passed, '
        '`$failedCount` failed, `$skippedCount` skipped',
      )
      ..writeln('- Duration: `${durationMs ?? 0} ms`')
      ..writeln()
      ..writeln('## Recovery Signals')
      ..writeln()
      ..writeln(
        '- Recovered stream fallback count: '
        '`${signals.recoveredStreamFallbackCount}`',
      )
      ..writeln(
        '- Tool-result compaction retry count: '
        '`${signals.toolResultCompactionRetryCount}`',
      )
      ..writeln(
        '- Incomplete content-tool recovery count: '
        '`${signals.incompleteContentToolRecoveryCount}`',
      )
      ..writeln(
        '- Ignored assistant-authored tool_result count: '
        '`${signals.ignoredAssistantToolResultCount}`',
      )
      ..writeln(
        '- Assistant-authored tool block count: '
        '`${signals.assistantAuthoredToolBlockCount}`',
      )
      ..writeln(
        '- Transport disconnect count: `${signals.transportDisconnectCount}`',
      )
      ..writeln(
        '- Memory extraction fallback count: '
        '`${signals.memoryExtractionFallbackCount}`',
      )
      ..writeln()
      ..writeln('## Tests')
      ..writeln()
      ..writeln('| Test | Result | Duration |')
      ..writeln('|------|--------|----------|');
    for (final test in tests) {
      buffer.writeln(
        '| ${_tableCell(test.name)} | `${test.result}` | '
        '`${test.durationMs ?? 0} ms` |',
      );
    }
    return buffer.toString();
  }
}

class LiveLlmCanarySignals {
  const LiveLlmCanarySignals({
    required this.recoveredStreamFallbackCount,
    required this.toolResultCompactionRetryCount,
    required this.incompleteContentToolRecoveryCount,
    required this.ignoredAssistantToolResultCount,
    required this.assistantAuthoredToolBlockCount,
    required this.transportDisconnectCount,
    required this.memoryExtractionFallbackCount,
  });

  final int recoveredStreamFallbackCount;
  final int toolResultCompactionRetryCount;
  final int incompleteContentToolRecoveryCount;
  final int ignoredAssistantToolResultCount;
  final int assistantAuthoredToolBlockCount;
  final int transportDisconnectCount;
  final int memoryExtractionFallbackCount;

  static LiveLlmCanarySignals fromLog(String rawLog) {
    return LiveLlmCanarySignals(
      recoveredStreamFallbackCount: _countMatches(
        rawLog,
        RegExp('Recovered content-tool continuation with non-streaming'),
      ),
      toolResultCompactionRetryCount: _countMatches(
        rawLog,
        RegExp('Retrying tool-result follow-up after context-length error'),
      ),
      incompleteContentToolRecoveryCount: _countMatches(
        rawLog,
        RegExp(r'Recovering incomplete tool_call\(s\)'),
      ),
      ignoredAssistantToolResultCount: _countMatches(
        rawLog,
        RegExp('Ignoring assistant-authored tool_result tag'),
      ),
      assistantAuthoredToolBlockCount: _countMatches(
        rawLog,
        RegExp(r'\[Tool: [A-Za-z0-9_]+\]'),
      ),
      transportDisconnectCount: _countMatches(
        rawLog,
        RegExp(
          'Connection closed before full header was received|'
          'streamDisconnect|stream disconnect',
          caseSensitive: false,
        ),
      ),
      memoryExtractionFallbackCount: _countMatches(
        rawLog,
        RegExp(
          'rule-based extraction|rule based extraction',
          caseSensitive: false,
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'recoveredStreamFallbackCount': recoveredStreamFallbackCount,
      'toolResultCompactionRetryCount': toolResultCompactionRetryCount,
      'incompleteContentToolRecoveryCount': incompleteContentToolRecoveryCount,
      'ignoredAssistantToolResultCount': ignoredAssistantToolResultCount,
      'assistantAuthoredToolBlockCount': assistantAuthoredToolBlockCount,
      'transportDisconnectCount': transportDisconnectCount,
      'memoryExtractionFallbackCount': memoryExtractionFallbackCount,
    };
  }
}

class LiveLlmCanaryTestResult {
  const LiveLlmCanaryTestResult({
    required this.id,
    required this.name,
    required this.result,
    required this.skipped,
    required this.hidden,
    required this.durationMs,
    required this.skipReason,
    required this.messageCount,
  });

  final int id;
  final String name;
  final String result;
  final bool skipped;
  final bool hidden;
  final int? durationMs;
  final String? skipReason;
  final int messageCount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'result': result,
      'skipped': skipped,
      'hidden': hidden,
      'durationMs': durationMs,
      'skipReason': skipReason,
      'messageCount': messageCount,
    };
  }
}

class _FlutterJsonTestLogParser {
  _FlutterJsonTestLogParser(this.rawLog);

  final String rawLog;

  _ParsedFlutterJsonTestLog parse() {
    final starts = <int, _TestStart>{};
    final messages = <int, List<String>>{};
    final tests = <LiveLlmCanaryTestResult>[];
    var malformedJsonLineCount = 0;
    var hiddenTestCount = 0;
    var doneSeen = false;
    bool? runnerSuccess;
    int? durationMs;

    for (final line in const LineSplitter().convert(rawLog)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('{')) {
        continue;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        malformedJsonLineCount += 1;
        continue;
      }
      if (decoded is! Map<String, dynamic>) {
        continue;
      }

      switch (decoded['type']) {
        case 'testStart':
          final test = decoded['test'];
          if (test is Map<String, dynamic>) {
            final id = (test['id'] as num?)?.toInt();
            if (id == null) {
              continue;
            }
            final metadata = test['metadata'];
            final skipReason = metadata is Map<String, dynamic>
                ? metadata['skipReason'] as String?
                : null;
            starts[id] = _TestStart(
              id: id,
              name: test['name'] as String? ?? 'unnamed test $id',
              startedAtMs: (decoded['time'] as num?)?.toInt(),
              skipReason: skipReason,
            );
          }
        case 'print':
          final testId = (decoded['testID'] as num?)?.toInt();
          final message = decoded['message'] as String?;
          if (testId != null && message != null) {
            messages.putIfAbsent(testId, () => []).add(message);
          }
        case 'testDone':
          final testId = (decoded['testID'] as num?)?.toInt();
          if (testId == null) {
            continue;
          }
          final start = starts[testId];
          final endMs = (decoded['time'] as num?)?.toInt();
          final hidden = decoded['hidden'] == true;
          if (hidden) {
            hiddenTestCount += 1;
          }
          final skipped = decoded['skipped'] == true;
          final rawResult = decoded['result'] as String? ?? 'unknown';
          final result = skipped
              ? 'skipped'
              : rawResult == 'success'
              ? 'passed'
              : 'failed';
          tests.add(
            LiveLlmCanaryTestResult(
              id: testId,
              name: start?.name ?? 'unknown test $testId',
              result: result,
              skipped: skipped,
              hidden: hidden,
              durationMs: start?.startedAtMs == null || endMs == null
                  ? null
                  : endMs - start!.startedAtMs!,
              skipReason: start?.skipReason,
              messageCount: messages[testId]?.length ?? 0,
            ),
          );
        case 'done':
          doneSeen = true;
          final runSuccess = decoded['success'] as bool?;
          if (runSuccess != null) {
            runnerSuccess = (runnerSuccess ?? true) && runSuccess;
          }
          final runDurationMs = (decoded['time'] as num?)?.toInt();
          if (runDurationMs != null) {
            durationMs = (durationMs ?? 0) + runDurationMs;
          }
      }
    }

    return _ParsedFlutterJsonTestLog(
      tests: tests,
      doneSeen: doneSeen,
      runnerSuccess: runnerSuccess,
      durationMs: durationMs,
      hiddenTestCount: hiddenTestCount,
      malformedJsonLineCount: malformedJsonLineCount,
    );
  }
}

class _ParsedFlutterJsonTestLog {
  const _ParsedFlutterJsonTestLog({
    required this.tests,
    required this.doneSeen,
    required this.runnerSuccess,
    required this.durationMs,
    required this.hiddenTestCount,
    required this.malformedJsonLineCount,
  });

  final List<LiveLlmCanaryTestResult> tests;
  final bool doneSeen;
  final bool? runnerSuccess;
  final int? durationMs;
  final int hiddenTestCount;
  final int malformedJsonLineCount;
}

class _TestStart {
  const _TestStart({
    required this.id,
    required this.name,
    required this.startedAtMs,
    required this.skipReason,
  });

  final int id;
  final String name;
  final int? startedAtMs;
  final String? skipReason;
}

class _LiveLlmCanarySummaryOptions {
  const _LiveLlmCanarySummaryOptions({
    required this.logPath,
    required this.outDir,
    required this.canaryName,
    required this.surface,
    required this.baseUrl,
    required this.model,
    required this.command,
  });

  final String logPath;
  final String outDir;
  final String canaryName;
  final String surface;
  final String baseUrl;
  final String model;
  final String command;

  static _LiveLlmCanarySummaryOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--')) {
        return null;
      }
      if (index + 1 >= args.length) {
        return null;
      }
      values[arg.substring(2)] = args[index + 1];
      index += 1;
    }
    final logPath = values['log'];
    final outDir = values['out-dir'];
    final canaryName = values['canary-name'];
    final surface = values['surface'];
    final baseUrl = values['base-url'];
    final model = values['model'];
    final command = values['command'];
    if (logPath == null ||
        outDir == null ||
        canaryName == null ||
        surface == null ||
        baseUrl == null ||
        model == null ||
        command == null) {
      return null;
    }
    return _LiveLlmCanarySummaryOptions(
      logPath: logPath,
      outDir: outDir,
      canaryName: canaryName,
      surface: surface,
      baseUrl: baseUrl,
      model: model,
      command: command,
    );
  }
}

int _countMatches(String input, RegExp pattern) {
  return pattern.allMatches(input).length;
}

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}
