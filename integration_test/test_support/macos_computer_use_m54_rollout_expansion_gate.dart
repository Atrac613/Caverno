import 'dart:convert';
import 'dart:io';

class MacosComputerUseM54RolloutExpansionGate {
  const MacosComputerUseM54RolloutExpansionGate({
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

class MacosComputerUseM54RolloutExpansionSummary {
  const MacosComputerUseM54RolloutExpansionSummary({
    required this.status,
    required this.ready,
    required this.gates,
  });

  final String status;
  final bool ready;
  final List<MacosComputerUseM54RolloutExpansionGate> gates;

  List<MacosComputerUseM54RolloutExpansionGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  List<MacosComputerUseM54RolloutExpansionGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<MacosComputerUseM54RolloutExpansionGate> get userOperatedGates =>
      gates.where((gate) => gate.userOperated).toList(growable: false);

  Map<String, Object?> get rolloutExpansionSummary {
    final readyGateIds = readyGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedGateIds = blockedGates
        .map((gate) => gate.id)
        .toList(growable: false);
    return <String, Object?>{
      'status': ready ? 'ready_for_rollout_expansion' : 'blocked_gates_present',
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
          'M54 reads M53 post-release guardrail evidence and rollout expansion checklist evidence only; cohort expansion, support, rollback, hotfix, TCC, and desktop actions remain user-operated.',
    };
  }

  Map<String, Object?> get m54RolloutExpansionGate {
    return <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockedGates.map((gate) => gate.id).toList(growable: false),
      'nextAction': ready
          ? 'Expand Computer Use rollout only within the approved cohort and review cadence.'
          : 'Resolve blocked M54 rollout expansion gates before expanding rollout.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m54_rollout_expansion_gate',
      'schemaVersion': 1,
      'milestone': 'M54',
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
      'rolloutExpansionSummary': rolloutExpansionSummary,
      'm54RolloutExpansionGate': m54RolloutExpansionGate,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = rolloutExpansionSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M54 Rollout Expansion Gate')
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
      ..writeln('## Rollout Expansion Summary')
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
      ..writeln('## Rollout Expansion Checklist Template')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(m54RolloutExpansionChecklistTemplate()),
      )
      ..writeln('```');

    return buffer.toString();
  }
}

class MacosComputerUseM54RolloutExpansionInputs {
  const MacosComputerUseM54RolloutExpansionInputs({
    required this.rolloutExpansionChecklist,
    required this.rolloutExpansionChecklistPath,
    required this.m53PostReleaseGuardrails,
    required this.m53PostReleaseGuardrailsPath,
  });

  final Map<String, dynamic>? rolloutExpansionChecklist;
  final String? rolloutExpansionChecklistPath;
  final Map<String, dynamic>? m53PostReleaseGuardrails;
  final String? m53PostReleaseGuardrailsPath;
}

Map<String, Object?> m54RolloutExpansionChecklistTemplate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m54_rollout_expansion_checklist',
    'schemaVersion': 1,
    'milestone': 'M54',
    'automationBoundary': 'user_operated_rollout_expansion_steps',
    'expansionScopeApproved': _readyTemplate(
      '<approved cohort, channel, or percentage expansion scope>',
    ),
    'cohortRiskReviewed': _readyTemplate(
      '<cohort risk and excluded segment review note>',
    ),
    'supportCapacityReviewed': _readyTemplate(
      '<support capacity and escalation coverage review note>',
    ),
    'safetyMetricsReviewed': _readyTemplate(
      '<safety, incident, complaint, and regression metrics review note>',
    ),
    'rollbackPauseReady': _readyTemplate(
      '<rollback, rollout pause, disable path, and emergency stop readiness note>',
    ),
    'communicationsReviewed': _readyTemplate(
      '<release notes, support copy, and user communication review note>',
    ),
    'ownerEscalationReviewed': _readyTemplate(
      '<rollout owner, support owner, and escalation handoff note>',
    ),
    'nextReviewScheduled': _readyTemplate(
      '<next post-expansion review date and evidence owner>',
    ),
  };
}

MacosComputerUseM54RolloutExpansionSummary
buildMacosComputerUseM54RolloutExpansionSummary(
  MacosComputerUseM54RolloutExpansionInputs inputs,
) {
  final gates = <MacosComputerUseM54RolloutExpansionGate>[
    _m53PostReleaseGuardrailsGate(
      inputs.m53PostReleaseGuardrails,
      inputs.m53PostReleaseGuardrailsPath,
    ),
    _checklistGate(
      id: 'expansion_scope_approved',
      label: 'Expansion scope',
      field: 'expansionScopeApproved',
      inputs: inputs,
      nextAction:
          'Ask the user to approve the cohort, channel, or percentage expansion scope.',
    ),
    _checklistGate(
      id: 'cohort_risk_reviewed',
      label: 'Cohort risk review',
      field: 'cohortRiskReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review cohort risk and excluded rollout segments.',
    ),
    _checklistGate(
      id: 'support_capacity_reviewed',
      label: 'Support capacity',
      field: 'supportCapacityReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm support capacity and escalation coverage for the expanded cohort.',
    ),
    _checklistGate(
      id: 'safety_metrics_reviewed',
      label: 'Safety metrics',
      field: 'safetyMetricsReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review safety, incident, complaint, and regression metrics.',
    ),
    _checklistGate(
      id: 'rollback_pause_ready',
      label: 'Rollback and pause readiness',
      field: 'rollbackPauseReady',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm rollback, rollout pause, disable path, and emergency stop readiness.',
    ),
    _checklistGate(
      id: 'communications_reviewed',
      label: 'Communications review',
      field: 'communicationsReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review release notes, support copy, and user communication for the expanded cohort.',
    ),
    _checklistGate(
      id: 'owner_escalation_reviewed',
      label: 'Owner and escalation review',
      field: 'ownerEscalationReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm rollout owner, support owner, and escalation handoff.',
    ),
    _checklistGate(
      id: 'next_review_scheduled',
      label: 'Next review scheduled',
      field: 'nextReviewScheduled',
      inputs: inputs,
      nextAction:
          'Ask the user to schedule the next post-expansion review and evidence owner.',
    ),
  ];
  final ready = gates.every((gate) => gate.ready);
  return MacosComputerUseM54RolloutExpansionSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    gates: List<MacosComputerUseM54RolloutExpansionGate>.unmodifiable(gates),
  );
}

MacosComputerUseM54RolloutExpansionInputs
readMacosComputerUseM54RolloutExpansionInputs({
  required Directory reportRoot,
  String? rolloutExpansionChecklistPath,
  String? m53PostReleaseGuardrailsPath,
}) {
  final checklistFile = rolloutExpansionChecklistPath == null
      ? discoverLatestM54RolloutExpansionChecklist(reportRoot)
      : File(rolloutExpansionChecklistPath);
  final m53File = m53PostReleaseGuardrailsPath == null
      ? discoverLatestM53PostReleaseGuardrails(reportRoot)
      : File(m53PostReleaseGuardrailsPath);
  return MacosComputerUseM54RolloutExpansionInputs(
    rolloutExpansionChecklist: _readJsonObject(checklistFile),
    rolloutExpansionChecklistPath: checklistFile?.path,
    m53PostReleaseGuardrails: _readJsonObject(m53File),
    m53PostReleaseGuardrailsPath: m53File?.path,
  );
}

File? discoverLatestM54RolloutExpansionChecklist(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m54_rollout_expansion_checklist';
  });
}

File? discoverLatestM53PostReleaseGuardrails(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m53_post_release_guardrails';
  });
}

MacosComputerUseM54RolloutExpansionGate _m53PostReleaseGuardrailsGate(
  Map<String, dynamic>? report,
  String? reportPath,
) {
  if (report == null) {
    return const MacosComputerUseM54RolloutExpansionGate(
      id: 'm53_post_release_guardrails',
      label: 'M53 post-release guardrails',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M53 post-release guardrails before preparing the M54 rollout expansion gate.',
      userOperated: false,
    );
  }
  final review = _mapValue(report['postReleaseGuardrailsSummary']);
  final gate = _mapValue(report['m53PostReleaseGuardrailsGate']);
  final blockers = <String>{
    ..._stringList(report['blockedGateIds']),
    ..._stringList(review['blockedGateIds']),
    ..._stringList(gate['blockers']),
  }.toList(growable: false);
  final ready =
      report['schemaName'] ==
          'macos_computer_use_m53_post_release_guardrails' &&
      report['ready'] == true &&
      (review.isEmpty ||
          review['status'] == 'ready_for_post_release_operations') &&
      blockers.isEmpty;
  return MacosComputerUseM54RolloutExpansionGate(
    id: 'm53_post_release_guardrails',
    label: 'M53 post-release guardrails',
    status: ready ? 'ready' : _statusValue(report, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M53 post-release guardrail evidence is ready.'
        : 'Resolve M53 post-release guardrail blockers before M54 rollout expansion.',
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

MacosComputerUseM54RolloutExpansionGate _checklistGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseM54RolloutExpansionInputs inputs,
  required String nextAction,
}) {
  final checklist = inputs.rolloutExpansionChecklist;
  if (checklist == null) {
    return MacosComputerUseM54RolloutExpansionGate(
      id: id,
      label: label,
      status: 'missing',
      ready: false,
      nextAction:
          'Ask the user to complete the M54 rollout expansion checklist field `$field`.',
      userOperated: true,
    );
  }
  final section = _mapValue(checklist[field]);
  final blockers = _stringList(section['blockers']);
  final ready =
      checklist['schemaName'] ==
          'macos_computer_use_m54_rollout_expansion_checklist' &&
      (section['ready'] == true || section['status'] == 'ready') &&
      blockers.isEmpty;
  return MacosComputerUseM54RolloutExpansionGate(
    id: id,
    label: label,
    status: ready ? 'ready' : _statusValue(section, fallback: 'blocked'),
    ready: ready,
    nextAction: ready ? '$label evidence is ready.' : nextAction,
    userOperated: true,
    artifactPath: inputs.rolloutExpansionChecklistPath,
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
