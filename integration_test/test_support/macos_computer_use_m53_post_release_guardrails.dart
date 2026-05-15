import 'dart:convert';
import 'dart:io';

class MacosComputerUseM53PostReleaseGate {
  const MacosComputerUseM53PostReleaseGate({
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

class MacosComputerUseM53PostReleaseSummary {
  const MacosComputerUseM53PostReleaseSummary({
    required this.status,
    required this.ready,
    required this.gates,
  });

  final String status;
  final bool ready;
  final List<MacosComputerUseM53PostReleaseGate> gates;

  List<MacosComputerUseM53PostReleaseGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  List<MacosComputerUseM53PostReleaseGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<MacosComputerUseM53PostReleaseGate> get userOperatedGates =>
      gates.where((gate) => gate.userOperated).toList(growable: false);

  Map<String, Object?> get postReleaseGuardrailsSummary {
    final readyGateIds = readyGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedGateIds = blockedGates
        .map((gate) => gate.id)
        .toList(growable: false);
    return <String, Object?>{
      'status': ready
          ? 'ready_for_post_release_operations'
          : 'blocked_gates_present',
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
          'M53 reads M52 rollout evidence and post-release checklist evidence only; monitoring, support diagnostics, rollback, hotfix, TCC, and desktop actions remain user-operated.',
    };
  }

  Map<String, Object?> get m53PostReleaseGuardrailsGate {
    return <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockedGates.map((gate) => gate.id).toList(growable: false),
      'nextAction': ready
          ? 'Keep Computer Use post-release guardrails on the scheduled review cadence.'
          : 'Resolve blocked M53 post-release guardrail gates before continuing rollout expansion.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m53_post_release_guardrails',
      'schemaVersion': 1,
      'milestone': 'M53',
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
      'postReleaseGuardrailsSummary': postReleaseGuardrailsSummary,
      'm53PostReleaseGuardrailsGate': m53PostReleaseGuardrailsGate,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = postReleaseGuardrailsSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M53 Post-Release Guardrails')
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
      ..writeln('## Post-Release Guardrails Summary')
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
      ..writeln('## Post-Release Checklist Template')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(m53PostReleaseChecklistTemplate()),
      )
      ..writeln('```');

    return buffer.toString();
  }
}

class MacosComputerUseM53PostReleaseInputs {
  const MacosComputerUseM53PostReleaseInputs({
    required this.postReleaseChecklist,
    required this.postReleaseChecklistPath,
    required this.m52ProductReleaseRollout,
    required this.m52ProductReleaseRolloutPath,
  });

  final Map<String, dynamic>? postReleaseChecklist;
  final String? postReleaseChecklistPath;
  final Map<String, dynamic>? m52ProductReleaseRollout;
  final String? m52ProductReleaseRolloutPath;
}

Map<String, Object?> m53PostReleaseChecklistTemplate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m53_post_release_checklist',
    'schemaVersion': 1,
    'milestone': 'M53',
    'automationBoundary': 'user_operated_post_release_steps',
    'reviewCadenceConfirmed': _readyTemplate(
      '<scheduled post-release review cadence sign-off note>',
    ),
    'defaultOffStillConfirmed': _readyTemplate(
      '<Computer Use remains default off after release>',
    ),
    'advancedOnlyStillConfirmed': _readyTemplate(
      '<Settings > Advanced remains the only enablement path>',
    ),
    'supportDiagnosticsReviewed': _readyTemplate(
      '<redacted support diagnostics review note>',
    ),
    'knownIssuesReviewed': _readyTemplate('<known issues review note>'),
    'incidentReviewComplete': _readyTemplate(
      '<incident, complaint, and regression review note>',
    ),
    'rollbackStillReady': _readyTemplate(
      '<rollback and disable path readiness note>',
    ),
    'hotfixTriggersReviewed': _readyTemplate(
      '<hotfix, rollout pause, and escalation trigger note>',
    ),
  };
}

MacosComputerUseM53PostReleaseSummary
buildMacosComputerUseM53PostReleaseSummary(
  MacosComputerUseM53PostReleaseInputs inputs,
) {
  final gates = <MacosComputerUseM53PostReleaseGate>[
    _m52ProductReleaseRolloutGate(
      inputs.m52ProductReleaseRollout,
      inputs.m52ProductReleaseRolloutPath,
    ),
    _checklistGate(
      id: 'review_cadence_confirmed',
      label: 'Review cadence',
      field: 'reviewCadenceConfirmed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm the scheduled post-release review cadence.',
    ),
    _checklistGate(
      id: 'default_off_still_confirmed',
      label: 'Default-off state',
      field: 'defaultOffStillConfirmed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm Computer Use remains default off after release.',
    ),
    _checklistGate(
      id: 'advanced_only_still_confirmed',
      label: 'Advanced-only enablement',
      field: 'advancedOnlyStillConfirmed',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm Settings > Advanced remains the only enablement path.',
    ),
    _checklistGate(
      id: 'support_diagnostics_reviewed',
      label: 'Support diagnostics review',
      field: 'supportDiagnosticsReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review redacted support diagnostics before continuing rollout expansion.',
    ),
    _checklistGate(
      id: 'known_issues_reviewed',
      label: 'Known issues review',
      field: 'knownIssuesReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review known issues and unresolved support reports.',
    ),
    _checklistGate(
      id: 'incident_review_complete',
      label: 'Incident review',
      field: 'incidentReviewComplete',
      inputs: inputs,
      nextAction:
          'Ask the user to review incidents, complaints, regressions, and user-impacting failures.',
    ),
    _checklistGate(
      id: 'rollback_still_ready',
      label: 'Rollback readiness',
      field: 'rollbackStillReady',
      inputs: inputs,
      nextAction:
          'Ask the user to confirm rollback, disable path, and emergency stop readiness.',
    ),
    _checklistGate(
      id: 'hotfix_triggers_reviewed',
      label: 'Hotfix triggers',
      field: 'hotfixTriggersReviewed',
      inputs: inputs,
      nextAction:
          'Ask the user to review hotfix, rollout pause, and escalation triggers.',
    ),
  ];
  final ready = gates.every((gate) => gate.ready);
  return MacosComputerUseM53PostReleaseSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    gates: List<MacosComputerUseM53PostReleaseGate>.unmodifiable(gates),
  );
}

MacosComputerUseM53PostReleaseInputs readMacosComputerUseM53PostReleaseInputs({
  required Directory reportRoot,
  String? postReleaseChecklistPath,
  String? m52ProductReleaseRolloutPath,
}) {
  final checklistFile = postReleaseChecklistPath == null
      ? discoverLatestM53PostReleaseChecklist(reportRoot)
      : File(postReleaseChecklistPath);
  final m52File = m52ProductReleaseRolloutPath == null
      ? discoverLatestM52ProductReleaseRollout(reportRoot)
      : File(m52ProductReleaseRolloutPath);
  return MacosComputerUseM53PostReleaseInputs(
    postReleaseChecklist: _readJsonObject(checklistFile),
    postReleaseChecklistPath: checklistFile?.path,
    m52ProductReleaseRollout: _readJsonObject(m52File),
    m52ProductReleaseRolloutPath: m52File?.path,
  );
}

File? discoverLatestM53PostReleaseChecklist(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m53_post_release_checklist';
  });
}

File? discoverLatestM52ProductReleaseRollout(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m52_product_release_rollout';
  });
}

MacosComputerUseM53PostReleaseGate _m52ProductReleaseRolloutGate(
  Map<String, dynamic>? report,
  String? reportPath,
) {
  if (report == null) {
    return const MacosComputerUseM53PostReleaseGate(
      id: 'm52_product_release_rollout',
      label: 'M52 product release rollout',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M52 product release rollout before preparing M53 post-release guardrails.',
      userOperated: false,
    );
  }
  final review = _mapValue(report['releaseRolloutSummary']);
  final gate = _mapValue(report['m52ProductReleaseGate']);
  final blockers = <String>{
    ..._stringList(report['blockedGateIds']),
    ..._stringList(review['blockedGateIds']),
    ..._stringList(gate['blockers']),
  }.toList(growable: false);
  final ready =
      report['schemaName'] ==
          'macos_computer_use_m52_product_release_rollout' &&
      report['ready'] == true &&
      (review.isEmpty || review['status'] == 'ready_for_product_release') &&
      blockers.isEmpty;
  return MacosComputerUseM53PostReleaseGate(
    id: 'm52_product_release_rollout',
    label: 'M52 product release rollout',
    status: ready ? 'ready' : _statusValue(report, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M52 product release evidence is ready.'
        : 'Resolve M52 product release rollout blockers before M53 post-release guardrails.',
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

MacosComputerUseM53PostReleaseGate _checklistGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseM53PostReleaseInputs inputs,
  required String nextAction,
}) {
  final checklist = inputs.postReleaseChecklist;
  if (checklist == null) {
    return MacosComputerUseM53PostReleaseGate(
      id: id,
      label: label,
      status: 'missing',
      ready: false,
      nextAction:
          'Ask the user to complete the M53 post-release checklist field `$field`.',
      userOperated: true,
    );
  }
  final section = _mapValue(checklist[field]);
  final blockers = _stringList(section['blockers']);
  final ready =
      checklist['schemaName'] ==
          'macos_computer_use_m53_post_release_checklist' &&
      (section['ready'] == true || section['status'] == 'ready') &&
      blockers.isEmpty;
  return MacosComputerUseM53PostReleaseGate(
    id: id,
    label: label,
    status: ready ? 'ready' : _statusValue(section, fallback: 'blocked'),
    ready: ready,
    nextAction: ready ? '$label evidence is ready.' : nextAction,
    userOperated: true,
    artifactPath: inputs.postReleaseChecklistPath,
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
