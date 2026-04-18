import 'dart:convert';

class PlanModeCanaryRunSummary {
  const PlanModeCanaryRunSummary({
    required this.name,
    required this.status,
    required this.failureClass,
    required this.durationMs,
    this.error,
    this.reportPath,
    this.logPath,
  });

  final String name;
  final String status;
  final String failureClass;
  final int durationMs;
  final String? error;
  final String? reportPath;
  final String? logPath;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'status': status,
      'failureClass': failureClass,
      'durationMs': durationMs,
      'error': error,
      'reportPath': reportPath,
      'logPath': logPath,
    };
  }
}

class PlanModeCanarySummary {
  const PlanModeCanarySummary({
    required this.runCount,
    required this.passedCount,
    required this.failedCount,
    required this.failureClassCounts,
    required this.runs,
  });

  final int runCount;
  final int passedCount;
  final int failedCount;
  final Map<String, int> failureClassCounts;
  final List<PlanModeCanaryRunSummary> runs;

  double get passRate => runCount == 0 ? 0 : passedCount / runCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'runCount': runCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'passRate': passRate,
      'failureClassCounts': failureClassCounts,
      'runs': runs.map((run) => run.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Plan Mode Live Canary Summary')
      ..writeln()
      ..writeln('- Run count: $runCount')
      ..writeln('- Passed: $passedCount')
      ..writeln('- Failed: $failedCount')
      ..writeln('- Pass rate: ${(passRate * 100).toStringAsFixed(1)}%')
      ..writeln()
      ..writeln('| Run | Status | Failure Class | Duration (ms) | Error |')
      ..writeln('| --- | --- | --- | ---: | --- |');

    for (final run in runs) {
      buffer.writeln(
        '| ${run.name} | ${run.status} | ${run.failureClass} | ${run.durationMs} | ${run.error ?? '-'} |',
      );
    }

    if (failureClassCounts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Failure Classes')
        ..writeln();
      for (final entry in failureClassCounts.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
    }

    return buffer.toString();
  }
}

PlanModeCanarySummary buildPlanModeCanarySummary(
  List<Map<String, dynamic>> suiteReports,
) {
  final runs = <PlanModeCanaryRunSummary>[];
  final failureClassCounts = <String, int>{};

  for (final suiteReport in suiteReports) {
    final scenarios =
        (suiteReport['scenarios'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>();
    for (final scenario in scenarios) {
      final failureClass =
          (scenario['failureClass'] as String?)?.trim().isNotEmpty == true
          ? scenario['failureClass'] as String
          : (scenario['status'] == 'passed' ? 'passed' : 'unclassified');
      failureClassCounts.update(
        failureClass,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      runs.add(
        PlanModeCanaryRunSummary(
          name: scenario['scenario'] as String? ?? 'unknown',
          status: scenario['status'] as String? ?? 'failed',
          failureClass: failureClass,
          durationMs: scenario['durationMs'] as int? ?? 0,
          error: scenario['error'] as String?,
          reportPath: scenario['scenarioReport'] as String?,
          logPath: scenario['scenarioLog'] as String?,
        ),
      );
    }
  }

  final passedCount = runs.where((run) => run.status == 'passed').length;
  return PlanModeCanarySummary(
    runCount: runs.length,
    passedCount: passedCount,
    failedCount: runs.length - passedCount,
    failureClassCounts: Map<String, int>.unmodifiable(failureClassCounts),
    runs: List<PlanModeCanaryRunSummary>.unmodifiable(runs),
  );
}

List<Map<String, dynamic>> decodeCanarySuiteReports(List<String> jsonContents) {
  return jsonContents
      .map((content) => jsonDecode(content) as Map<String, dynamic>)
      .toList(growable: false);
}
