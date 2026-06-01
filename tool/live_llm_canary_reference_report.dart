import 'dart:convert';
import 'dart:io';

import 'coding_diagnostic_feedback_release_gate.dart';
import 'coding_verification_feedback_release_gate.dart';

Future<void> main(List<String> args) async {
  final options = LiveLlmCanaryReferenceReportOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/live_llm_canary_reference_report.dart '
      '--out-dir PATH --label LABEL '
      '[--report-root PATH] '
      '[--pm5-smoke-report PATH] [--pm5-ping-summary PATH] '
      '[--readme-report PATH] [--coding-goal-summary PATH] '
      '[--coding-overwrite-transparency-summary PATH] '
      '[--coding-goal-edit-summary PATH] '
      '[--coding-diagnostic-feedback-summary PATH] '
      '[--coding-verification-feedback-summary PATH] '
      '[--chat-summary PATH] '
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
      codingGoalSummary: options.optionalFile('coding-goal-summary'),
      codingOverwriteTransparencySummary: options.optionalFile(
        'coding-overwrite-transparency-summary',
      ),
      codingGoalEditSummary: options.optionalFile('coding-goal-edit-summary'),
      codingDiagnosticFeedbackSummary: options.optionalFile(
        'coding-diagnostic-feedback-summary',
      ),
      codingVerificationFeedbackSummary: options.optionalFile(
        'coding-verification-feedback-summary',
      ),
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
  File? codingGoalSummary,
  File? codingOverwriteTransparencySummary,
  File? codingGoalEditSummary,
  File? codingDiagnosticFeedbackSummary,
  File? codingVerificationFeedbackSummary,
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
    codingGoalSummary: codingGoalSummary,
    codingOverwriteTransparencySummary: codingOverwriteTransparencySummary,
    codingGoalEditSummary: codingGoalEditSummary,
    codingDiagnosticFeedbackSummary: codingDiagnosticFeedbackSummary,
    codingVerificationFeedbackSummary: codingVerificationFeedbackSummary,
    chatSummary: chatSummary,
    budgetSummary: budgetSummary,
    routineSummary: routineSummary,
  );
  return buildLiveLlmCanaryReferenceReport(
    label: label,
    pm5SmokeReport: evidence.pm5SmokeReport,
    pm5PingSummary: evidence.pm5PingSummary,
    readmeReport: evidence.readmeReport,
    codingGoalSummary: evidence.codingGoalSummary,
    codingOverwriteTransparencySummary:
        evidence.codingOverwriteTransparencySummary,
    codingGoalEditSummary: evidence.codingGoalEditSummary,
    codingDiagnosticFeedbackSummary: evidence.codingDiagnosticFeedbackSummary,
    codingVerificationFeedbackSummary:
        evidence.codingVerificationFeedbackSummary,
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
  File? codingGoalSummary,
  File? codingOverwriteTransparencySummary,
  File? codingGoalEditSummary,
  File? codingDiagnosticFeedbackSummary,
  File? codingVerificationFeedbackSummary,
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
  if (codingGoalSummary != null) {
    entries.add(await _buildLiveSummaryEntry(codingGoalSummary));
  }
  if (codingOverwriteTransparencySummary != null) {
    entries.add(
      await _buildLiveSummaryEntry(codingOverwriteTransparencySummary),
    );
  }
  if (codingGoalEditSummary != null) {
    entries.add(await _buildLiveSummaryEntry(codingGoalEditSummary));
  }
  if (codingDiagnosticFeedbackSummary != null) {
    entries.add(await _buildLiveSummaryEntry(codingDiagnosticFeedbackSummary));
  }
  if (codingVerificationFeedbackSummary != null) {
    entries.add(
      await _buildLiveSummaryEntry(codingVerificationFeedbackSummary),
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
    schemaVersion: 2,
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
  File? codingGoalSummary,
  File? codingOverwriteTransparencySummary,
  File? codingGoalEditSummary,
  File? codingDiagnosticFeedbackSummary,
  File? codingVerificationFeedbackSummary,
  File? chatSummary,
  File? budgetSummary,
  File? routineSummary,
}) async {
  if (reportRoot == null) {
    return LiveLlmCanaryReferenceEvidenceFiles(
      pm5SmokeReport: pm5SmokeReport,
      pm5PingSummary: pm5PingSummary,
      readmeReport: readmeReport,
      codingGoalSummary: codingGoalSummary,
      codingOverwriteTransparencySummary: codingOverwriteTransparencySummary,
      codingGoalEditSummary: codingGoalEditSummary,
      codingDiagnosticFeedbackSummary: codingDiagnosticFeedbackSummary,
      codingVerificationFeedbackSummary: codingVerificationFeedbackSummary,
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
    codingGoalSummary:
        codingGoalSummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'coding_goal_live_llm_canary_',
          fileName: 'canary_summary.json',
        ),
    codingOverwriteTransparencySummary:
        codingOverwriteTransparencySummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'coding_overwrite_transparency_live_canary_',
          fileName: 'canary_summary.json',
        ),
    codingGoalEditSummary:
        codingGoalEditSummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'coding_goal_live_edit_canary_',
          fileName: 'canary_summary.json',
        ),
    codingDiagnosticFeedbackSummary:
        codingDiagnosticFeedbackSummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'coding_diagnostic_feedback_live_canary_',
          fileName: 'canary_summary.json',
        ),
    codingVerificationFeedbackSummary:
        codingVerificationFeedbackSummary ??
        _findLatestReportFile(
          reportRoot: reportRoot,
          directoryPrefix: 'coding_verification_feedback_live_canary_',
          fileName: 'canary_summary.json',
        ),
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
    required this.codingGoalSummary,
    required this.codingOverwriteTransparencySummary,
    required this.codingGoalEditSummary,
    required this.codingDiagnosticFeedbackSummary,
    required this.codingVerificationFeedbackSummary,
    required this.chatSummary,
    required this.budgetSummary,
    required this.routineSummary,
  });

  final File? pm5SmokeReport;
  final File? pm5PingSummary;
  final File? readmeReport;
  final File? codingGoalSummary;
  final File? codingOverwriteTransparencySummary;
  final File? codingGoalEditSummary;
  final File? codingDiagnosticFeedbackSummary;
  final File? codingVerificationFeedbackSummary;
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
      entries.isNotEmpty &&
      validationErrors.isEmpty &&
      entries.every((entry) => entry.result == 'passed');

  List<String> get validationErrors {
    final errors = <String>[];
    final models = _uniqueNonEmpty(entries.map((entry) => entry.model));
    if (models.length > 1) {
      errors.add('Mixed model evidence: ${models.join(', ')}');
    }
    final baseUrls = _uniqueNonEmpty(
      entries.map((entry) => entry.baseUrl),
      normalize: _normalizeBaseUrl,
    );
    if (baseUrls.length > 1) {
      errors.add('Mixed base URL evidence: ${baseUrls.join(', ')}');
    }
    return errors;
  }

  bool get hasValidationErrors => validationErrors.isNotEmpty;

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
      'validationErrors': validationErrors,
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
      );
    if (validationErrors.isNotEmpty) {
      buffer.writeln('- Validation errors:');
      for (final error in validationErrors) {
        buffer.writeln('  - $error');
      }
    }
    buffer
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
    this.assistantAuthoredToolBlockCount = 0,
    this.transportDisconnectCount = 0,
    this.memoryExtractionFallbackCount = 0,
    this.dartAnalyzeFeedbackCount = 0,
    this.dartAnalyzeDiagnosticCount = 0,
    this.dartTestFeedbackCount = 0,
    this.dartTestFailureCount = 0,
    this.failureClassCounts = const <String, int>{},
  });

  factory LiveLlmCanaryReferenceSignals.fromJson(Map<String, dynamic> json) {
    final dartAnalyzeFeedback = _asObject(json['dartAnalyzeFeedback']);
    final dartAnalyzeFeedbackCount = _asInt(json['dartAnalyzeFeedbackCount']);
    final dartAnalyzeDiagnosticCount = _asInt(
      json['dartAnalyzeDiagnosticCount'],
    );
    final dartTestFeedback = _asObject(json['dartTestFeedback']);
    final dartTestFeedbackCount = _asInt(json['dartTestFeedbackCount']);
    final dartTestFailureCount = _asInt(json['dartTestFailureCount']);
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
      assistantAuthoredToolBlockCount: _asInt(
        json['assistantAuthoredToolBlockCount'],
      ),
      transportDisconnectCount: _asInt(json['transportDisconnectCount']),
      memoryExtractionFallbackCount: _asInt(
        json['memoryExtractionFallbackCount'],
      ),
      dartAnalyzeFeedbackCount: dartAnalyzeFeedbackCount > 0
          ? dartAnalyzeFeedbackCount
          : _asInt(dartAnalyzeFeedback['feedbackCount']),
      dartAnalyzeDiagnosticCount: dartAnalyzeDiagnosticCount > 0
          ? dartAnalyzeDiagnosticCount
          : _asInt(dartAnalyzeFeedback['diagnosticCount']),
      dartTestFeedbackCount: dartTestFeedbackCount > 0
          ? dartTestFeedbackCount
          : _asInt(dartTestFeedback['feedbackCount']),
      dartTestFailureCount: dartTestFailureCount > 0
          ? dartTestFailureCount
          : _asInt(dartTestFeedback['failedCount']),
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
  final int assistantAuthoredToolBlockCount;
  final int transportDisconnectCount;
  final int memoryExtractionFallbackCount;
  final int dartAnalyzeFeedbackCount;
  final int dartAnalyzeDiagnosticCount;
  final int dartTestFeedbackCount;
  final int dartTestFailureCount;
  final Map<String, int> failureClassCounts;

  bool get hasRisk =>
      unexpectedWarningCount > 0 ||
      taskDriftCount > 0 ||
      reportQualityBlockerCount > 0 ||
      recoveredStreamFallbackCount > 0 ||
      assistantAuthoredToolBlockCount > 0 ||
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
      'assistantAuthoredToolBlockCount': assistantAuthoredToolBlockCount,
      'transportDisconnectCount': transportDisconnectCount,
      'memoryExtractionFallbackCount': memoryExtractionFallbackCount,
      'dartAnalyzeFeedbackCount': dartAnalyzeFeedbackCount,
      'dartAnalyzeDiagnosticCount': dartAnalyzeDiagnosticCount,
      'dartTestFeedbackCount': dartTestFeedbackCount,
      'dartTestFailureCount': dartTestFailureCount,
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
    if (assistantAuthoredToolBlockCount > 0) {
      parts.add('assistant tool blocks $assistantAuthoredToolBlockCount');
    }
    if (transportDisconnectCount > 0) {
      parts.add('transport disconnect $transportDisconnectCount');
    }
    if (memoryExtractionFallbackCount > 0) {
      parts.add('memory fallback $memoryExtractionFallbackCount');
    }
    if (dartAnalyzeFeedbackCount > 0 || dartAnalyzeDiagnosticCount > 0) {
      parts.add(
        'analyzer feedback $dartAnalyzeFeedbackCount, diagnostics $dartAnalyzeDiagnosticCount',
      );
    }
    if (dartTestFeedbackCount > 0 || dartTestFailureCount > 0) {
      parts.add(
        'test feedback $dartTestFeedbackCount, failures $dartTestFailureCount',
      );
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
  final dartAnalyzeFeedback = _asObject(signals['dartAnalyzeFeedback']);
  final dartTestFeedback = _asObject(signals['dartTestFeedback']);
  final result = json['result'] as String? ?? 'failed';
  final assistantAuthoredToolBlockCount = _asInt(
    signals['assistantAuthoredToolBlockCount'],
  );
  final isDiagnosticFeedback =
      json['surface'] == 'coding_diagnostic_feedback' ||
      json['canaryName'] == 'coding_diagnostic_feedback_live_canary';
  final diagnosticGate = isDiagnosticFeedback
      ? buildCodingDiagnosticFeedbackReleaseGateFromSummaryJson(
          summaryPath: summaryFile.path,
          summary: json,
        )
      : null;
  final diagnosticGateBlocked =
      diagnosticGate?.blockedGateIds.isNotEmpty == true;
  final isVerificationFeedback =
      json['surface'] == 'coding_verification_feedback' ||
      json['canaryName'] == 'coding_verification_feedback_live_canary';
  final verificationGate = isVerificationFeedback
      ? buildCodingVerificationFeedbackReleaseGateFromSummaryJson(
          summaryPath: summaryFile.path,
          summary: json,
        )
      : null;
  final verificationGateBlocked =
      verificationGate?.blockedGateIds.isNotEmpty == true;

  return LiveLlmCanaryReferenceEntry(
    surface: json['surface'] as String? ?? 'unknown',
    check: json['canaryName'] as String? ?? summaryFile.uri.pathSegments.last,
    result:
        assistantAuthoredToolBlockCount > 0 ||
            diagnosticGateBlocked ||
            verificationGateBlocked
        ? 'failed'
        : result,
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
      assistantAuthoredToolBlockCount: _asInt(
        signals['assistantAuthoredToolBlockCount'],
      ),
      transportDisconnectCount: _asInt(signals['transportDisconnectCount']),
      memoryExtractionFallbackCount: _asInt(
        signals['memoryExtractionFallbackCount'],
      ),
      dartAnalyzeFeedbackCount: _asInt(dartAnalyzeFeedback['feedbackCount']),
      dartAnalyzeDiagnosticCount: _asInt(
        dartAnalyzeFeedback['diagnosticCount'],
      ),
      dartTestFeedbackCount: _asInt(dartTestFeedback['feedbackCount']),
      dartTestFailureCount: _asInt(dartTestFeedback['failedCount']),
      failureClassCounts: {
        for (final gateId in diagnosticGate?.blockedGateIds ?? const <String>[])
          gateId: 1,
        for (final gateId
            in verificationGate?.blockedGateIds ?? const <String>[])
          gateId: 1,
      },
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
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

List<String> _uniqueNonEmpty(
  Iterable<String?> values, {
  String Function(String value)? normalize,
}) {
  final unique = <String>{};
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      continue;
    }
    unique.add(normalize == null ? trimmed : normalize(trimmed));
  }
  return unique.toList(growable: false)..sort();
}

String _normalizeBaseUrl(String value) {
  var normalized = value.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String _baseName(String path) {
  return path.replaceAll(r'\', '/').split('/').last;
}
