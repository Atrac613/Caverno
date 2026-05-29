import 'dart:convert';
import 'dart:io';

const _defaultMinimumRepeatCount = 3;
const _schemaName = 'coding_diagnostic_feedback_release_gate';
const _requiredCanaryName = 'coding_diagnostic_feedback_live_canary';
const _requiredSurface = 'coding_diagnostic_feedback';
const _requiredFeedbackFiles = [
  'lib/main.dart',
  'packages/nested_app/lib/main.dart',
];
const _scenarioNames = ['root package', 'nested package'];

Future<void> main(List<String> args) async {
  late final CodingDiagnosticFeedbackReleaseGateOptions options;
  try {
    options = CodingDiagnosticFeedbackReleaseGateOptions.parse(args);
  } on CodingDiagnosticFeedbackReleaseGateUsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(codingDiagnosticFeedbackReleaseGateUsage);
    exitCode = 64;
    return;
  }

  if (options.showHelp) {
    stdout.writeln(codingDiagnosticFeedbackReleaseGateUsage);
    return;
  }

  final CodingDiagnosticFeedbackReleaseGateResult result;
  try {
    result = await buildCodingDiagnosticFeedbackReleaseGate(
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
      'Coding diagnostic feedback release gate JSON written to $outJson',
    );
  }

  final outMarkdown = options.outMarkdownPath;
  if (outMarkdown != null) {
    final file = File(outMarkdown);
    await file.parent.create(recursive: true);
    await file.writeAsString(result.toMarkdown());
    stdout.writeln(
      'Coding diagnostic feedback release gate Markdown written to $outMarkdown',
    );
  }

  stdout.writeln(result.toMarkdown());

  if (result.blockedGateIds.isNotEmpty) {
    stderr.writeln(
      'Coding diagnostic feedback release gate blocked: '
      '${result.blockedGateIds.join(', ')}',
    );
    exitCode = 1;
  }
}

Future<CodingDiagnosticFeedbackReleaseGateResult>
buildCodingDiagnosticFeedbackReleaseGate({
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
  return buildCodingDiagnosticFeedbackReleaseGateFromSummaryJson(
    summaryPath: summaryFile.path,
    summary: decoded,
    minimumRepeatCount: minimumRepeatCount,
    generatedAt: generatedAt,
  );
}

CodingDiagnosticFeedbackReleaseGateResult
buildCodingDiagnosticFeedbackReleaseGateFromSummaryJson({
  required String summaryPath,
  required Map<String, dynamic> summary,
  int minimumRepeatCount = _defaultMinimumRepeatCount,
  DateTime? generatedAt,
}) {
  if (minimumRepeatCount < 1) {
    throw const FormatException('minimumRepeatCount must be at least 1.');
  }

  final signals = _asObject(summary['signals']);
  final dartAnalyzeFeedback = _asObject(signals['dartAnalyzeFeedback']);
  final tests = _asList(summary['tests'])
      .whereType<Map>()
      .map((test) => Map<String, dynamic>.from(test))
      .toList(growable: false);
  final coverage = _DiagnosticFeedbackCoverage.fromTests(tests);
  final feedbackFiles = _stringList(dartAnalyzeFeedback['files']).toSet();
  final recoverySignals = _recoverySignals(signals);

  final gates = [
    _gate(
      id: 'summary_identity',
      label: 'Summary is for the coding diagnostic feedback live canary.',
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
          'Run tool/run_coding_diagnostic_feedback_live_canary.sh and pass its canary_summary.json.',
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
          'Rerun the diagnostic feedback live canary until all tests pass without skipped tests or malformed JSON.',
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
          'Run with CAVERNO_CODING_DIAGNOSTIC_FEEDBACK_LIVE_REPEAT_COUNT=$minimumRepeatCount so each repeat passes root and nested package repair.',
    ),
    _gate(
      id: 'analyzer_feedback_present',
      label: 'Dart analyzer feedback and diagnostics were observed.',
      ready:
          dartAnalyzeFeedback['observed'] == true &&
          _asInt(dartAnalyzeFeedback['feedbackCount']) > 0 &&
          _asInt(dartAnalyzeFeedback['diagnosticCount']) > 0,
      evidence: [
        'observed=${dartAnalyzeFeedback['observed'] ?? '(missing)'}',
        'feedbackCount=${_asInt(dartAnalyzeFeedback['feedbackCount'])}',
        'diagnosticCount=${_asInt(dartAnalyzeFeedback['diagnosticCount'])}',
      ],
      nextAction:
          'Ensure the coding loop injects dart_analyze_feedback after broken Dart edits.',
    ),
    _gate(
      id: 'required_feedback_files',
      label: 'Analyzer feedback covers both root and nested Dart files.',
      ready: feedbackFiles.containsAll(_requiredFeedbackFiles),
      evidence: [
        'required=${_requiredFeedbackFiles.join(', ')}',
        'actual=${feedbackFiles.isEmpty ? '(none)' : feedbackFiles.join(', ')}',
      ],
      nextAction:
          'Keep the root and nested diagnostic feedback scenarios enabled in the live canary.',
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

  return CodingDiagnosticFeedbackReleaseGateResult(
    generatedAt: generatedAt ?? DateTime.now(),
    summaryPath: summaryPath,
    minimumRepeatCount: minimumRepeatCount,
    status: blockedGateIds.isEmpty
        ? 'ready_for_coding_diagnostic_feedback_release'
        : 'blocked',
    blockedGateIds: blockedGateIds,
    gates: gates,
    model: summary['model'] as String?,
    baseUrl: summary['baseUrl'] as String?,
    passedCount: _asInt(summary['passedCount']),
    testCount: _asInt(summary['testCount']),
    feedbackCount: _asInt(dartAnalyzeFeedback['feedbackCount']),
    diagnosticCount: _asInt(dartAnalyzeFeedback['diagnosticCount']),
    feedbackFiles: feedbackFiles.toList(growable: false)..sort(),
    nextAction: blockedGateIds.isEmpty
        ? 'Coding diagnostic feedback release evidence is complete.'
        : 'Resolve blocked diagnostic feedback gates before release.',
  );
}

class CodingDiagnosticFeedbackReleaseGateResult {
  const CodingDiagnosticFeedbackReleaseGateResult({
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
    required this.diagnosticCount,
    required this.feedbackFiles,
    required this.nextAction,
  });

  final DateTime generatedAt;
  final String summaryPath;
  final int minimumRepeatCount;
  final String status;
  final List<String> blockedGateIds;
  final List<CodingDiagnosticFeedbackGate> gates;
  final String? model;
  final String? baseUrl;
  final int passedCount;
  final int testCount;
  final int feedbackCount;
  final int diagnosticCount;
  final List<String> feedbackFiles;
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
    'diagnosticCount': diagnosticCount,
    'feedbackFiles': feedbackFiles,
    'blockedGateIds': blockedGateIds,
    'nextAction': nextAction,
    'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Coding Diagnostic Feedback Release Gate')
      ..writeln()
      ..writeln('- Status: `$status`')
      ..writeln('- Generated at: `${generatedAt.toIso8601String()}`')
      ..writeln('- Summary: `$summaryPath`')
      ..writeln('- Model: `${model ?? 'unknown'}`')
      ..writeln('- Base URL: `${baseUrl ?? 'unknown'}`')
      ..writeln('- Minimum repeat count: `$minimumRepeatCount`')
      ..writeln('- Tests: `$passedCount/$testCount` passed')
      ..writeln('- Analyzer feedback count: `$feedbackCount`')
      ..writeln('- Analyzer diagnostic count: `$diagnosticCount`')
      ..writeln(
        '- Analyzer feedback files: '
        '`${feedbackFiles.isEmpty ? '(none)' : feedbackFiles.join(', ')}`',
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

class CodingDiagnosticFeedbackGate {
  const CodingDiagnosticFeedbackGate({
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

class CodingDiagnosticFeedbackReleaseGateOptions {
  const CodingDiagnosticFeedbackReleaseGateOptions({
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

  static CodingDiagnosticFeedbackReleaseGateOptions parse(List<String> args) {
    var summaryPath = '';
    var minimumRepeatCount = _defaultMinimumRepeatCount;
    String? outJsonPath;
    String? outMarkdownPath;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--help':
        case '-h':
          return const CodingDiagnosticFeedbackReleaseGateOptions(
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
            throw const CodingDiagnosticFeedbackReleaseGateUsageException(
              '--min-repeat-count must be a positive integer.',
            );
          }
        case '--out-json':
          outJsonPath = _readValue(args, ++index, arg);
        case '--out-md':
          outMarkdownPath = _readValue(args, ++index, arg);
        default:
          throw CodingDiagnosticFeedbackReleaseGateUsageException(
            'Unknown argument: $arg',
          );
      }
    }

    if (summaryPath.isEmpty) {
      throw const CodingDiagnosticFeedbackReleaseGateUsageException(
        '--summary is required.',
      );
    }
    return CodingDiagnosticFeedbackReleaseGateOptions(
      summaryPath: summaryPath,
      minimumRepeatCount: minimumRepeatCount,
      outJsonPath: outJsonPath,
      outMarkdownPath: outMarkdownPath,
    );
  }
}

class CodingDiagnosticFeedbackReleaseGateUsageException implements Exception {
  const CodingDiagnosticFeedbackReleaseGateUsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

const codingDiagnosticFeedbackReleaseGateUsage = '''
Usage: dart run tool/coding_diagnostic_feedback_release_gate.dart [options]

Options:
  --summary <path>           Coding diagnostic feedback canary_summary.json.
  --min-repeat-count <n>     Required complete root/nested repeats. Defaults to 3.
  --out-json <path>          Write the gate report as JSON.
  --out-md <path>            Write the gate report as Markdown.
  --help                     Print this help.
''';

CodingDiagnosticFeedbackGate _gate({
  required String id,
  required String label,
  required bool ready,
  required List<String> evidence,
  required String nextAction,
}) {
  return CodingDiagnosticFeedbackGate(
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
    throw CodingDiagnosticFeedbackReleaseGateUsageException(
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

class _DiagnosticFeedbackCoverage {
  const _DiagnosticFeedbackCoverage(this.coveredRuns);

  factory _DiagnosticFeedbackCoverage.fromTests(
    List<Map<String, dynamic>> tests,
  ) {
    final scenariosByRun = <String, Set<String>>{};
    final pattern = RegExp(
      r'^\[(run_\d+)\] live LLM repairs (root package|nested package) Dart after analyzer feedback$',
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
    return _DiagnosticFeedbackCoverage(coveredRuns);
  }

  final List<String> coveredRuns;

  int get completeRunCount => coveredRuns.length;
}
