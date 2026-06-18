import 'dart:convert';
import 'dart:io';

const _defaultMinimumRepeatCount = 3;
const _schemaName = 'coding_verification_feedback_release_gate';
const _requiredCanaryName = 'coding_verification_feedback_live_canary';
const _requiredSurface = 'coding_verification_feedback';
const _requiredFeedbackFiles = [
  'lib/canary_value.dart',
  'packages/nested_app/lib/canary_value.dart',
];
const _scenarioNames = ['root package', 'nested package'];

Future<void> main(List<String> args) async {
  late final CodingVerificationFeedbackReleaseGateOptions options;
  try {
    options = CodingVerificationFeedbackReleaseGateOptions.parse(args);
  } on CodingVerificationFeedbackReleaseGateUsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(codingVerificationFeedbackReleaseGateUsage);
    exitCode = 64;
    return;
  }

  if (options.showHelp) {
    stdout.writeln(codingVerificationFeedbackReleaseGateUsage);
    return;
  }

  final CodingVerificationFeedbackReleaseGateResult result;
  try {
    result = await buildCodingVerificationFeedbackReleaseGate(
      summaryFile: File(options.summaryPath),
      minimumRepeatCount: options.minimumRepeatCount,
    );
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    exitCode = 66;
    return;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
    return;
  }

  final encoded = const JsonEncoder.withIndent('  ').convert(result.toJson());
  final outJson = options.outJsonPath;
  if (outJson == null) {
    stdout.writeln(encoded);
  } else {
    final file = File(outJson);
    await file.parent.create(recursive: true);
    await file.writeAsString(encoded);
    stdout.writeln(
      'Coding verification feedback release gate JSON written to $outJson',
    );
  }

  final outMarkdown = options.outMarkdownPath;
  if (outMarkdown != null) {
    final file = File(outMarkdown);
    await file.parent.create(recursive: true);
    await file.writeAsString(result.toMarkdown());
    stdout.writeln(
      'Coding verification feedback release gate Markdown written to '
      '$outMarkdown',
    );
  }

  stdout.writeln(result.toMarkdown());

  if (result.blockedGateIds.isNotEmpty) {
    stderr.writeln(
      'Coding verification feedback release gate blocked: '
      '${result.blockedGateIds.join(', ')}',
    );
    exitCode = 1;
  }
}

Future<CodingVerificationFeedbackReleaseGateResult>
buildCodingVerificationFeedbackReleaseGate({
  required File summaryFile,
  int minimumRepeatCount = _defaultMinimumRepeatCount,
  DateTime? generatedAt,
}) async {
  if (!summaryFile.existsSync()) {
    throw FileSystemException('Summary file not found', summaryFile.path);
  }
  final decoded = jsonDecode(await summaryFile.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in ${summaryFile.path}.');
  }
  return buildCodingVerificationFeedbackReleaseGateFromSummaryJson(
    summaryPath: summaryFile.path,
    summary: decoded,
    minimumRepeatCount: minimumRepeatCount,
    generatedAt: generatedAt,
  );
}

CodingVerificationFeedbackReleaseGateResult
buildCodingVerificationFeedbackReleaseGateFromSummaryJson({
  required String summaryPath,
  required Map<String, dynamic> summary,
  int minimumRepeatCount = _defaultMinimumRepeatCount,
  DateTime? generatedAt,
}) {
  if (minimumRepeatCount < 1) {
    throw const FormatException('minimumRepeatCount must be at least 1.');
  }

  final signals = _asObject(summary['signals']);
  final dartTestFeedback = _asObject(signals['dartTestFeedback']);
  final tests = _asList(summary['tests'])
      .whereType<Map>()
      .map((test) => Map<String, dynamic>.from(test))
      .toList(growable: false);
  final coverage = _VerificationFeedbackCoverage.fromTests(tests);
  final feedbackFiles = _stringList(dartTestFeedback['files']).toSet();
  final triggers = _stringList(dartTestFeedback['triggers']).toSet();
  final validationStatuses = _stringList(
    dartTestFeedback['validationStatuses'],
  ).toSet();
  final feedbackDurationMs = _asInt(dartTestFeedback['durationMs']);
  final commandAttemptCount = _asInt(dartTestFeedback['commandAttemptCount']);
  final fallbackCommandCount = _asInt(dartTestFeedback['fallbackCommandCount']);
  final timedOutCommandCount = _asInt(dartTestFeedback['timedOutCommandCount']);
  final startErrorCommandCount = _asInt(
    dartTestFeedback['startErrorCommandCount'],
  );
  final feedbackCount = _asInt(dartTestFeedback['feedbackCount']);
  final failedCount = _asInt(dartTestFeedback['failedCount']);
  final recoverySignals = _recoverySignals(signals);

  final gates = [
    _gate(
      id: 'summary_identity',
      label: 'Summary is for the coding verification feedback live canary.',
      ready:
          summary['schemaName'] == 'live_llm_canary_summary' &&
          summary['canaryName'] == _requiredCanaryName &&
          summary['surface'] == _requiredSurface,
      evidence: [
        'schemaName=${summary['schemaName'] ?? '(missing)'}',
        'canaryName=${summary['canaryName'] ?? '(missing)'}',
        'surface=${summary['surface'] ?? '(missing)'}',
      ],
      nextAction:
          'Run tool/run_coding_verification_feedback_live_canary.sh and pass its canary_summary.json.',
    ),
    _gate(
      id: 'metadata_present',
      label: 'Summary records model, endpoint, command, and source log path.',
      ready:
          _nonEmpty(summary['model']) &&
          _nonEmpty(summary['baseUrl']) &&
          _nonEmpty(summary['command']) &&
          _nonEmpty(summary['logPath']),
      evidence: [
        'model=${summary['model'] ?? '(missing)'}',
        'baseUrl=${summary['baseUrl'] ?? '(missing)'}',
        'command=${summary['command'] ?? '(missing)'}',
        'logPath=${summary['logPath'] ?? '(missing)'}',
      ],
      nextAction:
          'Regenerate the live canary summary with model, endpoint, command, and log metadata.',
    ),
    _gate(
      id: 'live_result_passed',
      label: 'Live run completed with no failed, skipped, or malformed tests.',
      ready:
          summary['result'] == 'passed' &&
          summary['runnerSuccess'] == true &&
          summary['doneSeen'] == true &&
          _asInt(summary['failedCount']) == 0 &&
          _asInt(summary['skippedCount']) == 0 &&
          _asInt(summary['malformedJsonLineCount']) == 0,
      evidence: [
        'result=${summary['result'] ?? '(missing)'}',
        'runnerSuccess=${summary['runnerSuccess'] ?? '(missing)'}',
        'doneSeen=${summary['doneSeen'] ?? '(missing)'}',
        'failedCount=${_asInt(summary['failedCount'])}',
        'skippedCount=${_asInt(summary['skippedCount'])}',
        'malformedJsonLineCount=${_asInt(summary['malformedJsonLineCount'])}',
      ],
      nextAction:
          'Rerun the verification feedback live canary until all tests pass without skipped tests or malformed JSON.',
    ),
    _gate(
      id: 'repeat_coverage',
      label:
          'Root and nested package scenarios passed in each required repeat.',
      ready:
          _asInt(summary['testCount']) >= minimumRepeatCount * 2 &&
          _asInt(summary['passedCount']) == _asInt(summary['testCount']) &&
          coverage.completeRunCount >= minimumRepeatCount,
      evidence: [
        'minimumRepeatCount=$minimumRepeatCount',
        'testCount=${_asInt(summary['testCount'])}',
        'passedCount=${_asInt(summary['passedCount'])}',
        'completeRuns=${coverage.completeRunCount}',
        'coveredRuns=${coverage.coveredRuns.join(', ')}',
      ],
      nextAction:
          'Run with CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_REPEAT_COUNT=$minimumRepeatCount so each repeat passes root and nested package repair.',
    ),
    _gate(
      id: 'test_feedback_present',
      label: 'Dart test feedback and failing tests were observed.',
      ready:
          dartTestFeedback['observed'] == true &&
          feedbackCount > 0 &&
          failedCount > 0,
      evidence: [
        'observed=${dartTestFeedback['observed'] ?? '(missing)'}',
        'feedbackCount=$feedbackCount',
        'failedCount=$failedCount',
      ],
      nextAction:
          'Ensure the coding loop injects dart_test_feedback after a completion claim with failing tests.',
    ),
    _gate(
      id: 'completion_claim_feedback',
      label: 'Verification feedback came from failed completion-claim checks.',
      ready:
          triggers.contains('completionClaim') &&
          validationStatuses.contains('failed'),
      evidence: [
        'triggers=${triggers.isEmpty ? '(none)' : triggers.join(', ')}',
        'validationStatuses=${validationStatuses.isEmpty ? '(none)' : validationStatuses.join(', ')}',
      ],
      nextAction:
          'Keep the live canary scripted premature completion path enabled so completion-claim verification is proven.',
    ),
    _gate(
      id: 'required_feedback_files',
      label: 'Test feedback covers both root and nested Dart files.',
      ready: feedbackFiles.containsAll(_requiredFeedbackFiles),
      evidence: [
        'required=${_requiredFeedbackFiles.join(', ')}',
        'actual=${feedbackFiles.isEmpty ? '(none)' : feedbackFiles.join(', ')}',
      ],
      nextAction:
          'Keep the root and nested verification feedback scenarios enabled in the live canary.',
    ),
    _gate(
      id: 'verification_feedback_telemetry_present',
      label: 'Test feedback reports command latency and fallback telemetry.',
      ready:
          feedbackDurationMs > 0 &&
          commandAttemptCount >= feedbackCount &&
          fallbackCommandCount >= 0 &&
          timedOutCommandCount >= 0 &&
          startErrorCommandCount >= 0,
      evidence: [
        'durationMs=$feedbackDurationMs',
        'commandAttemptCount=$commandAttemptCount',
        'fallbackCommandCount=$fallbackCommandCount',
        'timedOutCommandCount=$timedOutCommandCount',
        'startErrorCommandCount=$startErrorCommandCount',
      ],
      nextAction:
          'Regenerate the live canary summary from logs that include test feedback telemetry.',
    ),
    _gate(
      id: 'recovery_signals_clean',
      label: 'Live run used no recovery fallbacks or transport retries.',
      ready: recoverySignals.values.every((value) => value == 0),
      evidence: recoverySignals.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .toList(growable: false),
      nextAction:
          'Investigate Live LLM transport and tool-loop recovery signals before release.',
    ),
  ];

  final blockedGateIds = [
    for (final gate in gates)
      if (!gate.isReady) gate.id,
  ];

  return CodingVerificationFeedbackReleaseGateResult(
    generatedAt: generatedAt ?? DateTime.now(),
    summaryPath: summaryPath,
    minimumRepeatCount: minimumRepeatCount,
    status: blockedGateIds.isEmpty
        ? 'ready_for_coding_verification_feedback_release'
        : 'blocked',
    blockedGateIds: blockedGateIds,
    gates: gates,
    model: summary['model'] as String?,
    baseUrl: summary['baseUrl'] as String?,
    passedCount: _asInt(summary['passedCount']),
    testCount: _asInt(summary['testCount']),
    feedbackCount: feedbackCount,
    testFailureCount: failedCount,
    testPassedCount: _asInt(dartTestFeedback['passedCount']),
    testSkippedCount: _asInt(dartTestFeedback['skippedCount']),
    feedbackDurationMs: feedbackDurationMs,
    commandAttemptCount: commandAttemptCount,
    fallbackCommandCount: fallbackCommandCount,
    timedOutCommandCount: timedOutCommandCount,
    startErrorCommandCount: startErrorCommandCount,
    feedbackFiles: feedbackFiles.toList(growable: false)..sort(),
    triggers: triggers.toList(growable: false)..sort(),
    validationStatuses: validationStatuses.toList(growable: false)..sort(),
    nextAction: blockedGateIds.isEmpty
        ? 'Coding verification feedback release evidence is complete.'
        : 'Resolve blocked verification feedback gates before release.',
  );
}

class CodingVerificationFeedbackReleaseGateResult {
  const CodingVerificationFeedbackReleaseGateResult({
    required this.generatedAt,
    required this.summaryPath,
    required this.minimumRepeatCount,
    required this.status,
    required this.blockedGateIds,
    required this.gates,
    required this.model,
    required this.baseUrl,
    required this.passedCount,
    required this.testCount,
    required this.feedbackCount,
    required this.testFailureCount,
    required this.testPassedCount,
    required this.testSkippedCount,
    required this.feedbackDurationMs,
    required this.commandAttemptCount,
    required this.fallbackCommandCount,
    required this.timedOutCommandCount,
    required this.startErrorCommandCount,
    required this.feedbackFiles,
    required this.triggers,
    required this.validationStatuses,
    required this.nextAction,
  });

  final DateTime generatedAt;
  final String summaryPath;
  final int minimumRepeatCount;
  final String status;
  final List<String> blockedGateIds;
  final List<CodingVerificationFeedbackGate> gates;
  final String? model;
  final String? baseUrl;
  final int passedCount;
  final int testCount;
  final int feedbackCount;
  final int testFailureCount;
  final int testPassedCount;
  final int testSkippedCount;
  final int feedbackDurationMs;
  final int commandAttemptCount;
  final int fallbackCommandCount;
  final int timedOutCommandCount;
  final int startErrorCommandCount;
  final List<String> feedbackFiles;
  final List<String> triggers;
  final List<String> validationStatuses;
  final String nextAction;

  bool get isReady => blockedGateIds.isEmpty;

  Map<String, Object?> toJson() => {
    'schemaName': _schemaName,
    'schemaVersion': 1,
    'generatedAt': generatedAt.toIso8601String(),
    'status': status,
    'summaryPath': summaryPath,
    'minimumRepeatCount': minimumRepeatCount,
    'model': model,
    'baseUrl': baseUrl,
    'passedCount': passedCount,
    'testCount': testCount,
    'feedbackCount': feedbackCount,
    'testFailureCount': testFailureCount,
    'testPassedCount': testPassedCount,
    'testSkippedCount': testSkippedCount,
    'feedbackDurationMs': feedbackDurationMs,
    'commandAttemptCount': commandAttemptCount,
    'fallbackCommandCount': fallbackCommandCount,
    'timedOutCommandCount': timedOutCommandCount,
    'startErrorCommandCount': startErrorCommandCount,
    'feedbackFiles': feedbackFiles,
    'triggers': triggers,
    'validationStatuses': validationStatuses,
    'blockedGateIds': blockedGateIds,
    'nextAction': nextAction,
    'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Coding Verification Feedback Release Gate')
      ..writeln()
      ..writeln('- Status: `$status`')
      ..writeln('- Generated at: `${generatedAt.toIso8601String()}`')
      ..writeln('- Summary: `$summaryPath`')
      ..writeln('- Model: `${model ?? 'unknown'}`')
      ..writeln('- Base URL: `${baseUrl ?? 'unknown'}`')
      ..writeln('- Minimum repeat count: `$minimumRepeatCount`')
      ..writeln('- Tests: `$passedCount/$testCount` passed')
      ..writeln('- Test feedback count: `$feedbackCount`')
      ..writeln('- Test failure count: `$testFailureCount`')
      ..writeln('- Test passed count: `$testPassedCount`')
      ..writeln('- Test skipped count: `$testSkippedCount`')
      ..writeln('- Test feedback duration: `$feedbackDurationMs ms`')
      ..writeln('- Test command attempts: `$commandAttemptCount`')
      ..writeln('- Test fallback commands: `$fallbackCommandCount`')
      ..writeln('- Test timed-out commands: `$timedOutCommandCount`')
      ..writeln('- Test start-error commands: `$startErrorCommandCount`')
      ..writeln(
        '- Test feedback files: '
        '`${feedbackFiles.isEmpty ? '(none)' : feedbackFiles.join(', ')}`',
      )
      ..writeln(
        '- Triggers: `${triggers.isEmpty ? '(none)' : triggers.join(', ')}`',
      )
      ..writeln(
        '- Validation statuses: '
        '`${validationStatuses.isEmpty ? '(none)' : validationStatuses.join(', ')}`',
      )
      ..writeln('- Next action: $nextAction')
      ..writeln()
      ..writeln('## Gates');
    for (final gate in gates) {
      buffer
        ..writeln()
        ..writeln('- `${gate.id}`: `${gate.status}`')
        ..writeln('  - ${gate.label}');
      for (final evidence in gate.evidence) {
        buffer.writeln('  - Evidence: $evidence');
      }
      if (gate.nextAction.isNotEmpty && !gate.isReady) {
        buffer.writeln('  - Next action: ${gate.nextAction}');
      }
    }
    return buffer.toString();
  }
}

class CodingVerificationFeedbackGate {
  const CodingVerificationFeedbackGate({
    required this.id,
    required this.label,
    required this.status,
    required this.evidence,
    required this.nextAction,
  });

  final String id;
  final String label;
  final String status;
  final List<String> evidence;
  final String nextAction;

  bool get isReady => status == 'ready';

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'status': status,
    'evidence': evidence,
    if (nextAction.isNotEmpty) 'nextAction': nextAction,
  };
}

class CodingVerificationFeedbackReleaseGateOptions {
  const CodingVerificationFeedbackReleaseGateOptions({
    required this.summaryPath,
    required this.minimumRepeatCount,
    this.outJsonPath,
    this.outMarkdownPath,
    this.showHelp = false,
  });

  final String summaryPath;
  final int minimumRepeatCount;
  final String? outJsonPath;
  final String? outMarkdownPath;
  final bool showHelp;

  static CodingVerificationFeedbackReleaseGateOptions parse(List<String> args) {
    var summaryPath = '';
    var minimumRepeatCount = _defaultMinimumRepeatCount;
    String? outJsonPath;
    String? outMarkdownPath;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--help':
        case '-h':
          return const CodingVerificationFeedbackReleaseGateOptions(
            summaryPath: '',
            minimumRepeatCount: _defaultMinimumRepeatCount,
            showHelp: true,
          );
        case '--summary':
          summaryPath = _readValue(args, ++index, arg);
        case '--min-repeat-count':
          final raw = _readValue(args, ++index, arg);
          minimumRepeatCount = int.tryParse(raw) ?? -1;
          if (minimumRepeatCount < 1) {
            throw const CodingVerificationFeedbackReleaseGateUsageException(
              '--min-repeat-count must be a positive integer.',
            );
          }
        case '--out-json':
          outJsonPath = _readValue(args, ++index, arg);
        case '--out-md':
          outMarkdownPath = _readValue(args, ++index, arg);
        default:
          throw CodingVerificationFeedbackReleaseGateUsageException(
            'Unknown argument: $arg',
          );
      }
    }

    if (summaryPath.isEmpty) {
      throw const CodingVerificationFeedbackReleaseGateUsageException(
        '--summary is required.',
      );
    }
    return CodingVerificationFeedbackReleaseGateOptions(
      summaryPath: summaryPath,
      minimumRepeatCount: minimumRepeatCount,
      outJsonPath: outJsonPath,
      outMarkdownPath: outMarkdownPath,
    );
  }
}

class CodingVerificationFeedbackReleaseGateUsageException implements Exception {
  const CodingVerificationFeedbackReleaseGateUsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

const codingVerificationFeedbackReleaseGateUsage = '''
Usage: dart run tool/coding_verification_feedback_release_gate.dart [options]

Options:
  --summary <path>           Coding verification feedback canary_summary.json.
  --min-repeat-count <n>     Required complete root/nested repeats. Defaults to 3.
  --out-json <path>          Write the gate report as JSON.
  --out-md <path>            Write the gate report as Markdown.
  --help                     Print this help.
''';

CodingVerificationFeedbackGate _gate({
  required String id,
  required String label,
  required bool ready,
  required List<String> evidence,
  required String nextAction,
}) {
  return CodingVerificationFeedbackGate(
    id: id,
    label: label,
    status: ready ? 'ready' : 'blocked',
    evidence: evidence,
    nextAction: nextAction,
  );
}

Map<String, int> _recoverySignals(Map<String, dynamic> signals) {
  return {
    'recoveredStreamFallbackCount': _asInt(
      signals['recoveredStreamFallbackCount'],
    ),
    'toolResultCompactionRetryCount': _asInt(
      signals['toolResultCompactionRetryCount'],
    ),
    'codingContinuationRecoveryRequestCount': _asInt(
      signals['codingContinuationRecoveryRequestCount'],
    ),
    'codingContinuationRecoveryToolCallCount': _asInt(
      signals['codingContinuationRecoveryToolCallCount'],
    ),
    'turnFinalizationRecoveryRequestCount': _asInt(
      signals['turnFinalizationRecoveryRequestCount'],
    ),
    'turnFinalizationRecoveryToolCallCount': _asInt(
      signals['turnFinalizationRecoveryToolCallCount'],
    ),
    'incompleteContentToolRecoveryCount': _asInt(
      signals['incompleteContentToolRecoveryCount'],
    ),
    'ignoredAssistantToolResultCount': _asInt(
      signals['ignoredAssistantToolResultCount'],
    ),
    'assistantAuthoredToolBlockCount': _asInt(
      signals['assistantAuthoredToolBlockCount'],
    ),
    'transportDisconnectCount': _asInt(signals['transportDisconnectCount']),
    'memoryExtractionFallbackCount': _asInt(
      signals['memoryExtractionFallbackCount'],
    ),
  };
}

String _readValue(List<String> args, int index, String option) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw CodingVerificationFeedbackReleaseGateUsageException(
      '$option requires a value.',
    );
  }
  return args[index];
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

Map<String, dynamic> _asObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const <Object?>[];
}

List<String> _stringList(Object? value) {
  return _asList(value).whereType<String>().toList(growable: false);
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

class _VerificationFeedbackCoverage {
  const _VerificationFeedbackCoverage(this.coveredRuns);

  factory _VerificationFeedbackCoverage.fromTests(
    List<Map<String, dynamic>> tests,
  ) {
    final scenariosByRun = <String, Set<String>>{};
    final pattern = RegExp(
      r'^\[(run_\d+)\] live LLM repairs (root package|nested package) Dart after test feedback$',
    );
    for (final test in tests) {
      if (test['result'] != 'passed' || test['skipped'] == true) {
        continue;
      }
      final name = test['name'];
      if (name is! String) {
        continue;
      }
      final match = pattern.firstMatch(name);
      if (match == null) {
        continue;
      }
      scenariosByRun
          .putIfAbsent(match.group(1)!, () => <String>{})
          .add(match.group(2)!);
    }

    final coveredRuns =
        scenariosByRun.entries
            .where((entry) => entry.value.containsAll(_scenarioNames))
            .map((entry) => entry.key)
            .toList(growable: false)
          ..sort();
    return _VerificationFeedbackCoverage(coveredRuns);
  }

  final List<String> coveredRuns;

  int get completeRunCount => coveredRuns.length;
}
