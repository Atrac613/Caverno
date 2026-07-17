import 'package:flutter/material.dart';

@immutable
class ComputerUseLiveSmokeStatusRow {
  const ComputerUseLiveSmokeStatusRow({
    required this.label,
    required this.isPositive,
    required this.positiveText,
    required this.negativeText,
  });

  final String label;
  final bool isPositive;
  final String positiveText;
  final String negativeText;

  String get statusText => isPositive ? positiveText : negativeText;
}

@immutable
class ComputerUseLiveSmokeSummaryViewModel {
  ComputerUseLiveSmokeSummaryViewModel({
    required this.heading,
    required Iterable<ComputerUseLiveSmokeStatusRow> statusRows,
    required Iterable<String> details,
  }) : statusRows = List.unmodifiable(statusRows),
       details = List.unmodifiable(details);

  factory ComputerUseLiveSmokeSummaryViewModel.fromEnvelope(
    Map<String, dynamic> reportEnvelope,
  ) {
    return _LiveSmokeSummaryMapper(reportEnvelope).build();
  }

  final String heading;
  final List<ComputerUseLiveSmokeStatusRow> statusRows;
  final List<String> details;
}

class ComputerUseLiveSmokeSummary extends StatelessWidget {
  const ComputerUseLiveSmokeSummary({super.key, required this.viewModel});

  final ComputerUseLiveSmokeSummaryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(viewModel.heading, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final row in viewModel.statusRows)
              _LiveSmokeStatusChip(row: row),
          ],
        ),
        for (final detail in viewModel.details) ...[
          const SizedBox(height: 4),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _LiveSmokeStatusChip extends StatelessWidget {
  const _LiveSmokeStatusChip({required this.row});

  final ComputerUseLiveSmokeStatusRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = row.isPositive ? colorScheme.primary : colorScheme.outline;
    return Chip(
      avatar: Icon(
        row.isPositive
            ? Icons.check_circle_outline
            : Icons.radio_button_unchecked,
        size: 18,
        color: color,
      ),
      label: Text('${row.label}: ${row.statusText}'),
    );
  }
}

class _LiveSmokeSummaryMapper {
  _LiveSmokeSummaryMapper(this.reportEnvelope);

  final Map<String, dynamic> reportEnvelope;

  ComputerUseLiveSmokeSummaryViewModel build() {
    final report = _report();
    final generatedAt = report['generatedAt'];
    final path = reportEnvelope['path'] ?? report['reportPath'];
    final ok = report['ok'] == true;
    final coreOk = report['coreOk'] == true;
    final captureOk = report['captureOk'] == true;
    final signingDiagnostics = _mapValue(report['signingDiagnostics']);
    final xpcRuntimeDiagnostics = _mapValue(report['xpcRuntimeDiagnostics']);
    final permissionGate = _mapValue(report['permissionGate']);
    final captureGate = _mapValue(report['captureGate']);
    final inputGate = _mapValue(report['inputGate']);
    final audioGate = _mapValue(report['audioGate']);
    final unsafeActionGate = _mapValue(report['unsafeActionGate']);
    final positiveSmokeGateSummary = _mapValue(
      report['positiveSmokeGateSummary'],
    );
    final readinessExpectations = _mapValue(report['readinessExpectations']);
    final m4SignoffGate = _mapValue(report['m4SignoffGate']);
    final signingBlockers = _stringList(
      signingDiagnostics?['launchConstraintBlockers'],
    );
    final runtimeBlockers = _stringList(xpcRuntimeDiagnostics?['blockers']);
    final permissionBlockers = _stringList(
      permissionGate?['blockedByPermissions'],
    );
    final captureBlockers = _stringList(captureGate?['blockers']);
    final captureFailureClasses = _stringList(captureGate?['failureClasses']);
    final captureFailureClass = _stringValue(captureGate?['failureClass']);
    final captureNextAction = _stringValue(captureGate?['nextAction']);
    final inputBlockers = _stringList(inputGate?['blockers']);
    final audioBlockers = _stringList(audioGate?['blockers']);
    final unsafeBlockers = _stringList(unsafeActionGate?['blockers']);
    final positiveSmokeBlockers = _stringList(
      positiveSmokeGateSummary?['blockedBy'],
    );
    final failedExpectations = _stringList(readinessExpectations?['failed']);
    final m4SignoffBlockers = _stringList(m4SignoffGate?['blockers']);
    final m4SignoffHelperPath = _stringValue(
      _mapValue(m4SignoffGate?['helperPath'])?['embeddedHelperPath'],
    );
    final m4SignoffNextAction = _stringValue(m4SignoffGate?['nextAction']);
    final heading = generatedAt is String
        ? 'Last live smoke: ${ok ? 'passed' : 'needs attention'} at $generatedAt'
        : 'Last live smoke: ${ok ? 'passed' : 'needs attention'}';
    final statusRows = <ComputerUseLiveSmokeStatusRow>[
      ComputerUseLiveSmokeStatusRow(
        label: 'Live Core',
        isPositive: coreOk,
        positiveText: 'Passed',
        negativeText: 'Needs attention',
      ),
      ComputerUseLiveSmokeStatusRow(
        label: 'Live Capture',
        isPositive: captureOk,
        positiveText: 'Passed',
        negativeText: 'Needs attention',
      ),
      if (signingDiagnostics != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Signing',
          isPositive: signingBlockers.isEmpty,
          positiveText: 'Accepted',
          negativeText: 'Blocked',
        ),
      if (xpcRuntimeDiagnostics != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live XPC Runtime',
          isPositive: runtimeBlockers.isEmpty,
          positiveText: 'Ready',
          negativeText: 'Blocked',
        ),
      if (permissionGate != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Permissions',
          isPositive: permissionBlockers.isEmpty,
          positiveText: 'Clear',
          negativeText: 'Blocked',
        ),
      if (captureGate != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Capture Gate',
          isPositive: captureBlockers.isEmpty,
          positiveText: 'Ready',
          negativeText: '${captureGate['status']}',
        ),
      if (inputGate != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Input Gate',
          isPositive: inputBlockers.isEmpty,
          positiveText: 'Ready',
          negativeText: '${inputGate['status']}',
        ),
      if (audioGate != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Audio Gate',
          isPositive:
              audioBlockers.isEmpty || audioGate['status'] == 'unsupported',
          positiveText: audioGate['status'] == 'unsupported'
              ? 'Unsupported'
              : 'Ready',
          negativeText: '${audioGate['status']}',
        ),
      if (unsafeActionGate != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Unsafe Gate',
          isPositive: unsafeActionGate['unsafeArmed'] == true,
          positiveText: 'Armed',
          negativeText: 'Not armed',
        ),
      if (positiveSmokeGateSummary != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Positive Smoke',
          isPositive: positiveSmokeGateSummary['status'] == 'ready',
          positiveText: 'Ready',
          negativeText: '${positiveSmokeGateSummary['status']}',
        ),
      if (readinessExpectations != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Expectations',
          isPositive: readinessExpectations['ok'] == true,
          positiveText: 'Passed',
          negativeText: 'Failed',
        ),
      if (m4SignoffGate != null)
        ComputerUseLiveSmokeStatusRow(
          label: 'Live M4 Sign-off',
          isPositive: m4SignoffGate['status'] == 'ready',
          positiveText: 'Ready',
          negativeText: '${m4SignoffGate['status']}',
        ),
    ];
    final blockerDetails = <String>[
      if (signingBlockers.isNotEmpty) 'signing: ${signingBlockers.join(', ')}',
      if (runtimeBlockers.isNotEmpty) 'runtime: ${runtimeBlockers.join(', ')}',
      if (permissionBlockers.isNotEmpty)
        'permissions: ${permissionBlockers.join(', ')}',
      if (captureBlockers.isNotEmpty) 'capture: ${captureBlockers.join(', ')}',
      if (inputBlockers.isNotEmpty) 'input: ${inputBlockers.join(', ')}',
      if (audioBlockers.isNotEmpty) 'audio: ${audioBlockers.join(', ')}',
      if (unsafeBlockers.isNotEmpty) 'unsafe: ${unsafeBlockers.join(', ')}',
      if (positiveSmokeBlockers.isNotEmpty)
        'positive smoke: ${positiveSmokeBlockers.join(', ')}',
      if (m4SignoffBlockers.isNotEmpty) 'm4: ${m4SignoffBlockers.join(', ')}',
      if (failedExpectations.isNotEmpty)
        'expectations: ${failedExpectations.join(', ')}',
    ];
    final details = <String>[
      if (blockerDetails.isNotEmpty) blockerDetails.join(' | '),
      if (m4SignoffHelperPath != null)
        'Live M4 helper: ${_shortPath(m4SignoffHelperPath)}',
      if (m4SignoffNextAction != null)
        'Live M4 next action: $m4SignoffNextAction',
      if (captureFailureClass != null && captureFailureClass != 'none')
        'Live capture failure: ${captureFailureClasses.isEmpty ? captureFailureClass : captureFailureClasses.join(', ')}',
      if (captureNextAction != null)
        'Live capture next action: $captureNextAction',
      if (path is String && path.isNotEmpty) 'Live smoke report: $path',
    ];

    return ComputerUseLiveSmokeSummaryViewModel(
      heading: heading,
      statusRows: statusRows,
      details: details,
    );
  }

  Map<String, dynamic> _report() {
    final report = reportEnvelope['report'];
    if (report is Map) {
      return Map<String, dynamic>.from(report);
    }
    return reportEnvelope;
  }

  Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  String _shortPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 4) {
      return path;
    }
    return '.../${parts.sublist(parts.length - 4).join('/')}';
  }
}
