import 'dart:convert';
import 'dart:io';

class MacosComputerUseM56RolloutDecisionHandoffGate {
  const MacosComputerUseM56RolloutDecisionHandoffGate({
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

class MacosComputerUseM56RolloutDecisionHandoffSummary {
  const MacosComputerUseM56RolloutDecisionHandoffSummary({
    required this.status,
    required this.ready,
    required this.rolloutContinuationDecision,
    required this.decisionHandoffType,
    required this.gates,
  });

  final String status;
  final bool ready;
  final String rolloutContinuationDecision;
  final String decisionHandoffType;
  final List<MacosComputerUseM56RolloutDecisionHandoffGate> gates;

  List<MacosComputerUseM56RolloutDecisionHandoffGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  List<MacosComputerUseM56RolloutDecisionHandoffGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<MacosComputerUseM56RolloutDecisionHandoffGate> get userOperatedGates =>
      gates.where((gate) => gate.userOperated).toList(growable: false);

  Map<String, Object?> get rolloutDecisionHandoffSummary {
    final readyGateIds = readyGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedGateIds = blockedGates
        .map((gate) => gate.id)
        .toList(growable: false);
    return <String, Object?>{
      'status': ready
          ? 'ready_for_rollout_decision_handoff'
          : 'blocked_gates_present',
      'rolloutContinuationDecision': rolloutContinuationDecision,
      'decisionHandoffType': decisionHandoffType,
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
          'M56 reads M55 post-expansion monitoring evidence and rollout decision handoff checklist evidence only; next-cycle seeding, hold scheduling, pause, rollback, TCC, and desktop actions remain user-operated.',
    };
  }

  Map<String, Object?> get m56RolloutDecisionHandoffGate {
    return <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockedGates.map((gate) => gate.id).toList(growable: false),
      'rolloutContinuationDecision': rolloutContinuationDecision,
      'decisionHandoffType': decisionHandoffType,
      'nextAction': ready
          ? _nextActionForHandoff(decisionHandoffType)
          : 'Resolve blocked M56 rollout decision handoff gates before changing rollout state.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m56_rollout_decision_handoff_gate',
      'schemaVersion': 1,
      'milestone': 'M56',
      'automationBoundary': 'read_reports_only',
      'tccBoundary': 'user_operated',
      'desktopActionBoundary': 'user_operated',
      'status': status,
      'ready': ready,
      'rolloutContinuationDecision': rolloutContinuationDecision,
      'decisionHandoffType': decisionHandoffType,
      'readyGateIds': readyGates.map((gate) => gate.id).toList(growable: false),
      'blockedGateIds': blockedGates
          .map((gate) => gate.id)
          .toList(growable: false),
      'userOperatedGateIds': userOperatedGates
          .map((gate) => gate.id)
          .toList(growable: false),
      'rolloutDecisionHandoffSummary': rolloutDecisionHandoffSummary,
      'm56RolloutDecisionHandoffGate': m56RolloutDecisionHandoffGate,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = rolloutDecisionHandoffSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M56 Rollout Decision Handoff Gate')
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
      ..writeln('## Rollout Decision Handoff Summary')
      ..writeln()
      ..writeln('- Status: ${review['status']}')
      ..writeln(
        '- Rollout continuation decision: ${review['rolloutContinuationDecision']}',
      )
      ..writeln('- Decision handoff type: ${review['decisionHandoffType']}')
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
      ..writeln('## Rollout Decision Handoff Checklist Template')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(m56RolloutDecisionHandoffChecklistTemplate()),
      )
      ..writeln('```');

    return buffer.toString();
  }
}

class MacosComputerUseM56RolloutDecisionHandoffInputs {
  const MacosComputerUseM56RolloutDecisionHandoffInputs({
    required this.rolloutDecisionHandoffChecklist,
    required this.rolloutDecisionHandoffChecklistPath,
    required this.m55PostExpansionMonitoringGate,
    required this.m55PostExpansionMonitoringGatePath,
  });

  final Map<String, dynamic>? rolloutDecisionHandoffChecklist;
  final String? rolloutDecisionHandoffChecklistPath;
  final Map<String, dynamic>? m55PostExpansionMonitoringGate;
  final String? m55PostExpansionMonitoringGatePath;
}

Map<String, Object?> m56RolloutDecisionHandoffChecklistTemplate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m56_rollout_decision_handoff_checklist',
    'schemaVersion': 1,
    'milestone': 'M56',
    'automationBoundary': 'user_operated_rollout_decision_handoff_steps',
    'decisionScopeConfirmed': _readyTemplate(
      '<M55 decision scope, affected cohort, and evidence window>',
    ),
    'decisionBranchHandoff': <String, Object?>{
      ..._readyTemplate('<handoff plan matching the M55 decision>'),
      'decision': 'continue_expansion',
      'handoffType': 'next_expansion_cycle_seed',
    },
    'handoffOwnerConfirmed': _readyTemplate(
      '<owner for the next user-operated rollout action>',
    ),
    'evidenceArchiveReady': _readyTemplate(
      '<M55 evidence archive and links for review>',
    ),
    'userCommunicationReviewed': _readyTemplate(
      '<user, support, release note, or internal communication review>',
    ),
    'riskControlsConfirmed': _readyTemplate(
      '<branch-specific risk controls, rollback, pause, or monitoring note>',
    ),
    'nextReviewScheduled': _readyTemplate(
      '<next review, follow-up, or completion checkpoint>',
    ),
  };
}

MacosComputerUseM56RolloutDecisionHandoffSummary
buildMacosComputerUseM56RolloutDecisionHandoffSummary(
  MacosComputerUseM56RolloutDecisionHandoffInputs inputs,
) {
  final gates = <MacosComputerUseM56RolloutDecisionHandoffGate>[
    _m55PostExpansionMonitoringGateGate(
      inputs.m55PostExpansionMonitoringGate,
      inputs.m55PostExpansionMonitoringGatePath,
    ),
    _checklistGate(
      id: 'decision_scope_confirmed',
      label: 'Decision scope',
      field: 'decisionScopeConfirmed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm the M55 decision scope, affected cohort, and evidence window.',
    ),
    _decisionHandoffGate(
      id: 'decision_branch_handoff',
      label: 'Decision branch handoff',
      field: 'decisionBranchHandoff',
      inputs: inputs,
      nextAction:
          'Ask the user to provide a branch handoff that matches the M55 rollout decision.',
    ),
    _checklistGate(
      id: 'handoff_owner_confirmed',
      label: 'Handoff owner',
      field: 'handoffOwnerConfirmed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm the owner for the next user-operated rollout action.',
    ),
    _checklistGate(
      id: 'evidence_archive_ready',
      label: 'Evidence archive',
      field: 'evidenceArchiveReady',
      inputs: inputs,
      nextAction:
          'Ask the user to archive the M55 evidence and links required for the handoff.',
    ),
    _checklistGate(
      id: 'user_communication_reviewed',
      label: 'Communication review',
      field: 'userCommunicationReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review user, support, release note, or internal communication for the decision branch.',
    ),
    _checklistGate(
      id: 'risk_controls_confirmed',
      label: 'Risk controls',
      field: 'riskControlsConfirmed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm branch-specific risk controls before changing rollout state.',
    ),
    _checklistGate(
      id: 'next_review_scheduled',
      label: 'Next review scheduled',
      field: 'nextReviewScheduled',
      inputs: inputs,
      nextAction:
          'Ask the user to schedule the next review, follow-up, or completion checkpoint.',
    ),
  ];
  final ready = gates.every((gate) => gate.ready);
  return MacosComputerUseM56RolloutDecisionHandoffSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    rolloutContinuationDecision: _rolloutContinuationDecision(inputs),
    decisionHandoffType: _decisionHandoffType(inputs),
    gates: List<MacosComputerUseM56RolloutDecisionHandoffGate>.unmodifiable(
      gates,
    ),
  );
}

MacosComputerUseM56RolloutDecisionHandoffInputs
readMacosComputerUseM56RolloutDecisionHandoffInputs({
  required Directory reportRoot,
  String? rolloutDecisionHandoffChecklistPath,
  String? m55PostExpansionMonitoringGatePath,
}) {
  final checklistFile = rolloutDecisionHandoffChecklistPath == null
      ? discoverLatestM56RolloutDecisionHandoffChecklist(reportRoot)
      : File(rolloutDecisionHandoffChecklistPath);
  final m55File = m55PostExpansionMonitoringGatePath == null
      ? discoverLatestM55PostExpansionMonitoringGate(reportRoot)
      : File(m55PostExpansionMonitoringGatePath);
  return MacosComputerUseM56RolloutDecisionHandoffInputs(
    rolloutDecisionHandoffChecklist: _readJsonObject(checklistFile),
    rolloutDecisionHandoffChecklistPath: checklistFile?.path,
    m55PostExpansionMonitoringGate: _readJsonObject(m55File),
    m55PostExpansionMonitoringGatePath: m55File?.path,
  );
}

File? discoverLatestM56RolloutDecisionHandoffChecklist(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m56_rollout_decision_handoff_checklist';
  });
}

File? discoverLatestM55PostExpansionMonitoringGate(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m55_post_expansion_monitoring_gate';
  });
}

MacosComputerUseM56RolloutDecisionHandoffGate
_m55PostExpansionMonitoringGateGate(
  Map<String, dynamic>? report,
  String? reportPath,
) {
  if (report == null) {
    return const MacosComputerUseM56RolloutDecisionHandoffGate(
      id: 'm55_post_expansion_monitoring_gate',
      label: 'M55 post-expansion monitoring gate',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M55 post-expansion monitoring gate before preparing the M56 rollout decision handoff gate.',
      userOperated: false,
    );
  }
  final review = _mapValue(report['postExpansionMonitoringSummary']);
  final gate = _mapValue(report['m55PostExpansionMonitoringGate']);
  final blockers = <String>{
    ..._stringList(report['blockedGateIds']),
    ..._stringList(review['blockedGateIds']),
    ..._stringList(gate['blockers']),
  }.toList(growable: false);
  final ready =
      report['schemaName'] ==
          'macos_computer_use_m55_post_expansion_monitoring_gate' &&
      report['ready'] == true &&
      (review.isEmpty ||
          review['status'] == 'ready_for_post_expansion_decision') &&
      blockers.isEmpty &&
      _allowedRolloutContinuationDecisions.contains(
        _decisionFromM55Report(report),
      );
  return MacosComputerUseM56RolloutDecisionHandoffGate(
    id: 'm55_post_expansion_monitoring_gate',
    label: 'M55 post-expansion monitoring gate',
    status: ready ? 'ready' : _statusValue(report, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M55 post-expansion monitoring evidence is ready.'
        : 'Resolve M55 post-expansion monitoring blockers before M56 rollout decision handoff.',
    userOperated: false,
    artifactPath: reportPath,
    details: <String, Object?>{
      'reviewStatus': review['status']?.toString(),
      'rolloutContinuationDecision': _decisionFromM55Report(report),
      'blockers': blockers,
      'readyGateIds': _stringList(report['readyGateIds']),
      'blockedGateIds': _stringList(report['blockedGateIds']),
    },
  );
}

MacosComputerUseM56RolloutDecisionHandoffGate _decisionHandoffGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseM56RolloutDecisionHandoffInputs inputs,
  required String nextAction,
}) {
  final gate = _checklistGate(
    id: id,
    label: label,
    field: field,
    inputs: inputs,
    nextAction: nextAction,
  );
  final sourceDecision = _sourceRolloutContinuationDecision(inputs);
  final handoffDecision = _rolloutContinuationDecision(inputs);
  final handoffType = _decisionHandoffType(inputs);
  final expectedHandoffType = _expectedHandoffType(sourceDecision);
  final ready =
      gate.ready &&
      _allowedRolloutContinuationDecisions.contains(sourceDecision) &&
      sourceDecision == handoffDecision &&
      expectedHandoffType == handoffType;
  if (ready) {
    return MacosComputerUseM56RolloutDecisionHandoffGate(
      id: gate.id,
      label: gate.label,
      status: gate.status,
      ready: true,
      nextAction: '$label evidence is ready.',
      userOperated: gate.userOperated,
      artifactPath: gate.artifactPath,
      details: <String, Object?>{
        ...gate.details,
        'sourceRolloutContinuationDecision': sourceDecision,
        'rolloutContinuationDecision': handoffDecision,
        'decisionHandoffType': handoffType,
        'expectedDecisionHandoffType': expectedHandoffType,
      },
    );
  }
  return MacosComputerUseM56RolloutDecisionHandoffGate(
    id: gate.id,
    label: gate.label,
    status: gate.ready ? 'blocked' : gate.status,
    ready: false,
    nextAction: gate.ready
        ? 'Ask the user to provide a decision and handoff type that match the ready M55 decision.'
        : gate.nextAction,
    userOperated: gate.userOperated,
    artifactPath: gate.artifactPath,
    details: <String, Object?>{
      ...gate.details,
      'sourceRolloutContinuationDecision': sourceDecision,
      'rolloutContinuationDecision': handoffDecision,
      'decisionHandoffType': handoffType,
      'expectedDecisionHandoffType': expectedHandoffType,
    },
  );
}

MacosComputerUseM56RolloutDecisionHandoffGate _checklistGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseM56RolloutDecisionHandoffInputs inputs,
  required String nextAction,
}) {
  final checklist = inputs.rolloutDecisionHandoffChecklist;
  if (checklist == null) {
    return MacosComputerUseM56RolloutDecisionHandoffGate(
      id: id,
      label: label,
      status: 'missing',
      ready: false,
      nextAction:
          'Ask the user to complete the M56 rollout decision handoff checklist field `$field`.',
      userOperated: true,
    );
  }
  final section = _mapValue(checklist[field]);
  final blockers = _stringList(section['blockers']);
  final ready =
      checklist['schemaName'] ==
          'macos_computer_use_m56_rollout_decision_handoff_checklist' &&
      (section['ready'] == true || section['status'] == 'ready') &&
      blockers.isEmpty;
  return MacosComputerUseM56RolloutDecisionHandoffGate(
    id: id,
    label: label,
    status: ready ? 'ready' : _statusValue(section, fallback: 'blocked'),
    ready: ready,
    nextAction: ready ? '$label evidence is ready.' : nextAction,
    userOperated: true,
    artifactPath: inputs.rolloutDecisionHandoffChecklistPath,
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

const _allowedRolloutContinuationDecisions = <String>{
  'continue_expansion',
  'hold_current_cohort',
  'pause_rollout',
  'rollback_recommended',
};

String _rolloutContinuationDecision(
  MacosComputerUseM56RolloutDecisionHandoffInputs inputs,
) {
  final checklist = inputs.rolloutDecisionHandoffChecklist;
  if (checklist == null) {
    return 'unknown';
  }
  final section = _mapValue(checklist['decisionBranchHandoff']);
  final decision = section['decision']?.toString() ?? '';
  return decision.isEmpty ? 'unknown' : decision;
}

String _sourceRolloutContinuationDecision(
  MacosComputerUseM56RolloutDecisionHandoffInputs inputs,
) {
  final report = inputs.m55PostExpansionMonitoringGate;
  if (report == null) {
    return 'unknown';
  }
  return _decisionFromM55Report(report);
}

String _decisionFromM55Report(Map<String, dynamic> report) {
  final topLevelDecision = report['rolloutContinuationDecision']?.toString();
  if (topLevelDecision != null && topLevelDecision.isNotEmpty) {
    return topLevelDecision;
  }
  final review = _mapValue(report['postExpansionMonitoringSummary']);
  final reviewDecision = review['rolloutContinuationDecision']?.toString();
  if (reviewDecision != null && reviewDecision.isNotEmpty) {
    return reviewDecision;
  }
  final gate = _mapValue(report['m55PostExpansionMonitoringGate']);
  final gateDecision = gate['rolloutContinuationDecision']?.toString();
  return gateDecision == null || gateDecision.isEmpty
      ? 'unknown'
      : gateDecision;
}

String _decisionHandoffType(
  MacosComputerUseM56RolloutDecisionHandoffInputs inputs,
) {
  final checklist = inputs.rolloutDecisionHandoffChecklist;
  if (checklist == null) {
    return 'unknown';
  }
  final section = _mapValue(checklist['decisionBranchHandoff']);
  final handoffType = section['handoffType']?.toString() ?? '';
  return handoffType.isEmpty ? 'unknown' : handoffType;
}

String _expectedHandoffType(String decision) {
  switch (decision) {
    case 'continue_expansion':
      return 'next_expansion_cycle_seed';
    case 'hold_current_cohort':
      return 'monitoring_cadence_hold';
    case 'pause_rollout':
      return 'rollout_pause_handoff';
    case 'rollback_recommended':
      return 'rollback_handoff';
    default:
      return 'unknown';
  }
}

String _nextActionForHandoff(String handoffType) {
  switch (handoffType) {
    case 'next_expansion_cycle_seed':
      return 'Prepare the next user-operated M54 rollout expansion cycle seed.';
    case 'monitoring_cadence_hold':
      return 'Hold the current cohort and keep the scheduled M55 monitoring cadence.';
    case 'rollout_pause_handoff':
      return 'Hand off the user-operated rollout pause path and preserve evidence.';
    case 'rollback_handoff':
      return 'Hand off the user-operated rollback path and preserve evidence.';
    default:
      return 'Review the approved rollout decision handoff before changing rollout state.';
  }
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
