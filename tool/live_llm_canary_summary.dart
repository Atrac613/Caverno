import 'dart:convert';
import 'dart:io';

const _dartAnalyzeFeedbackSummaryPrefix =
    '[CodingDiagnostics] Analyzer feedback summary: ';
const _dartAnalyzeFeedbackToolName = 'dart_analyze_feedback';
const _dartTestFeedbackSummaryPrefix =
    '[CodingVerification] Test feedback summary: ';
const _dartTestFeedbackToolName = 'dart_test_feedback';
const _codingOutputFeedbackSummaryPrefix =
    '[CodingOutputGuardrail] Feedback summary: ';
const _codingOutputFeedbackToolName = 'coding_output_feedback';

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
  final signals = LiveLlmCanarySignals.fromLog(rawLog);
  return LiveLlmCanarySummary(
    schemaName: 'live_llm_canary_summary',
    schemaVersion: 2,
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
    signals: signals,
    readiness: LiveLlmCanaryReadiness.fromTests(
      result: result,
      doneSeen: parsed.doneSeen,
      signals: signals,
      tests: tests,
    ),
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
    required this.readiness,
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
  final LiveLlmCanaryReadiness readiness;
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
      'mainReadiness': readiness.toJson(),
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
      ..writeln('- Main readiness: `${readiness.status}`')
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
      ..writeln('## Main Readiness')
      ..writeln()
      ..writeln('- Status: `${readiness.status}`')
      ..writeln('- Blocker failures: `${readiness.blockerFailedCount}`')
      ..writeln('- Warning failures: `${readiness.warningFailedCount}`')
      ..writeln('- Skipped tests: `${readiness.skippedCount}`')
      ..writeln('- Note: ${readiness.note}')
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
      ..writeln('- Process-start call count: `${signals.processStartCount}`')
      ..writeln('- Process-wait call count: `${signals.processWaitCount}`')
      ..writeln(
        '- Background process still-running count: '
        '`${signals.backgroundProcessStillRunningCount}`',
      )
      ..writeln(
        '- Background process completed count: '
        '`${signals.backgroundProcessCompletedCount}`',
      )
      ..writeln(
        '- Background process failed count: '
        '`${signals.backgroundProcessFailedCount}`',
      )
      ..writeln(
        '- Background process status-unverified count: '
        '`${signals.backgroundProcessStatusUnverifiedCount}`',
      )
      ..writeln()
      ..writeln('## Coding Diagnostic Feedback')
      ..writeln()
      ..writeln(
        '- Dart analyzer feedback observed: '
        '`${signals.dartAnalyzeFeedback.observed ? 'yes' : 'no'}`',
      )
      ..writeln(
        '- Dart analyzer feedback count: '
        '`${signals.dartAnalyzeFeedback.feedbackCount}`',
      )
      ..writeln(
        '- Dart analyzer diagnostic count: '
        '`${signals.dartAnalyzeFeedback.diagnosticCount}`',
      )
      ..writeln(
        '- Dart analyzer feedback files: '
        '`${signals.dartAnalyzeFeedback.files.isEmpty ? '(none)' : signals.dartAnalyzeFeedback.files.join(', ')}`',
      )
      ..writeln(
        '- Dart analyzer feedback duration: '
        '`${signals.dartAnalyzeFeedback.durationMs} ms`',
      )
      ..writeln(
        '- Dart analyzer command attempts: '
        '`${signals.dartAnalyzeFeedback.commandAttemptCount}`',
      )
      ..writeln(
        '- Dart analyzer fallback commands: '
        '`${signals.dartAnalyzeFeedback.fallbackCommandCount}`',
      )
      ..writeln(
        '- Dart analyzer timed-out commands: '
        '`${signals.dartAnalyzeFeedback.timedOutCommandCount}`',
      )
      ..writeln(
        '- Dart analyzer start-error commands: '
        '`${signals.dartAnalyzeFeedback.startErrorCommandCount}`',
      )
      ..writeln()
      ..writeln('## Coding Verification Feedback')
      ..writeln()
      ..writeln(
        '- Dart test feedback observed: '
        '`${signals.dartTestFeedback.observed ? 'yes' : 'no'}`',
      )
      ..writeln(
        '- Dart test feedback count: '
        '`${signals.dartTestFeedback.feedbackCount}`',
      )
      ..writeln(
        '- Dart test failure count: '
        '`${signals.dartTestFeedback.failedCount}`',
      )
      ..writeln(
        '- Dart test feedback files: '
        '`${signals.dartTestFeedback.files.isEmpty ? '(none)' : signals.dartTestFeedback.files.join(', ')}`',
      )
      ..writeln(
        '- Dart test feedback triggers: '
        '`${signals.dartTestFeedback.triggers.isEmpty ? '(none)' : signals.dartTestFeedback.triggers.join(', ')}`',
      )
      ..writeln(
        '- Dart test validation statuses: '
        '`${signals.dartTestFeedback.validationStatuses.isEmpty ? '(none)' : signals.dartTestFeedback.validationStatuses.join(', ')}`',
      )
      ..writeln(
        '- Dart test feedback duration: '
        '`${signals.dartTestFeedback.durationMs} ms`',
      )
      ..writeln(
        '- Dart test command attempts: '
        '`${signals.dartTestFeedback.commandAttemptCount}`',
      )
      ..writeln(
        '- Dart test fallback commands: '
        '`${signals.dartTestFeedback.fallbackCommandCount}`',
      )
      ..writeln(
        '- Dart test timed-out commands: '
        '`${signals.dartTestFeedback.timedOutCommandCount}`',
      )
      ..writeln(
        '- Dart test start-error commands: '
        '`${signals.dartTestFeedback.startErrorCommandCount}`',
      )
      ..writeln()
      ..writeln('## Coding Output Feedback')
      ..writeln()
      ..writeln(
        '- Command output feedback observed: '
        '`${signals.codingOutputFeedback.observed ? 'yes' : 'no'}`',
      )
      ..writeln(
        '- Command output feedback count: '
        '`${signals.codingOutputFeedback.feedbackCount}`',
      )
      ..writeln(
        '- Command output issue count: '
        '`${signals.codingOutputFeedback.issueCount}`',
      )
      ..writeln(
        '- Command output feedback commands: '
        '`${signals.codingOutputFeedback.commands.isEmpty ? '(none)' : signals.codingOutputFeedback.commands.join(', ')}`',
      )
      ..writeln(
        '- Command output validation statuses: '
        '`${signals.codingOutputFeedback.validationStatuses.isEmpty ? '(none)' : signals.codingOutputFeedback.validationStatuses.join(', ')}`',
      )
      ..writeln()
      ..writeln('## Tests')
      ..writeln()
      ..writeln('| Test | Result | Category | Impact | Duration |')
      ..writeln('|------|--------|----------|--------|----------|');
    for (final test in tests) {
      buffer.writeln(
        '| ${_tableCell(test.name)} | `${test.result}` | '
        '`${test.category}` | `${test.readinessImpact}` | '
        '`${test.durationMs ?? 0} ms` |',
      );
    }
    final failedTests = tests
        .where((test) => test.failureMessage != null)
        .toList(growable: false);
    if (failedTests.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Failed Test Details')
        ..writeln();
      for (final test in failedTests) {
        buffer
          ..writeln('### ${test.name}')
          ..writeln()
          ..writeln('- Category: `${test.category}`')
          ..writeln('- Impact: `${test.readinessImpact}`')
          ..writeln('- Failure: ${_inlineCode(test.failurePreview)}')
          ..writeln();
      }
    }
    return buffer.toString();
  }
}

class LiveLlmCanaryReadiness {
  const LiveLlmCanaryReadiness({
    required this.status,
    required this.blockerFailedCount,
    required this.warningFailedCount,
    required this.skippedCount,
    required this.note,
  });

  final String status;
  final int blockerFailedCount;
  final int warningFailedCount;
  final int skippedCount;
  final String note;

  static LiveLlmCanaryReadiness fromTests({
    required String result,
    required bool doneSeen,
    required LiveLlmCanarySignals signals,
    required List<LiveLlmCanaryTestResult> tests,
  }) {
    final visibleTests = tests.where((test) => !test.hidden).toList();
    final failedTests = visibleTests
        .where((test) => test.result == 'failed')
        .toList(growable: false);
    final warningFailedCount = failedTests
        .where((test) => test.readinessImpact == 'warning')
        .length;
    final blockerFailedCount = failedTests.length - warningFailedCount;
    final skippedCount = visibleTests.where((test) => test.skipped).length;

    if (!doneSeen || result == 'skipped') {
      return LiveLlmCanaryReadiness(
        status: 'not_run',
        blockerFailedCount: blockerFailedCount,
        warningFailedCount: warningFailedCount,
        skippedCount: skippedCount,
        note: 'The canary did not complete with actionable readiness evidence.',
      );
    }
    if (failedTests.isEmpty && result == 'passed') {
      return LiveLlmCanaryReadiness(
        status: 'ready',
        blockerFailedCount: 0,
        warningFailedCount: 0,
        skippedCount: skippedCount,
        note: 'All visible live canary checks passed.',
      );
    }
    if (failedTests.isNotEmpty && blockerFailedCount == 0) {
      return LiveLlmCanaryReadiness(
        status: 'usable_with_warnings',
        blockerFailedCount: 0,
        warningFailedCount: warningFailedCount,
        skippedCount: skippedCount,
        note:
            'Core checks passed, but recovery or skill follow-up checks need attention.',
      );
    }
    if (failedTests.isNotEmpty && signals.transportDisconnectCount > 0) {
      return LiveLlmCanaryReadiness(
        status: 'inconclusive',
        blockerFailedCount: blockerFailedCount,
        warningFailedCount: warningFailedCount,
        skippedCount: skippedCount,
        note:
            'Transport disconnects occurred; rerun before making a model readiness decision.',
      );
    }
    return LiveLlmCanaryReadiness(
      status: 'blocked',
      blockerFailedCount: blockerFailedCount,
      warningFailedCount: warningFailedCount,
      skippedCount: skippedCount,
      note: 'At least one core live canary check failed.',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'blockerFailedCount': blockerFailedCount,
      'warningFailedCount': warningFailedCount,
      'skippedCount': skippedCount,
      'note': note,
    };
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
    required this.processStartCount,
    required this.processWaitCount,
    required this.backgroundProcessStillRunningCount,
    required this.backgroundProcessCompletedCount,
    required this.backgroundProcessFailedCount,
    required this.backgroundProcessStatusUnverifiedCount,
    required this.dartAnalyzeFeedback,
    required this.dartTestFeedback,
    required this.codingOutputFeedback,
  });

  final int recoveredStreamFallbackCount;
  final int toolResultCompactionRetryCount;
  final int incompleteContentToolRecoveryCount;
  final int ignoredAssistantToolResultCount;
  final int assistantAuthoredToolBlockCount;
  final int transportDisconnectCount;
  final int memoryExtractionFallbackCount;
  final int processStartCount;
  final int processWaitCount;
  final int backgroundProcessStillRunningCount;
  final int backgroundProcessCompletedCount;
  final int backgroundProcessFailedCount;
  final int backgroundProcessStatusUnverifiedCount;
  final LiveLlmCanaryDartAnalyzeFeedbackSignals dartAnalyzeFeedback;
  final LiveLlmCanaryDartTestFeedbackSignals dartTestFeedback;
  final LiveLlmCanaryCodingOutputFeedbackSignals codingOutputFeedback;

  static LiveLlmCanarySignals fromLog(String rawLog) {
    final dartAnalyzeFeedback = _extractDartAnalyzeFeedbackSignals(rawLog);
    final dartTestFeedback = _extractDartTestFeedbackSignals(rawLog);
    final codingOutputFeedback = _extractCodingOutputFeedbackSignals(rawLog);
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
      processStartCount: _countToolExecutionMessages(rawLog, 'process_start'),
      processWaitCount: _countToolExecutionMessages(rawLog, 'process_wait'),
      backgroundProcessStillRunningCount: _countMatches(
        rawLog,
        RegExp('background_process_still_running'),
      ),
      backgroundProcessCompletedCount: _countMatches(
        rawLog,
        RegExp('background_process_completed'),
      ),
      backgroundProcessFailedCount: _countMatches(
        rawLog,
        RegExp('background_process_failed'),
      ),
      backgroundProcessStatusUnverifiedCount: _countMatches(
        rawLog,
        RegExp('background_process_status_unverified'),
      ),
      dartAnalyzeFeedback: dartAnalyzeFeedback,
      dartTestFeedback: dartTestFeedback,
      codingOutputFeedback: codingOutputFeedback,
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
      'processStartCount': processStartCount,
      'processWaitCount': processWaitCount,
      'backgroundProcessStillRunningCount': backgroundProcessStillRunningCount,
      'backgroundProcessCompletedCount': backgroundProcessCompletedCount,
      'backgroundProcessFailedCount': backgroundProcessFailedCount,
      'backgroundProcessStatusUnverifiedCount':
          backgroundProcessStatusUnverifiedCount,
      'dartAnalyzeFeedback': dartAnalyzeFeedback.toJson(),
      'dartTestFeedback': dartTestFeedback.toJson(),
      'codingOutputFeedback': codingOutputFeedback.toJson(),
    };
  }
}

class LiveLlmCanaryDartAnalyzeFeedbackSignals {
  const LiveLlmCanaryDartAnalyzeFeedbackSignals({
    required this.feedbackCount,
    required this.diagnosticCount,
    required this.files,
    required this.durationMs,
    required this.commandAttemptCount,
    required this.fallbackCommandCount,
    required this.timedOutCommandCount,
    required this.startErrorCommandCount,
  });

  final int feedbackCount;
  final int diagnosticCount;
  final List<String> files;
  final int durationMs;
  final int commandAttemptCount;
  final int fallbackCommandCount;
  final int timedOutCommandCount;
  final int startErrorCommandCount;

  bool get observed => feedbackCount > 0;

  Map<String, dynamic> toJson() {
    return {
      'observed': observed,
      'feedbackCount': feedbackCount,
      'diagnosticCount': diagnosticCount,
      'files': files,
      'durationMs': durationMs,
      'commandAttemptCount': commandAttemptCount,
      'fallbackCommandCount': fallbackCommandCount,
      'timedOutCommandCount': timedOutCommandCount,
      'startErrorCommandCount': startErrorCommandCount,
    };
  }
}

class LiveLlmCanaryDartTestFeedbackSignals {
  const LiveLlmCanaryDartTestFeedbackSignals({
    required this.feedbackCount,
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.files,
    required this.triggers,
    required this.validationStatuses,
    required this.durationMs,
    required this.commandAttemptCount,
    required this.fallbackCommandCount,
    required this.timedOutCommandCount,
    required this.startErrorCommandCount,
  });

  final int feedbackCount;
  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final List<String> files;
  final List<String> triggers;
  final List<String> validationStatuses;
  final int durationMs;
  final int commandAttemptCount;
  final int fallbackCommandCount;
  final int timedOutCommandCount;
  final int startErrorCommandCount;

  bool get observed => feedbackCount > 0;

  Map<String, dynamic> toJson() {
    return {
      'observed': observed,
      'feedbackCount': feedbackCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'skippedCount': skippedCount,
      'files': files,
      'triggers': triggers,
      'validationStatuses': validationStatuses,
      'durationMs': durationMs,
      'commandAttemptCount': commandAttemptCount,
      'fallbackCommandCount': fallbackCommandCount,
      'timedOutCommandCount': timedOutCommandCount,
      'startErrorCommandCount': startErrorCommandCount,
    };
  }
}

class LiveLlmCanaryCodingOutputFeedbackSignals {
  const LiveLlmCanaryCodingOutputFeedbackSignals({
    required this.feedbackCount,
    required this.issueCount,
    required this.commands,
    required this.validationStatuses,
  });

  final int feedbackCount;
  final int issueCount;
  final List<String> commands;
  final List<String> validationStatuses;

  bool get observed => feedbackCount > 0;

  Map<String, dynamic> toJson() {
    return {
      'observed': observed,
      'feedbackCount': feedbackCount,
      'issueCount': issueCount,
      'commands': commands,
      'validationStatuses': validationStatuses,
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
    required this.failureMessage,
  });

  final int id;
  final String name;
  final String result;
  final bool skipped;
  final bool hidden;
  final int? durationMs;
  final String? skipReason;
  final int messageCount;
  final String? failureMessage;

  String get category => _categoryForTestName(name);
  String get readinessImpact => _readinessImpactForCategory(category, result);
  String get failurePreview => _truncateForSummary(failureMessage ?? '', 700);

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
      'category': category,
      'readinessImpact': readinessImpact,
      if (failureMessage != null) 'failureMessage': failureMessage,
    };
  }
}

class _FlutterJsonTestLogParser {
  _FlutterJsonTestLogParser(this.rawLog);

  final String rawLog;

  _ParsedFlutterJsonTestLog parse() {
    final starts = <int, _TestStart>{};
    final messages = <int, List<String>>{};
    final errors = <int, List<String>>{};
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
        case 'error':
          final testId = (decoded['testID'] as num?)?.toInt();
          final message = decoded['error'] as String?;
          if (testId != null && message != null) {
            errors.putIfAbsent(testId, () => []).add(message);
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
              failureMessage: _joinedFailureMessages(errors[testId]),
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

int _countToolExecutionMessages(String rawLog, String toolName) {
  var count = 0;
  for (final line in const LineSplitter().convert(rawLog)) {
    for (final message in _messagesFromLogLine(line)) {
      if (message == '[ToolCall] $toolName' ||
          message.contains('[Tool] Executing tool: $toolName')) {
        count += 1;
      }
    }
  }
  return count;
}

LiveLlmCanaryDartAnalyzeFeedbackSignals _extractDartAnalyzeFeedbackSignals(
  String rawLog,
) {
  final files = <String>{};
  var feedbackCount = 0;
  var diagnosticCount = 0;
  var durationMs = 0;
  var commandAttemptCount = 0;
  var fallbackCommandCount = 0;
  var timedOutCommandCount = 0;
  var startErrorCommandCount = 0;
  var fallbackFeedbackCount = 0;

  for (final line in const LineSplitter().convert(rawLog)) {
    for (final message in _messagesFromLogLine(line)) {
      if (message.contains('[CodingDiagnostics] Added analyzer feedback')) {
        fallbackFeedbackCount += 1;
      }

      final prefixIndex = message.indexOf(_dartAnalyzeFeedbackSummaryPrefix);
      if (prefixIndex == -1) {
        continue;
      }
      final encoded = message
          .substring(prefixIndex + _dartAnalyzeFeedbackSummaryPrefix.length)
          .trim();
      final decoded = _tryDecodeObject(encoded);
      if (decoded.isEmpty) {
        continue;
      }
      final toolName =
          decoded['toolName'] as String? ?? decoded['tool_name'] as String?;
      if (toolName != null && toolName != _dartAnalyzeFeedbackToolName) {
        continue;
      }

      feedbackCount += 1;
      final rawDiagnosticCount =
          decoded['diagnosticCount'] ?? decoded['diagnostic_count'];
      if (rawDiagnosticCount is num) {
        diagnosticCount += rawDiagnosticCount.toInt();
      }

      final rawDurationMs = decoded['durationMs'] ?? decoded['duration_ms'];
      if (rawDurationMs is num) {
        durationMs += rawDurationMs.toInt();
      }
      final rawCommandAttemptCount =
          decoded['commandAttemptCount'] ?? decoded['command_attempt_count'];
      if (rawCommandAttemptCount is num) {
        commandAttemptCount += rawCommandAttemptCount.toInt();
      }
      final rawFallbackCommandCount =
          decoded['fallbackCommandCount'] ?? decoded['fallback_command_count'];
      if (rawFallbackCommandCount is num) {
        fallbackCommandCount += rawFallbackCommandCount.toInt();
      }
      final rawTimedOutCommandCount =
          decoded['timedOutCommandCount'] ?? decoded['timed_out_command_count'];
      if (rawTimedOutCommandCount is num) {
        timedOutCommandCount += rawTimedOutCommandCount.toInt();
      }
      final rawStartErrorCommandCount =
          decoded['startErrorCommandCount'] ??
          decoded['start_error_command_count'];
      if (rawStartErrorCommandCount is num) {
        startErrorCommandCount += rawStartErrorCommandCount.toInt();
      }

      final rawFiles =
          decoded['files'] ??
          decoded['changedPaths'] ??
          decoded['changed_paths'];
      if (rawFiles is Iterable) {
        for (final file in rawFiles) {
          if (file is String && file.trim().isNotEmpty) {
            files.add(file.trim());
          }
        }
      }
    }
  }

  if (feedbackCount == 0 && fallbackFeedbackCount > 0) {
    feedbackCount = fallbackFeedbackCount;
  }

  final sortedFiles = files.toList(growable: false)..sort();
  return LiveLlmCanaryDartAnalyzeFeedbackSignals(
    feedbackCount: feedbackCount,
    diagnosticCount: diagnosticCount,
    files: sortedFiles,
    durationMs: durationMs,
    commandAttemptCount: commandAttemptCount,
    fallbackCommandCount: fallbackCommandCount,
    timedOutCommandCount: timedOutCommandCount,
    startErrorCommandCount: startErrorCommandCount,
  );
}

LiveLlmCanaryDartTestFeedbackSignals _extractDartTestFeedbackSignals(
  String rawLog,
) {
  final files = <String>{};
  final triggers = <String>{};
  final validationStatuses = <String>{};
  var feedbackCount = 0;
  var passedCount = 0;
  var failedCount = 0;
  var skippedCount = 0;
  var durationMs = 0;
  var commandAttemptCount = 0;
  var fallbackCommandCount = 0;
  var timedOutCommandCount = 0;
  var startErrorCommandCount = 0;

  for (final line in const LineSplitter().convert(rawLog)) {
    for (final message in _messagesFromLogLine(line)) {
      final prefixIndex = message.indexOf(_dartTestFeedbackSummaryPrefix);
      if (prefixIndex == -1) {
        continue;
      }
      final encoded = message
          .substring(prefixIndex + _dartTestFeedbackSummaryPrefix.length)
          .trim();
      final decoded = _tryDecodeObject(encoded);
      if (decoded.isEmpty) {
        continue;
      }
      final toolName =
          decoded['toolName'] as String? ?? decoded['tool_name'] as String?;
      if (toolName != null && toolName != _dartTestFeedbackToolName) {
        continue;
      }

      feedbackCount += 1;
      final rawPassedCount = decoded['passedCount'] ?? decoded['passed_count'];
      if (rawPassedCount is num) {
        passedCount += rawPassedCount.toInt();
      }
      final rawFailedCount = decoded['failedCount'] ?? decoded['failed_count'];
      if (rawFailedCount is num) {
        failedCount += rawFailedCount.toInt();
      }
      final rawSkippedCount =
          decoded['skippedCount'] ?? decoded['skipped_count'];
      if (rawSkippedCount is num) {
        skippedCount += rawSkippedCount.toInt();
      }

      final rawDurationMs = decoded['durationMs'] ?? decoded['duration_ms'];
      if (rawDurationMs is num) {
        durationMs += rawDurationMs.toInt();
      }
      final rawCommandAttemptCount =
          decoded['commandAttemptCount'] ?? decoded['command_attempt_count'];
      if (rawCommandAttemptCount is num) {
        commandAttemptCount += rawCommandAttemptCount.toInt();
      }
      final rawFallbackCommandCount =
          decoded['fallbackCommandCount'] ?? decoded['fallback_command_count'];
      if (rawFallbackCommandCount is num) {
        fallbackCommandCount += rawFallbackCommandCount.toInt();
      }
      final rawTimedOutCommandCount =
          decoded['timedOutCommandCount'] ?? decoded['timed_out_command_count'];
      if (rawTimedOutCommandCount is num) {
        timedOutCommandCount += rawTimedOutCommandCount.toInt();
      }
      final rawStartErrorCommandCount =
          decoded['startErrorCommandCount'] ??
          decoded['start_error_command_count'];
      if (rawStartErrorCommandCount is num) {
        startErrorCommandCount += rawStartErrorCommandCount.toInt();
      }

      final rawFiles =
          decoded['files'] ??
          decoded['changedPaths'] ??
          decoded['changed_paths'];
      if (rawFiles is Iterable) {
        for (final file in rawFiles) {
          if (file is String && file.trim().isNotEmpty) {
            files.add(file.trim());
          }
        }
      }

      final trigger = decoded['trigger'];
      if (trigger is String && trigger.trim().isNotEmpty) {
        triggers.add(trigger.trim());
      }
      final validationStatus =
          decoded['validationStatus'] ?? decoded['validation_status'];
      if (validationStatus is String && validationStatus.trim().isNotEmpty) {
        validationStatuses.add(validationStatus.trim());
      }
    }
  }

  return LiveLlmCanaryDartTestFeedbackSignals(
    feedbackCount: feedbackCount,
    passedCount: passedCount,
    failedCount: failedCount,
    skippedCount: skippedCount,
    files: files.toList(growable: false)..sort(),
    triggers: triggers.toList(growable: false)..sort(),
    validationStatuses: validationStatuses.toList(growable: false)..sort(),
    durationMs: durationMs,
    commandAttemptCount: commandAttemptCount,
    fallbackCommandCount: fallbackCommandCount,
    timedOutCommandCount: timedOutCommandCount,
    startErrorCommandCount: startErrorCommandCount,
  );
}

LiveLlmCanaryCodingOutputFeedbackSignals _extractCodingOutputFeedbackSignals(
  String rawLog,
) {
  final commands = <String>{};
  final validationStatuses = <String>{};
  var feedbackCount = 0;
  var issueCount = 0;

  for (final line in const LineSplitter().convert(rawLog)) {
    for (final message in _messagesFromLogLine(line)) {
      final prefixIndex = message.indexOf(_codingOutputFeedbackSummaryPrefix);
      if (prefixIndex == -1) {
        continue;
      }
      final encoded = message
          .substring(prefixIndex + _codingOutputFeedbackSummaryPrefix.length)
          .trim();
      final decoded = _tryDecodeObject(encoded);
      if (decoded.isEmpty) {
        continue;
      }
      final toolName =
          decoded['toolName'] as String? ?? decoded['tool_name'] as String?;
      if (toolName != null && toolName != _codingOutputFeedbackToolName) {
        continue;
      }

      feedbackCount += 1;
      final rawIssueCount = decoded['issueCount'] ?? decoded['issue_count'];
      if (rawIssueCount is num) {
        issueCount += rawIssueCount.toInt();
      }

      final rawCommands = decoded['commands'];
      if (rawCommands is Iterable) {
        for (final command in rawCommands) {
          if (command is String && command.trim().isNotEmpty) {
            commands.add(command.trim());
          }
        }
      }

      final validationStatus =
          decoded['validationStatus'] ?? decoded['validation_status'];
      if (validationStatus is String && validationStatus.trim().isNotEmpty) {
        validationStatuses.add(validationStatus.trim());
      }
    }
  }

  return LiveLlmCanaryCodingOutputFeedbackSignals(
    feedbackCount: feedbackCount,
    issueCount: issueCount,
    commands: commands.toList(growable: false)..sort(),
    validationStatuses: validationStatuses.toList(growable: false)..sort(),
  );
}

Iterable<String> _messagesFromLogLine(String line) sync* {
  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return;
  }
  if (!trimmed.startsWith('{')) {
    yield trimmed;
    return;
  }
  final decoded = _tryDecodeObject(trimmed);
  final message = decoded['message'];
  if (message is String) {
    yield message;
    return;
  }
  yield trimmed;
}

Map<String, dynamic> _tryDecodeObject(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String _inlineCode(String value) {
  return '`${value.replaceAll('`', r'\`').replaceAll('\n', r'\n')}`';
}

String? _joinedFailureMessages(List<String>? messages) {
  if (messages == null || messages.isEmpty) {
    return null;
  }
  return _truncateForSummary(messages.join('\n\n'), 4000);
}

String _truncateForSummary(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...';
}

String _categoryForTestName(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('plain chat') ||
      normalized.contains('memory extraction')) {
    return 'core_chat';
  }
  if (normalized.contains('embedded tool call') ||
      normalized.contains('deferred tool') ||
      normalized.contains('persisted artifact') ||
      normalized.contains('compacted oversized tool results') ||
      normalized.contains('tool-result budget')) {
    return 'core_tool';
  }
  if (normalized.contains('subagent')) {
    return 'subagent';
  }
  if (normalized.contains('recovered incomplete') ||
      normalized.contains('ignored assistant-authored') ||
      normalized.contains('recovers') ||
      normalized.contains('recovery')) {
    return 'recovery';
  }
  if (normalized.contains('load_skill') || normalized.contains('skill')) {
    return 'skill_follow_up';
  }
  return 'uncategorized';
}

String _readinessImpactForCategory(String category, String result) {
  if (result == 'passed') {
    return 'satisfied';
  }
  if (result == 'skipped') {
    return 'skipped';
  }
  switch (category) {
    case 'recovery':
    case 'skill_follow_up':
      return 'warning';
    default:
      return 'blocker';
  }
}
