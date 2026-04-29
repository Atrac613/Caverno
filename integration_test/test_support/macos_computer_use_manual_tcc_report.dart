import 'dart:convert';
import 'dart:io';

class ManualTccCheckSummary {
  const ManualTccCheckSummary({
    required this.id,
    required this.label,
    required this.status,
    required this.ok,
    this.nextAction,
  });

  final String id;
  final String label;
  final String status;
  final bool ok;
  final String? nextAction;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'status': status,
      'ok': ok,
      'nextAction': nextAction,
    };
  }
}

class ManualTccReportSummary {
  const ManualTccReportSummary({
    required this.reportPath,
    required this.status,
    required this.ready,
    required this.blockers,
    required this.appPath,
    required this.helperPath,
    required this.nextAction,
    required this.checks,
  });

  final String reportPath;
  final String status;
  final bool ready;
  final List<String> blockers;
  final String? appPath;
  final String? helperPath;
  final String? nextAction;
  final List<ManualTccCheckSummary> checks;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_manual_tcc_report_summary',
      'schemaVersion': 1,
      'automationBoundary': 'parse_user_produced_report_only',
      'reportPath': reportPath,
      'status': status,
      'ready': ready,
      'blockers': blockers,
      'appPath': appPath,
      'helperPath': helperPath,
      'nextAction': nextAction,
      'checks': checks.map((check) => check.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use Manual TCC Report')
      ..writeln()
      ..writeln('- Automation boundary: parse user-produced report only')
      ..writeln('- Status: $status')
      ..writeln('- Ready: $ready')
      ..writeln(
        '- Blockers: ${blockers.isEmpty ? 'none' : blockers.join(', ')}',
      );

    if (appPath != null) {
      buffer.writeln('- Release app: `$appPath`');
    }
    if (helperPath != null) {
      buffer.writeln('- Release helper: `$helperPath`');
    }
    if (nextAction != null && nextAction!.trim().isNotEmpty) {
      buffer.writeln('- Next action: $nextAction');
    }

    buffer
      ..writeln()
      ..writeln('| Check | Status | Result | Next Action |')
      ..writeln('| --- | --- | --- | --- |');
    for (final check in checks) {
      buffer.writeln(
        '| ${_markdownCell(check.label)} | ${_markdownCell(check.status)} | ${check.ok ? 'ok' : 'blocked'} | ${_markdownCell(check.nextAction)} |',
      );
    }

    return buffer.toString();
  }
}

ManualTccReportSummary readManualTccReport(File reportFile) {
  final decoded = jsonDecode(reportFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Manual TCC report must be a JSON object.');
  }
  return buildManualTccReportSummary(decoded, reportPath: reportFile.path);
}

ManualTccReportSummary buildManualTccReportSummary(
  Map<String, dynamic> report, {
  required String reportPath,
}) {
  final gate = _mapValue(report['releaseRuntimeSignoffGate']);
  final blockers = _stringList(gate['blockers']);
  final status = gate['status'] as String? ?? 'missing';
  final checks = _listValue(gate['checks'])
      .whereType<Map<String, dynamic>>()
      .map(
        (check) => ManualTccCheckSummary(
          id: check['id'] as String? ?? 'unknown',
          label:
              check['label'] as String? ?? check['id'] as String? ?? 'unknown',
          status: check['status'] as String? ?? 'unknown',
          ok: check['ok'] == true,
          nextAction: check['nextAction'] as String?,
        ),
      )
      .toList(growable: false);

  return ManualTccReportSummary(
    reportPath: reportPath,
    status: status,
    ready: status == 'ready' && blockers.isEmpty,
    blockers: List<String>.unmodifiable(blockers),
    appPath: gate['appPath'] as String?,
    helperPath: gate['helperPath'] as String?,
    nextAction: gate['nextAction'] as String?,
    checks: List<ManualTccCheckSummary>.unmodifiable(checks),
  );
}

Map<String, dynamic> _mapValue(Object? value) {
  return value is Map<String, dynamic> ? value : const <String, dynamic>{};
}

List<dynamic> _listValue(Object? value) {
  return value is List<dynamic> ? value : const <dynamic>[];
}

List<String> _stringList(Object? value) {
  return _listValue(value).map((item) => item.toString()).toList();
}

String _markdownCell(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return '-';
  }
  return text.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
