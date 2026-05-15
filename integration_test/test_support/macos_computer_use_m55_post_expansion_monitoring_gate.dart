import 'dart:convert';
import 'dart:io';

class MacosComputerUseM55PostExpansionMonitoringGate {
  const MacosComputerUseM55PostExpansionMonitoringGate({
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

class MacosComputerUseM55PostExpansionMonitoringSummary {
  const MacosComputerUseM55PostExpansionMonitoringSummary({
    required this.status,
    required this.ready,
    required this.rolloutContinuationDecision,
    required this.gates,
  });

  final String status;
  final bool ready;
  final String rolloutContinuationDecision;
  final List<MacosComputerUseM55PostExpansionMonitoringGate> gates;

  List<MacosComputerUseM55PostExpansionMonitoringGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  List<MacosComputerUseM55PostExpansionMonitoringGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<MacosComputerUseM55PostExpansionMonitoringGate> get userOperatedGates =>
      gates.where((gate) => gate.userOperated).toList(growable: false);

  Map<String, Object?> get postExpansionMonitoringSummary {
    final readyGateIds = readyGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedGateIds = blockedGates
        .map((gate) => gate.id)
        .toList(growable: false);
    return <String, Object?>{
      'status': ready
          ? 'ready_for_post_expansion_decision'
          : 'blocked_gates_present',
      'rolloutContinuationDecision': rolloutContinuationDecision,
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
          'M55 reads M54 rollout expansion evidence and post-expansion monitoring checklist evidence only; rollout continuation, cohort expansion, support, rollback, hotfix, TCC, and desktop actions remain user-operated.',
    };
  }

  Map<String, Object?> get m55PostExpansionMonitoringGate {
    return <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockedGates.map((gate) => gate.id).toList(growable: false),
      'rolloutContinuationDecision': rolloutContinuationDecision,
      'nextAction': ready
          ? _nextActionForDecision(rolloutContinuationDecision)
          : 'Resolve blocked M55 post-expansion monitoring gates before changing rollout state.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m55_post_expansion_monitoring_gate',
      'schemaVersion': 1,
      'milestone': 'M55',
      'automationBoundary': 'read_reports_only',
      'tccBoundary': 'user_operated',
      'desktopActionBoundary': 'user_operated',
      'status': status,
      'ready': ready,
      'rolloutContinuationDecision': rolloutContinuationDecision,
      'readyGateIds': readyGates.map((gate) => gate.id).toList(growable: false),
      'blockedGateIds': blockedGates
          .map((gate) => gate.id)
          .toList(growable: false),
      'userOperatedGateIds': userOperatedGates
          .map((gate) => gate.id)
          .toList(growable: false),
      'postExpansionMonitoringSummary': postExpansionMonitoringSummary,
      'm55PostExpansionMonitoringGate': m55PostExpansionMonitoringGate,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = postExpansionMonitoringSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M55 Post-Expansion Monitoring Gate')
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
      ..writeln('## Post-Expansion Monitoring Summary')
      ..writeln()
      ..writeln('- Status: ${review['status']}')
      ..writeln(
        '- Rollout continuation decision: ${review['rolloutContinuationDecision']}',
      )
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
      ..writeln('## Post-Expansion Monitoring Checklist Template')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(m55PostExpansionMonitoringChecklistTemplate()),
      )
      ..writeln('```');

    return buffer.toString();
  }
}

class MacosComputerUseM55PostExpansionMonitoringInputs {
  const MacosComputerUseM55PostExpansionMonitoringInputs({
    required this.postExpansionMonitoringChecklist,
    required this.postExpansionMonitoringChecklistPath,
    required this.m54RolloutExpansionGate,
    required this.m54RolloutExpansionGatePath,
  });

  final Map<String, dynamic>? postExpansionMonitoringChecklist;
  final String? postExpansionMonitoringChecklistPath;
  final Map<String, dynamic>? m54RolloutExpansionGate;
  final String? m54RolloutExpansionGatePath;
}

Map<String, Object?> m55PostExpansionMonitoringChecklistTemplate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m55_post_expansion_monitoring_checklist',
    'schemaVersion': 1,
    'milestone': 'M55',
    'automationBoundary': 'user_operated_post_expansion_monitoring_steps',
    'expansionScopeObserved': _readyTemplate(
      '<observed cohort, channel, percentage, and elapsed monitoring window>',
    ),
    'safetyMetricsReviewed': _readyTemplate(
      '<post-expansion safety, incident, complaint, and regression metrics review note>',
    ),
    'supportLoadReviewed': _readyTemplate(
      '<post-expansion support volume, response time, and escalation load review note>',
    ),
    'incidentComplaintReviewed': _readyTemplate(
      '<incident, complaint, regression, and user-impacting failure review note>',
    ),
    'rollbackPauseReviewed': _readyTemplate(
      '<rollback, rollout pause, disable path, hotfix, and emergency stop review note>',
    ),
    'continuationDecisionApproved': <String, Object?>{
      ..._readyTemplate(
        '<approved decision: continue_expansion, hold_current_cohort, pause_rollout, or rollback_recommended>',
      ),
      'decision': 'continue_expansion',
    },
    'ownerFollowupReviewed': _readyTemplate(
      '<rollout owner, support owner, follow-up action, and escalation handoff note>',
    ),
    'nextReviewScheduled': _readyTemplate(
      '<next monitoring review date and evidence owner>',
    ),
  };
}

MacosComputerUseM55PostExpansionMonitoringSummary
buildMacosComputerUseM55PostExpansionMonitoringSummary(
  MacosComputerUseM55PostExpansionMonitoringInputs inputs,
) {
  final gates = <MacosComputerUseM55PostExpansionMonitoringGate>[
    _m54RolloutExpansionGateGate(
      inputs.m54RolloutExpansionGate,
      inputs.m54RolloutExpansionGatePath,
    ),
    _checklistGate(
      id: 'expansion_scope_observed',
      label: 'Expansion scope observed',
      field: 'expansionScopeObserved',
      inputs: inputs,
      nextAction:
          'Ask the user to record the actual expanded cohort, channel, percentage, and monitoring window.',
    ),
    _checklistGate(
      id: 'safety_metrics_reviewed',
      label: 'Safety metrics review',
      field: 'safetyMetricsReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review post-expansion safety, incident, complaint, and regression metrics.',
    ),
    _checklistGate(
      id: 'support_load_reviewed',
      label: 'Support load review',
      field: 'supportLoadReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review support volume, response time, and escalation load after expansion.',
    ),
    _checklistGate(
      id: 'incident_complaint_reviewed',
      label: 'Incident and complaint review',
      field: 'incidentComplaintReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review incidents, complaints, regressions, and user-impacting failures.',
    ),
    _checklistGate(
      id: 'rollback_pause_reviewed',
      label: 'Rollback and pause review',
      field: 'rollbackPauseReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review rollback, rollout pause, disable path, hotfix, and emergency stop readiness.',
    ),
    _decisionGate(
      id: 'continuation_decision_approved',
      label: 'Continuation decision',
      field: 'continuationDecisionApproved',
      inputs: inputs,
      nextAction:
          'Ask the user to approve a continuation decision for the expanded rollout.',
    ),
    _checklistGate(
      id: 'owner_followup_reviewed',
      label: 'Owner and follow-up review',
      field: 'ownerFollowupReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm rollout owner, support owner, follow-up actions, and escalation handoff.',
    ),
    _checklistGate(
      id: 'next_review_scheduled',
      label: 'Next review scheduled',
      field: 'nextReviewScheduled',
      inputs: inputs,
      nextAction:
          'Ask the user to schedule the next monitoring review and evidence owner.',
    ),
  ];
  final ready = gates.every((gate) => gate.ready);
  return MacosComputerUseM55PostExpansionMonitoringSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    rolloutContinuationDecision: _rolloutContinuationDecision(inputs),
    gates: List<MacosComputerUseM55PostExpansionMonitoringGate>.unmodifiable(
      gates,
    ),
  );
}

MacosComputerUseM55PostExpansionMonitoringInputs
readMacosComputerUseM55PostExpansionMonitoringInputs({
  required Directory reportRoot,
  String? postExpansionMonitoringChecklistPath,
  String? m54RolloutExpansionGatePath,
}) {
  final checklistFile = postExpansionMonitoringChecklistPath == null
      ? discoverLatestM55PostExpansionMonitoringChecklist(reportRoot)
      : File(postExpansionMonitoringChecklistPath);
  final m54File = m54RolloutExpansionGatePath == null
      ? discoverLatestM54RolloutExpansionGate(reportRoot)
      : File(m54RolloutExpansionGatePath);
  return MacosComputerUseM55PostExpansionMonitoringInputs(
    postExpansionMonitoringChecklist: _readJsonObject(checklistFile),
    postExpansionMonitoringChecklistPath: checklistFile?.path,
    m54RolloutExpansionGate: _readJsonObject(m54File),
    m54RolloutExpansionGatePath: m54File?.path,
  );
}

File? discoverLatestM55PostExpansionMonitoringChecklist(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m55_post_expansion_monitoring_checklist';
  });
}

File? discoverLatestM54RolloutExpansionGate(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m54_rollout_expansion_gate';
  });
}

MacosComputerUseM55PostExpansionMonitoringGate _m54RolloutExpansionGateGate(
  Map<String, dynamic>? report,
  String? reportPath,
) {
  if (report == null) {
    return const MacosComputerUseM55PostExpansionMonitoringGate(
      id: 'm54_rollout_expansion_gate',
      label: 'M54 rollout expansion gate',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M54 rollout expansion gate before preparing the M55 post-expansion monitoring gate.',
      userOperated: false,
    );
  }
  final review = _mapValue(report['rolloutExpansionSummary']);
  final gate = _mapValue(report['m54RolloutExpansionGate']);
  final blockers = <String>{
    ..._stringList(report['blockedGateIds']),
    ..._stringList(review['blockedGateIds']),
    ..._stringList(gate['blockers']),
  }.toList(growable: false);
  final ready =
      report['schemaName'] == 'macos_computer_use_m54_rollout_expansion_gate' &&
      report['ready'] == true &&
      (review.isEmpty || review['status'] == 'ready_for_rollout_expansion') &&
      blockers.isEmpty;
  return MacosComputerUseM55PostExpansionMonitoringGate(
    id: 'm54_rollout_expansion_gate',
    label: 'M54 rollout expansion gate',
    status: ready ? 'ready' : _statusValue(report, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M54 rollout expansion evidence is ready.'
        : 'Resolve M54 rollout expansion blockers before M55 post-expansion monitoring.',
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

MacosComputerUseM55PostExpansionMonitoringGate _decisionGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseM55PostExpansionMonitoringInputs inputs,
  required String nextAction,
}) {
  final gate = _checklistGate(
    id: id,
    label: label,
    field: field,
    inputs: inputs,
    nextAction: nextAction,
  );
  final decision = _rolloutContinuationDecision(inputs);
  final allowed = _allowedRolloutContinuationDecisions.contains(decision);
  if (gate.ready && allowed) {
    return MacosComputerUseM55PostExpansionMonitoringGate(
      id: gate.id,
      label: gate.label,
      status: gate.status,
      ready: true,
      nextAction: '$label evidence is ready.',
      userOperated: gate.userOperated,
      artifactPath: gate.artifactPath,
      details: <String, Object?>{
        ...gate.details,
        'rolloutContinuationDecision': decision,
      },
    );
  }
  return MacosComputerUseM55PostExpansionMonitoringGate(
    id: gate.id,
    label: gate.label,
    status: gate.ready ? 'blocked' : gate.status,
    ready: false,
    nextAction: gate.ready
        ? 'Ask the user to choose continue_expansion, hold_current_cohort, pause_rollout, or rollback_recommended.'
        : gate.nextAction,
    userOperated: gate.userOperated,
    artifactPath: gate.artifactPath,
    details: <String, Object?>{
      ...gate.details,
      'rolloutContinuationDecision': decision,
    },
  );
}

MacosComputerUseM55PostExpansionMonitoringGate _checklistGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseM55PostExpansionMonitoringInputs inputs,
  required String nextAction,
}) {
  final checklist = inputs.postExpansionMonitoringChecklist;
  if (checklist == null) {
    return MacosComputerUseM55PostExpansionMonitoringGate(
      id: id,
      label: label,
      status: 'missing',
      ready: false,
      nextAction:
          'Ask the user to complete the M55 post-expansion monitoring checklist field `$field`.',
      userOperated: true,
    );
  }
  final section = _mapValue(checklist[field]);
  final blockers = _stringList(section['blockers']);
  final ready =
      checklist['schemaName'] ==
          'macos_computer_use_m55_post_expansion_monitoring_checklist' &&
      (section['ready'] == true || section['status'] == 'ready') &&
      blockers.isEmpty;
  return MacosComputerUseM55PostExpansionMonitoringGate(
    id: id,
    label: label,
    status: ready ? 'ready' : _statusValue(section, fallback: 'blocked'),
    ready: ready,
    nextAction: ready ? '$label evidence is ready.' : nextAction,
    userOperated: true,
    artifactPath: inputs.postExpansionMonitoringChecklistPath,
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
  MacosComputerUseM55PostExpansionMonitoringInputs inputs,
) {
  final checklist = inputs.postExpansionMonitoringChecklist;
  if (checklist == null) {
    return 'unknown';
  }
  final section = _mapValue(checklist['continuationDecisionApproved']);
  final decision = section['decision']?.toString() ?? '';
  return decision.isEmpty ? 'unknown' : decision;
}

String _nextActionForDecision(String decision) {
  switch (decision) {
    case 'continue_expansion':
      return 'Continue Computer Use rollout only within the approved monitoring cadence.';
    case 'hold_current_cohort':
      return 'Hold Computer Use at the current expanded cohort until the next review.';
    case 'pause_rollout':
      return 'Pause further Computer Use rollout expansion and keep monitoring active.';
    case 'rollback_recommended':
      return 'Start the user-operated rollback path and preserve post-expansion evidence.';
    default:
      return 'Review the approved post-expansion rollout decision before changing rollout state.';
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
