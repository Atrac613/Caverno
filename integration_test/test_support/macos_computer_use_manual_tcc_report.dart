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
    required this.failureClasses,
    required this.appPath,
    required this.helperPath,
    required this.nextAction,
    required this.checks,
    this.captureFailureClasses = const <String>[],
    this.captureNextAction,
  });

  final String reportPath;
  final String status;
  final bool ready;
  final List<String> blockers;
  final List<String> failureClasses;
  final String? appPath;
  final String? helperPath;
  final String? nextAction;
  final List<ManualTccCheckSummary> checks;
  final List<String> captureFailureClasses;
  final String? captureNextAction;

  List<ManualTccCheckSummary> get failedChecks =>
      checks.where((check) => !check.ok).toList(growable: false);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_manual_tcc_report_summary',
      'schemaVersion': 1,
      'automationBoundary': 'parse_user_produced_report_only',
      'reportPath': reportPath,
      'status': status,
      'ready': ready,
      'blockers': blockers,
      'failureClasses': failureClasses,
      'appPath': appPath,
      'helperPath': helperPath,
      'nextAction': nextAction,
      'captureFailureClasses': captureFailureClasses,
      'captureNextAction': captureNextAction,
      'failedChecks': failedChecks
          .map((check) => check.toJson())
          .toList(growable: false),
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
      )
      ..writeln(
        '- Failure classes: ${failureClasses.isEmpty ? 'none' : failureClasses.join(', ')}',
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
    if (captureFailureClasses.isNotEmpty) {
      buffer.writeln(
        '- Capture failure classes: ${captureFailureClasses.join(', ')}',
      );
    }
    if (captureNextAction != null && captureNextAction!.trim().isNotEmpty) {
      buffer.writeln('- Capture next action: $captureNextAction');
    }

    if (failedChecks.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Failed Checks')
        ..writeln()
        ..writeln('| Check | Status | Next Action |')
        ..writeln('| --- | --- | --- |');
      for (final check in failedChecks) {
        buffer.writeln(
          '| ${_markdownCell(check.label)} | ${_markdownCell(check.status)} | ${_markdownCell(check.nextAction)} |',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('## All Checks')
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
  final captureGate = _mapValue(report['captureGate']);
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
    failureClasses: List<String>.unmodifiable(
      _classifyManualTccFailures(blockers, checks),
    ),
    appPath: gate['appPath'] as String?,
    helperPath: gate['helperPath'] as String?,
    nextAction: gate['nextAction'] as String?,
    checks: List<ManualTccCheckSummary>.unmodifiable(checks),
    captureFailureClasses: List<String>.unmodifiable(
      _stringList(captureGate['failureClasses']),
    ),
    captureNextAction: captureGate['nextAction'] as String?,
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

List<String> _classifyManualTccFailures(
  List<String> blockers,
  List<ManualTccCheckSummary> checks,
) {
  final classes = <String>{};
  void add(String value) {
    classes.add(value);
  }

  for (final blocker in blockers) {
    switch (blocker) {
      case 'release_artifact_gate_blocked':
        add('release_artifact_blocked');
      case 'release_runtime_app_path_mismatch':
        add('app_path_mismatch');
      case 'release_runtime_helper_path_mismatch':
        add('helper_path_mismatch');
      case 'release_runtime_permission_status_failed':
        add('permission_status_failed');
      case 'release_runtime_permissions_blocked':
        add('permissions_missing');
      case 'release_runtime_capture_blocked':
        add('capture_blocked');
      case 'release_runtime_input_blocked':
        add('input_blocked');
      case 'release_runtime_audio_blocked':
        add('audio_blocked');
      default:
        add('manual_tcc_blocked');
    }
  }

  for (final check in checks.where((check) => !check.ok)) {
    switch (check.id) {
      case 'release_app_path':
        add('app_path_mismatch');
      case 'release_helper_path':
        add('helper_path_mismatch');
      case 'permission_status':
        add('permission_status_failed');
      case 'accessibility':
      case 'screen_capture':
        add('permissions_missing');
      case 'display_screenshot':
      case 'window_capture':
        add('capture_blocked');
      case 'system_audio_resolved':
        add('audio_blocked');
      default:
        add('manual_tcc_check_failed');
    }
  }

  return classes.toList(growable: false)..sort();
}

String _markdownCell(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return '-';
  }
  return text.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
