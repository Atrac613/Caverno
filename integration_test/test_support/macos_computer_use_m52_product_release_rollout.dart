import 'dart:convert';
import 'dart:io';

class MacosComputerUseM52ProductReleaseGate {
  const MacosComputerUseM52ProductReleaseGate({
    required this.id,
    required this.label,
    required this.status,
    required this.ready,
    required this.nextAction,
    required this.userOperated,
    this.artifactPath,
    this.details = const <String, Object?>{},
  });

  final String id;
  final String label;
  final String status;
  final bool ready;
  final String nextAction;
  final bool userOperated;
  final String? artifactPath;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'status': status,
      'ready': ready,
      'nextAction': nextAction,
      'userOperated': userOperated,
      'artifactPath': artifactPath,
      'details': details,
    };
  }
}

class MacosComputerUseM52ProductReleaseSummary {
  const MacosComputerUseM52ProductReleaseSummary({
    required this.status,
    required this.ready,
    required this.gates,
  });

  final String status;
  final bool ready;
  final List<MacosComputerUseM52ProductReleaseGate> gates;

  List<MacosComputerUseM52ProductReleaseGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  List<MacosComputerUseM52ProductReleaseGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<MacosComputerUseM52ProductReleaseGate> get userOperatedGates =>
      gates.where((gate) => gate.userOperated).toList(growable: false);

  Map<String, Object?> get releaseRolloutSummary {
    final readyGateIds = readyGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedGateIds = blockedGates
        .map((gate) => gate.id)
        .toList(growable: false);
    return <String, Object?>{
      'status': ready ? 'ready_for_product_release' : 'blocked_gates_present',
      'readyGateIds': readyGateIds,
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedGates
          .where((gate) => gate.userOperated)
          .map((gate) => gate.id)
          .toList(growable: false),
      'blockedAutomationSafeGateIds': blockedGates
          .where((gate) => !gate.userOperated)
          .map((gate) => gate.id)
          .toList(growable: false),
      'operationBoundarySummary':
          'M52 reads M51 launch evidence and user-operated rollout checklist evidence only; Advanced settings rollout, rollback, support, TCC, and desktop actions remain user-operated.',
    };
  }

  Map<String, Object?> get m52ProductReleaseGate {
    return <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockedGates.map((gate) => gate.id).toList(growable: false),
      'nextAction': ready
          ? 'Ship element-grounded Computer Use through the product release rollout.'
          : 'Resolve blocked M52 product release rollout gates before shipping.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m52_product_release_rollout',
      'schemaVersion': 1,
      'milestone': 'M52',
      'automationBoundary': 'read_reports_only',
      'tccBoundary': 'user_operated',
      'desktopActionBoundary': 'user_operated',
      'status': status,
      'ready': ready,
      'readyGateIds': readyGates.map((gate) => gate.id).toList(growable: false),
      'blockedGateIds': blockedGates
          .map((gate) => gate.id)
          .toList(growable: false),
      'userOperatedGateIds': userOperatedGates
          .map((gate) => gate.id)
          .toList(growable: false),
      'releaseRolloutSummary': releaseRolloutSummary,
      'm52ProductReleaseGate': m52ProductReleaseGate,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = releaseRolloutSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M52 Product Release Rollout')
      ..writeln()
      ..writeln('- Automation boundary: read reports only')
      ..writeln('- TCC boundary: user-operated')
      ..writeln('- Desktop action boundary: user-operated')
      ..writeln('- Status: $status')
      ..writeln('- Ready: $ready')
      ..writeln(
        '- Blocked gates: ${blockedGates.isEmpty ? 'none' : blockedGates.map((gate) => gate.id).join(', ')}',
      )
      ..writeln();

    buffer
      ..writeln('## Product Release Summary')
      ..writeln()
      ..writeln('- Status: ${review['status']}')
      ..writeln(
        '- Ready gates: ${_joinedOrNone(_stringList(review['readyGateIds']))}',
      )
      ..writeln(
        '- Blocked gates: ${_joinedOrNone(_stringList(review['blockedGateIds']))}',
      )
      ..writeln(
        '- Blocked user-operated gates: ${_joinedOrNone(_stringList(review['blockedUserOperatedGateIds']))}',
      )
      ..writeln(
        '- Blocked automation-safe gates: ${_joinedOrNone(_stringList(review['blockedAutomationSafeGateIds']))}',
      )
      ..writeln('- Boundary: ${review['operationBoundarySummary']}')
      ..writeln();

    if (blockedGates.isNotEmpty) {
      buffer
        ..writeln('## Blocked Gates')
        ..writeln()
        ..writeln('| Gate | Status | Next Action | Artifact |')
        ..writeln('| --- | --- | --- | --- |');
      for (final gate in blockedGates) {
        buffer.writeln(
          '| ${_markdownCell(gate.label)} | ${_markdownCell(gate.status)} | ${_markdownCell(gate.nextAction)} | ${_artifactCell(gate.artifactPath)} |',
        );
      }
      buffer.writeln();
    }

    buffer
      ..writeln('## All Gates')
      ..writeln()
      ..writeln(
        '| Gate | Status | Ready | User Operated | Next Action | Artifact |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final gate in gates) {
      buffer.writeln(
        '| ${_markdownCell(gate.label)} | ${_markdownCell(gate.status)} | ${gate.ready} | ${gate.userOperated} | ${_markdownCell(gate.nextAction)} | ${_artifactCell(gate.artifactPath)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Product Release Checklist Template')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(m52ProductReleaseChecklistTemplate()),
      )
      ..writeln('```');

    return buffer.toString();
  }
}

class MacosComputerUseM52ProductReleaseInputs {
  const MacosComputerUseM52ProductReleaseInputs({
    required this.productReleaseChecklist,
    required this.productReleaseChecklistPath,
    required this.m51ProductionLaunchGate,
    required this.m51ProductionLaunchGatePath,
  });

  final Map<String, dynamic>? productReleaseChecklist;
  final String? productReleaseChecklistPath;
  final Map<String, dynamic>? m51ProductionLaunchGate;
  final String? m51ProductionLaunchGatePath;
}

Map<String, Object?> m52ProductReleaseChecklistTemplate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m52_product_release_checklist',
    'schemaVersion': 1,
    'milestone': 'M52',
    'automationBoundary': 'user_operated_release_steps',
    'defaultOffConfirmed': _readyTemplate(
      '<Computer Use remains default off for product release>',
    ),
    'advancedSettingsConfirmed': _readyTemplate(
      '<Settings > Advanced entry point verified>',
    ),
    'reversibleDisablePath': _readyTemplate(
      '<Disable path and emergency stop verified>',
    ),
    'rollbackRunbookReady': _readyTemplate('<rollback runbook sign-off note>'),
    'supportRunbookReady': _readyTemplate('<support runbook sign-off note>'),
    'privacyReleaseNotesReady': _readyTemplate(
      '<privacy copy and release notes sign-off note>',
    ),
    'supportDiagnosticsReady': _readyTemplate(
      '<support diagnostics handoff verified>',
    ),
    'rolloutMonitoringReady': _readyTemplate(
      '<rollout owner, monitoring, and escalation sign-off note>',
    ),
  };
}

MacosComputerUseM52ProductReleaseSummary
buildMacosComputerUseM52ProductReleaseSummary(
  MacosComputerUseM52ProductReleaseInputs inputs,
) {
  final gates = <MacosComputerUseM52ProductReleaseGate>[
    _m51ProductionLaunchGate(
      inputs.m51ProductionLaunchGate,
      inputs.m51ProductionLaunchGatePath,
    ),
    _checklistGate(
      id: 'default_off_confirmed',
      label: 'Default-off release',
      field: 'defaultOffConfirmed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm Computer Use remains default off for product release.',
    ),
    _checklistGate(
      id: 'advanced_settings_confirmed',
      label: 'Advanced settings entry point',
      field: 'advancedSettingsConfirmed',
      inputs: inputs,
      nextAction:
          'Ask the user to verify Computer Use can be enabled only through Settings > Advanced.',
    ),
    _checklistGate(
      id: 'reversible_disable_path',
      label: 'Reversible disable path',
      field: 'reversibleDisablePath',
      inputs: inputs,
      nextAction:
          'Ask the user to validate the disable path and emergency stop behavior.',
    ),
    _checklistGate(
      id: 'rollback_runbook_ready',
      label: 'Rollback runbook',
      field: 'rollbackRunbookReady',
      inputs: inputs,
      nextAction:
          'Ask the user to complete rollback runbook sign-off for the product release.',
    ),
    _checklistGate(
      id: 'support_runbook_ready',
      label: 'Support runbook',
      field: 'supportRunbookReady',
      inputs: inputs,
      nextAction:
          'Ask the user to complete support runbook sign-off for the product release.',
    ),
    _checklistGate(
      id: 'privacy_release_notes_ready',
      label: 'Privacy and release notes',
      field: 'privacyReleaseNotesReady',
      inputs: inputs,
      nextAction:
          'Ask the user to approve privacy copy and release notes for product release.',
    ),
    _checklistGate(
      id: 'support_diagnostics_ready',
      label: 'Support diagnostics handoff',
      field: 'supportDiagnosticsReady',
      inputs: inputs,
      nextAction:
          'Ask the user to verify support diagnostics handoff before product release.',
    ),
    _checklistGate(
      id: 'rollout_monitoring_ready',
      label: 'Rollout monitoring',
      field: 'rolloutMonitoringReady',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm rollout monitoring, owner, and escalation coverage.',
    ),
  ];
  final ready = gates.every((gate) => gate.ready);
  return MacosComputerUseM52ProductReleaseSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    gates: List<MacosComputerUseM52ProductReleaseGate>.unmodifiable(gates),
  );
}

MacosComputerUseM52ProductReleaseInputs
readMacosComputerUseM52ProductReleaseInputs({
  required Directory reportRoot,
  String? productReleaseChecklistPath,
  String? m51ProductionLaunchGatePath,
}) {
  final checklistFile = productReleaseChecklistPath == null
      ? discoverLatestM52ProductReleaseChecklist(reportRoot)
      : File(productReleaseChecklistPath);
  final m51File = m51ProductionLaunchGatePath == null
      ? discoverLatestM51ProductionLaunchGate(reportRoot)
      : File(m51ProductionLaunchGatePath);
  return MacosComputerUseM52ProductReleaseInputs(
    productReleaseChecklist: _readJsonObject(checklistFile),
    productReleaseChecklistPath: checklistFile?.path,
    m51ProductionLaunchGate: _readJsonObject(m51File),
    m51ProductionLaunchGatePath: m51File?.path,
  );
}

File? discoverLatestM52ProductReleaseChecklist(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m52_product_release_checklist';
  });
}

File? discoverLatestM51ProductionLaunchGate(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m51_production_launch_gate';
  });
}

MacosComputerUseM52ProductReleaseGate _m51ProductionLaunchGate(
  Map<String, dynamic>? report,
  String? reportPath,
) {
  if (report == null) {
    return const MacosComputerUseM52ProductReleaseGate(
      id: 'm51_production_launch_gate',
      label: 'M51 production launch gate',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M51 production launch gate before preparing the M52 product release rollout.',
      userOperated: false,
    );
  }
  final review = _mapValue(report['launchReviewSummary']);
  final gate = _mapValue(report['m51ProductionLaunchGate']);
  final blockers = <String>{
    ..._stringList(report['blockedGateIds']),
    ..._stringList(review['blockedGateIds']),
    ..._stringList(gate['blockers']),
  }.toList(growable: false);
  final ready =
      report['schemaName'] == 'macos_computer_use_m51_production_launch_gate' &&
      report['ready'] == true &&
      (review.isEmpty || review['status'] == 'ready_for_production_launch') &&
      blockers.isEmpty;
  return MacosComputerUseM52ProductReleaseGate(
    id: 'm51_production_launch_gate',
    label: 'M51 production launch gate',
    status: ready ? 'ready' : _statusValue(report, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M51 production launch evidence is ready.'
        : 'Resolve M51 production launch blockers before product release rollout.',
    userOperated: false,
    artifactPath: reportPath,
    details: <String, Object?>{
      'reviewStatus': review['status']?.toString(),
      'blockers': blockers,
      'readyGateIds': _stringList(report['readyGateIds']),
      'blockedGateIds': _stringList(report['blockedGateIds']),
    },
  );
}

MacosComputerUseM52ProductReleaseGate _checklistGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseM52ProductReleaseInputs inputs,
  required String nextAction,
}) {
  final checklist = inputs.productReleaseChecklist;
  if (checklist == null) {
    return MacosComputerUseM52ProductReleaseGate(
      id: id,
      label: label,
      status: 'missing',
      ready: false,
      nextAction:
          'Ask the user to complete the M52 product release checklist field `$field`.',
      userOperated: true,
    );
  }
  final section = _mapValue(checklist[field]);
  final blockers = _stringList(section['blockers']);
  final ready =
      checklist['schemaName'] ==
          'macos_computer_use_m52_product_release_checklist' &&
      (section['ready'] == true || section['status'] == 'ready') &&
      blockers.isEmpty;
  return MacosComputerUseM52ProductReleaseGate(
    id: id,
    label: label,
    status: ready ? 'ready' : _statusValue(section, fallback: 'blocked'),
    ready: ready,
    nextAction: ready ? '$label evidence is ready.' : nextAction,
    userOperated: true,
    artifactPath: inputs.productReleaseChecklistPath,
    details: <String, Object?>{
      'field': field,
      'evidence': section['evidence']?.toString(),
      'blockers': blockers,
    },
  );
}

Map<String, Object?> _readyTemplate(String evidence) {
  return <String, Object?>{
    'status': 'ready',
    'ready': true,
    'evidence': evidence,
  };
}

File? _latestJsonMatching(
  Directory reportRoot,
  bool Function(Map<String, dynamic> json) matches,
) {
  if (!reportRoot.existsSync()) {
    return null;
  }
  final files = reportRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .where((file) {
        final json = _readJsonObject(file);
        return json != null && matches(json);
      })
      .toList(growable: false);
  files.sort((left, right) {
    final modifiedCompare = left.statSync().modified.compareTo(
      right.statSync().modified,
    );
    if (modifiedCompare != 0) {
      return modifiedCompare;
    }
    return left.path.compareTo(right.path);
  });
  return files.isEmpty ? null : files.last;
}

Map<String, dynamic>? _readJsonObject(File? file) {
  if (file == null) {
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

Map<String, dynamic> _mapValue(Object? value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

String _statusValue(Map<String, dynamic> json, {required String fallback}) {
  final status = json['status'];
  return status is String && status.isNotEmpty ? status : fallback;
}

List<String> _stringList(Object? value) {
  return value is List
      ? value.map((item) => item.toString()).toList(growable: false)
      : const <String>[];
}

String _joinedOrNone(List<String> values) {
  return values.isEmpty ? 'none' : values.join(', ');
}

String _artifactCell(String? value) {
  if (value == null || value.isEmpty) {
    return 'missing';
  }
  return '`${_escapeMarkdownCode(_markdownCell(value))}`';
}

String _markdownCell(Object? value) {
  final text = value?.toString() ?? '';
  return text
      .replaceAll('\\', r'\\')
      .replaceAll('|', r'\|')
      .replaceAll('\r', ' ')
      .replaceAll('\n', '<br>');
}

String _escapeMarkdownCode(String value) {
  return value.replaceAll('`', r'\`');
}
