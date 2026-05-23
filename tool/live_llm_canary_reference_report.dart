import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = LiveLlmCanaryReferenceReportOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/live_llm_canary_reference_report.dart '
      '--out-dir PATH --label LABEL '
      '[--report-root PATH] '
      '[--pm5-smoke-report PATH] [--pm5-ping-summary PATH] '
      '[--readme-report PATH] [--chat-summary PATH] '
      '[--budget-summary PATH] [--routine-summary PATH]',
    );
    exitCode = 64;
    return;
  }

  final LiveLlmCanaryReferenceReport report;
  try {
    report = await buildLiveLlmCanaryReferenceReportFromArtifacts(
      label: options.label,
      reportRoot: options.optionalDirectory('report-root'),
      pm5SmokeReport: options.optionalFile('pm5-smoke-report'),
      pm5PingSummary: options.optionalFile('pm5-ping-summary'),
      readmeReport: options.optionalFile('readme-report'),
      chatSummary: options.optionalFile('chat-summary'),
      budgetSummary: options.optionalFile('budget-summary'),
      routineSummary: options.optionalFile('routine-summary'),
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

  final outputDirectory = Directory(options.outDir);
  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/reference_report.json');
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  final markdownFile = File('${outputDirectory.path}/reference_report.md');
  await markdownFile.writeAsString(report.toMarkdown());

  stdout.writeln(
    'Live LLM canary reference report written to ${jsonFile.path}',
  );
  stdout.writeln(report.toMarkdown());

  if (!report.isSuccessful) {
    exitCode = 1;
  }
}

Future<LiveLlmCanaryReferenceReport>
buildLiveLlmCanaryReferenceReportFromArtifacts({
  required String label,
  Directory? reportRoot,
  File? pm5SmokeReport,
  File? pm5PingSummary,
  File? readmeReport,
  File? chatSummary,
  File? budgetSummary,
  File? routineSummary,
  DateTime? generatedAt,
}) async {
  final evidence = await resolveLiveLlmCanaryReferenceEvidenceFiles(
    reportRoot: reportRoot,
    pm5SmokeReport: pm5SmokeReport,
    pm5PingSummary: pm5PingSummary,
    readmeReport: readmeReport,
    chatSummary: chatSummary,
    budgetSummary: budgetSummary,
    routineSummary: routineSummary,
  );
  return buildLiveLlmCanaryReferenceReport(
    label: label,
    pm5SmokeReport: evidence.pm5SmokeReport,
    pm5PingSummary: evidence.pm5PingSummary,
    readmeReport: evidence.readmeReport,
    chatSummary: evidence.chatSummary,
    budgetSummary: evidence.budgetSummary,
    routineSummary: evidence.routineSummary,
    generatedAt: generatedAt,
  );
}

Future<LiveLlmCanaryReferenceReport> buildLiveLlmCanaryReferenceReport({
  required String label,
  File? pm5SmokeReport,
  File? pm5PingSummary,
  File? readmeReport,
  File? chatSummary,
  File? budgetSummary,
  File? routineSummary,
  DateTime? generatedAt,
}) async {
  final entries = <LiveLlmCanaryReferenceEntry>[];

  if (pm5SmokeReport != null) {
    entries.add(
      await _buildPlanSuiteEntry(
        surface: 'coding_pm5',
        check: 'PM5 smoke',
        reportFile: pm5SmokeReport,
      ),
    );
  }
  if (pm5PingSummary != null) {
    entries.add(
      await _buildPingSummaryEntry(
        surface: 'coding_ping',
        check: 'PM5 ping',
        summaryFile: pm5PingSummary,
      ),
    );
  }
  if (readmeReport != null) {
    entries.add(
      await _buildPlanSuiteEntry(
        surface: 'coding_artifact',
        check: 'README first',
        reportFile: readmeReport,
      ),
    );
  }
  if (chatSummary != null) {
    entries.add(await _buildLiveSummaryEntry(chatSummary));
  }
  if (budgetSummary != null) {
    entries.add(await _buildLiveSummaryEntry(budgetSummary));
  }
  if (routineSummary != null) {
    entries.add(await _buildLiveSummaryEntry(routineSummary));
  }
  if (entries.isEmpty) {
    throw const FormatException('At least one evidence file is required.');
  }

  return LiveLlmCanaryReferenceReport(
    schemaName: 'live_llm_canary_reference_report',
    schemaVersion: 1,
    generatedAt: generatedAt ?? DateTime.now(),
    label: label,
    entries: entries,
  );
}

Future<LiveLlmCanaryReferenceEvidenceFiles>
resolveLiveLlmCanaryReferenceEvidenceFiles({
  Directory? reportRoot,
  File? pm5SmokeReport,
  File? pm5PingSummary,
  File? readmeReport,
  File? chatSummary,
  File? budgetSummary,
  File? routineSummary,
}) async {
  if (reportRoot == null) {
    return LiveLlmCanaryReferenceEvidenceFiles(
      pm5SmokeReport: pm5SmokeReport,
      pm5PingSummary: pm5PingSummary,
      readmeReport: readmeReport,
      chatSummary: chatSummary,
      budgetSummary: budgetSummary,
      routineSummary: routineSummary,
    );
  }
  if (!reportRoot.existsSync()) {
    throw FileSystemException('Report root not found', reportRoot.path);
  }

  return LiveLlmCanaryReferenceEvidenceFiles(
    pm5SmokeReport:
        pm5SmokeReport ??
        await _findLatestPlanSuiteReport(reportRoot, _isPm5SmokeReport),
    pm5PingSummary:
        pm5PingSummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'plan_mode_ping_cli_canary_',
          fileName: 'canary_summary.json',
        ),
    readmeReport:
        readmeReport ??
        await _findLatestPlanSuiteReport(reportRoot, _isReadmeFirstReport),
    chatSummary:
        chatSummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'chat_live_llm_canary_',
          fileName: 'canary_summary.json',
        ),
    budgetSummary:
        budgetSummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'tool_result_budget_live_canary_',
          fileName: 'canary_summary.json',
        ),
    routineSummary:
        routineSummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'routine_live_llm_canary_',
          fileName: 'canary_summary.json',
        ),
  );
}

class LiveLlmCanaryReferenceEvidenceFiles {
  const LiveLlmCanaryReferenceEvidenceFiles({
    required this.pm5SmokeReport,
    required this.pm5PingSummary,
    required this.readmeReport,
    required this.chatSummary,
    required this.budgetSummary,
    required this.routineSummary,
  });

  final File? pm5SmokeReport;
  final File? pm5PingSummary;
  final File? readmeReport;
  final File? chatSummary;
  final File? budgetSummary;
  final File? routineSummary;
}

class LiveLlmCanaryReferenceReport {
  const LiveLlmCanaryReferenceReport({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.label,
    required this.entries,
  });

  factory LiveLlmCanaryReferenceReport.fromJson(Map<String, dynamic> json) {
    final entries = _asList(json['entries'])
        .whereType<Map>()
        .map(
          (entry) => LiveLlmCanaryReferenceEntry.fromJson(
            Map<String, dynamic>.from(entry),
          ),
        )
        .toList(growable: false);
    return LiveLlmCanaryReferenceReport(
      schemaName:
          json['schemaName'] as String? ?? 'live_llm_canary_reference_report',
      schemaVersion: _asInt(json['schemaVersion']),
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      label: json['label'] as String? ?? 'unlabeled',
      entries: entries,
    );
  }

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String label;
  final List<LiveLlmCanaryReferenceEntry> entries;

  bool get isSuccessful =>
      entries.isNotEmpty && entries.every((entry) => entry.result == 'passed');

  String get result => isSuccessful ? 'passed' : 'failed';

  String? get model => _firstNonEmpty(entries.map((entry) => entry.model));

  String? get baseUrl => _firstNonEmpty(entries.map((entry) => entry.baseUrl));

  int get totalPassed => entries.fold(0, (sum, entry) => sum + entry.passed);

  int get totalCount => entries.fold(0, (sum, entry) => sum + entry.total);

  int get totalFailed => entries.fold(0, (sum, entry) => sum + entry.failed);

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'label': label,
      'result': result,
      'model': model,
      'baseUrl': baseUrl,
      'totalPassed': totalPassed,
      'totalCount': totalCount,
      'totalFailed': totalFailed,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Live LLM Canary Reference Report')
      ..writeln()
      ..writeln('- Label: `$label`')
      ..writeln('- Result: `$result`')
      ..writeln('- Model: `${model ?? 'unknown'}`')
      ..writeln('- Base URL: `${baseUrl ?? 'unknown'}`')
      ..writeln(
        '- Checks: `$totalPassed/$totalCount` passed, `$totalFailed` failed',
      )
      ..writeln()
      ..writeln('| Surface | Check | Result | Pass | Risk Signals | Evidence |')
      ..writeln(
        '|---------|-------|--------|------|--------------|----------|',
      );

    for (final entry in entries) {
      buffer.writeln(
        '| ${_tableCell(entry.surface)} '
        '| ${_tableCell(entry.check)} '
        '| `${entry.result}` '
        '| `${entry.passed}/${entry.total}` '
        '| ${_tableCell(entry.riskSummary)} '
        '| `${_tableCell(entry.evidencePath)}` |',
      );
    }

    return buffer.toString();
  }
}

class LiveLlmCanaryReferenceEntry {
  const LiveLlmCanaryReferenceEntry({
    required this.surface,
    required this.check,
    required this.result,
    required this.model,
    required this.baseUrl,
    required this.evidencePath,
    required this.passed,
    required this.total,
    required this.failed,
    required this.signals,
  });

  factory LiveLlmCanaryReferenceEntry.fromJson(Map<String, dynamic> json) {
    return LiveLlmCanaryReferenceEntry(
      surface: json['surface'] as String? ?? 'unknown',
      check: json['check'] as String? ?? 'unknown',
      result: json['result'] as String? ?? 'failed',
      model: json['model'] as String?,
      baseUrl: json['baseUrl'] as String?,
      evidencePath: json['evidencePath'] as String? ?? '',
      passed: _asInt(json['passed']),
      total: _asInt(json['total']),
      failed: _asInt(json['failed']),
      signals: LiveLlmCanaryReferenceSignals.fromJson(
        _asObject(json['signals']),
      ),
    );
  }

  final String surface;
  final String check;
  final String result;
  final String? model;
  final String? baseUrl;
  final String evidencePath;
  final int passed;
  final int total;
  final int failed;
  final LiveLlmCanaryReferenceSignals signals;

  String get riskSummary => signals.toSummary();

  Map<String, dynamic> toJson() {
    return {
      'surface': surface,
      'check': check,
      'result': result,
      'model': model,
      'baseUrl': baseUrl,
      'evidencePath': evidencePath,
      'passed': passed,
      'total': total,
      'failed': failed,
      'signals': signals.toJson(),
    };
  }
}

class LiveLlmCanaryReferenceSignals {
  const LiveLlmCanaryReferenceSignals({
    this.warningCount = 0,
    this.unexpectedWarningCount = 0,
    this.allowedWarningCount = 0,
    this.taskDriftCount = 0,
    this.reportQualityBlockerCount = 0,
    this.guardActivationCount = 0,
    this.naturalStopCount = 0,
    this.cleanupCancellationCount = 0,
    this.approvalFallbackCount = 0,
    this.recoveredStreamFallbackCount = 0,
    this.toolResultCompactionRetryCount = 0,
    this.transportDisconnectCount = 0,
    this.memoryExtractionFallbackCount = 0,
    this.failureClassCounts = const <String, int>{},
  });

  factory LiveLlmCanaryReferenceSignals.fromJson(Map<String, dynamic> json) {
    return LiveLlmCanaryReferenceSignals(
      warningCount: _asInt(json['warningCount']),
      unexpectedWarningCount: _asInt(json['unexpectedWarningCount']),
      allowedWarningCount: _asInt(json['allowedWarningCount']),
      taskDriftCount: _asInt(json['taskDriftCount']),
      reportQualityBlockerCount: _asInt(json['reportQualityBlockerCount']),
      guardActivationCount: _asInt(json['guardActivationCount']),
      naturalStopCount: _asInt(json['naturalStopCount']),
      cleanupCancellationCount: _asInt(json['cleanupCancellationCount']),
      approvalFallbackCount: _asInt(json['approvalFallbackCount']),
      recoveredStreamFallbackCount: _asInt(
        json['recoveredStreamFallbackCount'],
      ),
      toolResultCompactionRetryCount: _asInt(
        json['toolResultCompactionRetryCount'],
      ),
      transportDisconnectCount: _asInt(json['transportDisconnectCount']),
      memoryExtractionFallbackCount: _asInt(
        json['memoryExtractionFallbackCount'],
      ),
      failureClassCounts: _stringIntMap(json['failureClassCounts']),
    );
  }

  final int warningCount;
  final int unexpectedWarningCount;
  final int allowedWarningCount;
  final int taskDriftCount;
  final int reportQualityBlockerCount;
  final int guardActivationCount;
  final int naturalStopCount;
  final int cleanupCancellationCount;
  final int approvalFallbackCount;
  final int recoveredStreamFallbackCount;
  final int toolResultCompactionRetryCount;
  final int transportDisconnectCount;
  final int memoryExtractionFallbackCount;
  final Map<String, int> failureClassCounts;

  bool get hasRisk =>
      unexpectedWarningCount > 0 ||
      taskDriftCount > 0 ||
      reportQualityBlockerCount > 0 ||
      recoveredStreamFallbackCount > 0 ||
      transportDisconnectCount > 0 ||
      memoryExtractionFallbackCount > 0;

  Map<String, dynamic> toJson() {
    return {
      'warningCount': warningCount,
      'unexpectedWarningCount': unexpectedWarningCount,
      'allowedWarningCount': allowedWarningCount,
      'taskDriftCount': taskDriftCount,
      'reportQualityBlockerCount': reportQualityBlockerCount,
      'guardActivationCount': guardActivationCount,
      'naturalStopCount': naturalStopCount,
      'cleanupCancellationCount': cleanupCancellationCount,
      'approvalFallbackCount': approvalFallbackCount,
      'recoveredStreamFallbackCount': recoveredStreamFallbackCount,
      'toolResultCompactionRetryCount': toolResultCompactionRetryCount,
      'transportDisconnectCount': transportDisconnectCount,
      'memoryExtractionFallbackCount': memoryExtractionFallbackCount,
      'failureClassCounts': failureClassCounts,
    };
  }

  String toSummary() {
    final parts = <String>[];
    if (warningCount > 0 || allowedWarningCount > 0) {
      parts.add('warnings $warningCount, allowed $allowedWarningCount');
    }
    if (unexpectedWarningCount > 0) {
      parts.add('unexpected warnings $unexpectedWarningCount');
    }
    if (taskDriftCount > 0) {
      parts.add('task drift $taskDriftCount');
    }
    if (reportQualityBlockerCount > 0) {
      parts.add('report blockers $reportQualityBlockerCount');
    }
    if (guardActivationCount > 0 || naturalStopCount > 0) {
      parts.add(
        'convergence guard $guardActivationCount, natural $naturalStopCount',
      );
    }
    if (cleanupCancellationCount > 0) {
      parts.add('cleanup cancellations $cleanupCancellationCount');
    }
    if (approvalFallbackCount > 0) {
      parts.add('approval fallback $approvalFallbackCount');
    }
    if (recoveredStreamFallbackCount > 0) {
      parts.add('stream fallback $recoveredStreamFallbackCount');
    }
    if (toolResultCompactionRetryCount > 0) {
      parts.add('compaction retry $toolResultCompactionRetryCount');
    }
    if (transportDisconnectCount > 0) {
      parts.add('transport disconnect $transportDisconnectCount');
    }
    if (memoryExtractionFallbackCount > 0) {
      parts.add('memory fallback $memoryExtractionFallbackCount');
    }
    final failingClasses = failureClassCounts.entries
        .where((entry) => entry.key != 'passed' && entry.value > 0)
        .map((entry) => '${entry.key} ${entry.value}');
    parts.addAll(failingClasses);
    return parts.isEmpty ? 'none' : parts.join('; ');
  }
}

class LiveLlmCanaryReferenceReportOptions {
  const LiveLlmCanaryReferenceReportOptions({
    required this.outDir,
    required this.label,
    required this.values,
  });

  final String outDir;
  final String label;
  final Map<String, String> values;

  File? optionalFile(String name) {
    final path = values[name];
    if (path == null || path.isEmpty) {
      return null;
    }
    return File(path);
  }

  Directory? optionalDirectory(String name) {
    final path = values[name];
    if (path == null || path.isEmpty) {
      return null;
    }
    return Directory(path);
  }

  static LiveLlmCanaryReferenceReportOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--') || index + 1 >= args.length) {
        return null;
      }
      values[arg.substring(2)] = args[index + 1];
      index += 1;
    }

    final outDir = values['out-dir'];
    final label = values['label'];
    if (outDir == null || label == null) {
      return null;
    }
    return LiveLlmCanaryReferenceReportOptions(
      outDir: outDir,
      label: label,
      values: values,
    );
  }
}

Future<LiveLlmCanaryReferenceEntry> _buildPlanSuiteEntry({
  required String surface,
  required String check,
  required File reportFile,
}) async {
  final json = await _readJsonObject(reportFile);
  final scenarioCount = _asInt(json['scenarioCount']);
  final passedCount = _asInt(json['passedCount']);
  final failedCount = _asInt(json['failedCount']);
  final warnings = _asObject(json['warningSummary']);
  final taskDrift = _asObject(json['taskDriftSummary']);
  final reportQuality = _asObject(json['reportQualitySummary']);
  final convergence = _asObject(json['toolLoopConvergenceSummary']);
  final scenarios = _asList(json['scenarios']);
  final unexpectedWarnings = _asInt(warnings['unexpectedWarnings']);
  final taskDriftCount = _asInt(taskDrift['detected']);
  final blockerCount = _asInt(reportQuality['blockerCount']);

  return LiveLlmCanaryReferenceEntry(
    surface: surface,
    check: check,
    result:
        failedCount == 0 &&
            unexpectedWarnings == 0 &&
            taskDriftCount == 0 &&
            blockerCount == 0
        ? 'passed'
        : 'failed',
    model: json['model'] as String?,
    baseUrl: json['baseUrl'] as String?,
    evidencePath: reportFile.path,
    passed: passedCount,
    total: scenarioCount,
    failed: failedCount,
    signals: LiveLlmCanaryReferenceSignals(
      warningCount: _asInt(warnings['warnings']),
      unexpectedWarningCount: unexpectedWarnings,
      allowedWarningCount: _asInt(warnings['allowedWarnings']),
      taskDriftCount: taskDriftCount,
      reportQualityBlockerCount: blockerCount,
      guardActivationCount: _asInt(convergence['guardActivations']),
      naturalStopCount: _asInt(convergence['naturalStops']),
      cleanupCancellationCount: scenarios
          .where(
            (scenario) =>
                scenario is Map &&
                scenario['postScenarioCancellationUsed'] == true,
          )
          .length,
      approvalFallbackCount: scenarios
          .where(
            (scenario) =>
                scenario is Map &&
                scenario['usedHarnessApprovalFallback'] == true,
          )
          .length,
    ),
  );
}

Future<LiveLlmCanaryReferenceEntry> _buildPingSummaryEntry({
  required String surface,
  required String check,
  required File summaryFile,
}) async {
  final json = await _readJsonObject(summaryFile);
  final runCount = _asInt(json['runCount']);
  final passedCount = _asInt(json['passedCount']);
  final failedCount = _asInt(json['failedCount']);
  final runs = _asList(json['runs']);
  final blockerCount = runs.fold<int>(
    0,
    (sum, run) =>
        sum + (run is Map ? _asInt(run['reportQualityBlockerCount']) : 0),
  );
  final failureClassCounts = _stringIntMap(json['failureClassCounts']);

  return LiveLlmCanaryReferenceEntry(
    surface: surface,
    check: check,
    result: failedCount == 0 && blockerCount == 0 ? 'passed' : 'failed',
    model: null,
    baseUrl: null,
    evidencePath: summaryFile.path,
    passed: passedCount,
    total: runCount,
    failed: failedCount,
    signals: LiveLlmCanaryReferenceSignals(
      reportQualityBlockerCount: blockerCount,
      failureClassCounts: failureClassCounts,
    ),
  );
}

Future<LiveLlmCanaryReferenceEntry> _buildLiveSummaryEntry(
  File summaryFile,
) async {
  final json = await _readJsonObject(summaryFile);
  final signals = _asObject(json['signals']);
  final result = json['result'] as String? ?? 'failed';

  return LiveLlmCanaryReferenceEntry(
    surface: json['surface'] as String? ?? 'unknown',
    check: json['canaryName'] as String? ?? summaryFile.uri.pathSegments.last,
    result: result,
    model: json['model'] as String?,
    baseUrl: json['baseUrl'] as String?,
    evidencePath: summaryFile.path,
    passed: _asInt(json['passedCount']),
    total: _asInt(json['testCount']),
    failed: _asInt(json['failedCount']),
    signals: LiveLlmCanaryReferenceSignals(
      recoveredStreamFallbackCount: _asInt(
        signals['recoveredStreamFallbackCount'],
      ),
      toolResultCompactionRetryCount: _asInt(
        signals['toolResultCompactionRetryCount'],
      ),
      transportDisconnectCount: _asInt(signals['transportDisconnectCount']),
      memoryExtractionFallbackCount: _asInt(
        signals['memoryExtractionFallbackCount'],
      ),
    ),
  );
}

Future<File?> _findLatestPlanSuiteReport(
  Directory reportRoot,
  bool Function(Map<String, dynamic> json) predicate,
) async {
  final candidates = _findReportFiles(
    reportRoot: reportRoot,
    directoryPrefix: 'plan_mode_live_suite_macos_',
    fileName: 'plan_mode_live_suite_macos_report.json',
  );
  final matches = <File>[];
  for (final candidate in candidates) {
    final json = await _readJsonObject(candidate);
    if (predicate(json)) {
      matches.add(candidate);
    }
  }
  return matches.isEmpty ? null : matches.last;
}

File? _findLatestReportFile({
  required Directory reportRoot,
  required String directoryPrefix,
  required String fileName,
}) {
  final candidates = _findReportFiles(
    reportRoot: reportRoot,
    directoryPrefix: directoryPrefix,
    fileName: fileName,
  );
  return candidates.isEmpty ? null : candidates.last;
}

List<File> _findReportFiles({
  required Directory reportRoot,
  required String directoryPrefix,
  required String fileName,
}) {
  final files = reportRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where(
        (file) =>
            _baseName(file.path) == fileName &&
            _baseName(file.parent.path).startsWith(directoryPrefix),
      )
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

bool _isReadmeFirstReport(Map<String, dynamic> json) {
  return _stringList(
    json['requestedScenarioNames'],
  ).contains('live_readme_first_canary');
}

bool _isPm5SmokeReport(Map<String, dynamic> json) {
  final requestedScenarios = _stringList(json['requestedScenarioNames']);
  if (requestedScenarios.contains('live_readme_first_canary') ||
      requestedScenarios.contains('live_ping_cli_completion')) {
    return false;
  }
  final scenarioNames = _asList(json['scenarios'])
      .whereType<Map>()
      .map((scenario) => scenario['scenario'] as String?)
      .whereType<String>()
      .toSet();
  const smokeScenarios = {
    'live_host_health_scaffold',
    'live_cli_entrypoint_decision',
    'live_clarify_recovery',
  };
  return scenarioNames.containsAll(smokeScenarios) ||
      requestedScenarios.isEmpty && _asInt(json['scenarioCount']) >= 3;
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  if (!file.existsSync()) {
    throw FileSystemException('Evidence file not found', file.path);
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in ${file.path}.');
  }
  return decoded;
}

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

Map<String, int> _stringIntMap(Object? value) {
  if (value is! Map) {
    return const <String, int>{};
  }
  return Map<String, int>.fromEntries(
    value.entries.map((entry) => MapEntry('${entry.key}', _asInt(entry.value))),
  );
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String _baseName(String path) {
  return path.replaceAll(r'\', '/').split('/').last;
}
