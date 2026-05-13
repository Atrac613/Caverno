import 'dart:convert';
import 'dart:io';

class MacosComputerUseBetaSignoffGate {
  const MacosComputerUseBetaSignoffGate({
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

class MacosComputerUseBetaSignoffSummary {
  const MacosComputerUseBetaSignoffSummary({
    required this.status,
    required this.ready,
    required this.gates,
  });

  final String status;
  final bool ready;
  final List<MacosComputerUseBetaSignoffGate> gates;

  List<MacosComputerUseBetaSignoffGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  List<MacosComputerUseBetaSignoffGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<MacosComputerUseBetaSignoffGate> get userOperatedGates =>
      gates.where((gate) => gate.userOperated).toList(growable: false);

  Map<String, Object?> get betaReviewSummary {
    final readyGateIds = readyGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedGateIds = blockedGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedUserOperatedGateIds = blockedGates
        .where((gate) => gate.userOperated)
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedAutomationSafeGateIds = blockedGates
        .where((gate) => !gate.userOperated)
        .map((gate) => gate.id)
        .toList(growable: false);
    return <String, Object?>{
      'status': ready ? 'ready_for_internal_beta' : 'blocked_gates_present',
      'readyGateIds': readyGateIds,
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedUserOperatedGateIds,
      'blockedAutomationSafeGateIds': blockedAutomationSafeGateIds,
      'operationBoundarySummary':
          'M39 reads existing reports and manual checklist evidence only; TCC grants and desktop actions remain user-operated.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m39_beta_signoff',
      'schemaVersion': 1,
      'milestone': 'M39',
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
      'betaReviewSummary': betaReviewSummary,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = betaReviewSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M39 Internal Beta Sign-Off')
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
      ..writeln('## Beta Review Summary')
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
      ..writeln('## Manual Checklist Template')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent('  ').convert(manualChecklistTemplate()),
      )
      ..writeln('```');

    return buffer.toString();
  }
}

class MacosComputerUseBetaSignoffInputs {
  const MacosComputerUseBetaSignoffInputs({
    required this.manualChecklist,
    required this.manualChecklistPath,
    required this.m36LiveLlmEvalSummary,
    required this.m36LiveLlmEvalSummaryPath,
    required this.m23CycleOutcomeHandoff,
    required this.m23CycleOutcomeHandoffPath,
    required this.installMigrationDiagnostics,
    required this.installMigrationDiagnosticsPath,
  });

  final Map<String, dynamic>? manualChecklist;
  final String? manualChecklistPath;
  final Map<String, dynamic>? m36LiveLlmEvalSummary;
  final String? m36LiveLlmEvalSummaryPath;
  final Map<String, dynamic>? m23CycleOutcomeHandoff;
  final String? m23CycleOutcomeHandoffPath;
  final Map<String, dynamic>? installMigrationDiagnostics;
  final String? installMigrationDiagnosticsPath;
}

Map<String, Object?> manualChecklistTemplate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m39_manual_beta_checklist',
    'schemaVersion': 1,
    'milestone': 'M39',
    'automationBoundary': 'user_operated_runtime_checks',
    'cleanInstall': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': '<clean install note or artifact path>',
    },
    'upgradeMigration': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': '<upgrade and migration note or artifact path>',
    },
    'permissionGrant': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': '<permission grant note or artifact path>',
    },
    'permissionRevocation': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': '<permission revocation recovery note or artifact path>',
    },
    'helperRestart': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': '<helper restart note or artifact path>',
    },
    'xpcFallbackObservability': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': '<XPC fallback diagnostics note or artifact path>',
    },
  };
}

MacosComputerUseBetaSignoffSummary buildMacosComputerUseBetaSignoffSummary(
  MacosComputerUseBetaSignoffInputs inputs,
) {
  final gates = <MacosComputerUseBetaSignoffGate>[
    _manualChecklistGate(
      id: 'clean_install',
      label: 'Clean install',
      field: 'cleanInstall',
      inputs: inputs,
      nextAction:
          'Ask the user to complete a clean install pass and record it in the M39 manual beta checklist.',
    ),
    _upgradeMigrationGate(inputs),
    _manualChecklistGate(
      id: 'permission_grant',
      label: 'Permission grant',
      field: 'permissionGrant',
      inputs: inputs,
      nextAction:
          'Ask the user to grant Accessibility and Screen & System Audio Recording, then record the result in the M39 manual beta checklist.',
    ),
    _manualChecklistGate(
      id: 'permission_revocation',
      label: 'Permission revocation recovery',
      field: 'permissionRevocation',
      inputs: inputs,
      nextAction:
          'Ask the user to revoke and recover the helper permissions, then record the result in the M39 manual beta checklist.',
    ),
    _manualChecklistGate(
      id: 'helper_restart',
      label: 'Helper restart',
      field: 'helperRestart',
      inputs: inputs,
      nextAction:
          'Ask the user to restart Caverno and the helper, then record the one-helper process result in the M39 manual beta checklist.',
    ),
    _manualChecklistGate(
      id: 'xpc_fallback_observability',
      label: 'XPC fallback observability',
      field: 'xpcFallbackObservability',
      inputs: inputs,
      nextAction:
          'Ask the user to verify XPC fallback diagnostics are visible, then record the result in the M39 manual beta checklist.',
    ),
    _m36LiveLlmObserveOnlyGate(
      inputs.m36LiveLlmEvalSummary,
      inputs.m36LiveLlmEvalSummaryPath,
    ),
    _m23UserOperatedCycleGate(
      inputs.m23CycleOutcomeHandoff,
      inputs.m23CycleOutcomeHandoffPath,
    ),
  ];
  final ready = gates.every((gate) => gate.ready);
  return MacosComputerUseBetaSignoffSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    gates: List<MacosComputerUseBetaSignoffGate>.unmodifiable(gates),
  );
}

MacosComputerUseBetaSignoffInputs readMacosComputerUseBetaSignoffInputs({
  required Directory reportRoot,
  String? manualChecklistPath,
  String? m36LiveLlmEvalSummaryPath,
  String? m23CycleOutcomeHandoffPath,
  String? installMigrationDiagnosticsPath,
}) {
  final manualChecklistFile = manualChecklistPath == null
      ? discoverLatestM39ManualBetaChecklist(reportRoot)
      : File(manualChecklistPath);
  final m36SummaryFile = m36LiveLlmEvalSummaryPath == null
      ? discoverLatestM36LiveLlmEvalSummary(reportRoot)
      : File(m36LiveLlmEvalSummaryPath);
  final m23HandoffFile = m23CycleOutcomeHandoffPath == null
      ? discoverLatestM23CycleOutcomeHandoff(reportRoot)
      : File(m23CycleOutcomeHandoffPath);
  final installMigrationFile = installMigrationDiagnosticsPath == null
      ? discoverLatestInstallMigrationDiagnostics(reportRoot)
      : File(installMigrationDiagnosticsPath);

  return MacosComputerUseBetaSignoffInputs(
    manualChecklist: _readJsonObject(manualChecklistFile),
    manualChecklistPath: manualChecklistFile?.path,
    m36LiveLlmEvalSummary: _readJsonObject(m36SummaryFile),
    m36LiveLlmEvalSummaryPath: m36SummaryFile?.path,
    m23CycleOutcomeHandoff: _readJsonObject(m23HandoffFile),
    m23CycleOutcomeHandoffPath: m23HandoffFile?.path,
    installMigrationDiagnostics: _readJsonObject(installMigrationFile),
    installMigrationDiagnosticsPath: installMigrationFile?.path,
  );
}

File? discoverLatestM39ManualBetaChecklist(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] == 'macos_computer_use_m39_manual_beta_checklist';
  });
}

File? discoverLatestM36LiveLlmEvalSummary(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] == 'macos_computer_use_m36_live_llm_eval_summary';
  });
}

File? discoverLatestM23CycleOutcomeHandoff(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] == 'macos_computer_use_m23_cycle_outcome_handoff';
  });
}

File? discoverLatestInstallMigrationDiagnostics(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
            'macos_computer_use_install_migration_guardrails' ||
        json.containsKey('installMigrationGuardrails');
  });
}

MacosComputerUseBetaSignoffGate _manualChecklistGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseBetaSignoffInputs inputs,
  required String nextAction,
}) {
  final checklist = inputs.manualChecklist;
  if (checklist == null) {
    return MacosComputerUseBetaSignoffGate(
      id: id,
      label: label,
      status: 'manual_required',
      ready: false,
      nextAction: nextAction,
      userOperated: true,
      artifactPath: inputs.manualChecklistPath,
    );
  }
  final section = _mapValue(checklist[field]);
  final ready = _readyValue(section);
  return MacosComputerUseBetaSignoffGate(
    id: id,
    label: label,
    status: ready ? 'ready' : _statusValue(section, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? '$label beta evidence is ready.'
        : (section['nextAction'] as String? ?? nextAction),
    userOperated: true,
    artifactPath: inputs.manualChecklistPath,
    details: <String, Object?>{
      'checklistField': field,
      'evidence': section['evidence'],
      'notes': section['notes'],
    },
  );
}

MacosComputerUseBetaSignoffGate _upgradeMigrationGate(
  MacosComputerUseBetaSignoffInputs inputs,
) {
  final manualGate = _manualChecklistGate(
    id: 'upgrade_migration',
    label: 'Upgrade and migration',
    field: 'upgradeMigration',
    inputs: inputs,
    nextAction:
        'Ask the user to complete an upgrade pass, confirm M38 migration guardrails, and record it in the M39 manual beta checklist.',
  );
  final guardrails = _installMigrationGuardrails(
    inputs.installMigrationDiagnostics,
  );
  final guardrailsReady = _installMigrationReady(guardrails);
  if (manualGate.ready || !guardrailsReady) {
    return MacosComputerUseBetaSignoffGate(
      id: manualGate.id,
      label: manualGate.label,
      status: manualGate.status,
      ready: manualGate.ready,
      nextAction: manualGate.nextAction,
      userOperated: manualGate.userOperated,
      artifactPath: manualGate.artifactPath,
      details: <String, Object?>{
        ...manualGate.details,
        'installMigrationGuardrailsReady': guardrailsReady,
        'installMigrationDiagnosticsPath':
            inputs.installMigrationDiagnosticsPath,
      },
    );
  }
  return MacosComputerUseBetaSignoffGate(
    id: 'upgrade_migration',
    label: 'Upgrade and migration',
    status: 'ready',
    ready: true,
    nextAction: 'M38 install migration guardrails are ready.',
    userOperated: true,
    artifactPath: inputs.installMigrationDiagnosticsPath,
    details: <String, Object?>{
      'installMigrationGuardrailsReady': true,
      'manualChecklistPath': inputs.manualChecklistPath,
    },
  );
}

MacosComputerUseBetaSignoffGate _m36LiveLlmObserveOnlyGate(
  Map<String, dynamic>? summary,
  String? summaryPath,
) {
  if (summary == null) {
    return const MacosComputerUseBetaSignoffGate(
      id: 'live_llm_observe_only_canaries',
      label: 'Live LLM observe-only canaries',
      status: 'missing',
      ready: false,
      nextAction:
          'Run M36 Live LLM evaluation and provide its canary_summary.json.',
      userOperated: false,
    );
  }
  final gate = _mapValue(summary['m36LiveLlmEvaluationGate']);
  final coverage = _listValue(summary['requiredCoverage']);
  final coverageReady =
      coverage.isNotEmpty &&
      coverage.every((item) {
        return item is Map && item['ok'] == true;
      });
  final ready =
      summary['schemaName'] == 'macos_computer_use_m36_live_llm_eval_summary' &&
      summary['ready'] == true &&
      gate['ok'] == true &&
      summary['desktopActionBoundary'] == 'no_desktop_action' &&
      summary['tccBoundary'] == 'no_tcc_operation' &&
      coverageReady;
  return MacosComputerUseBetaSignoffGate(
    id: 'live_llm_observe_only_canaries',
    label: 'Live LLM observe-only canaries',
    status: ready ? 'ready' : _statusValue(summary, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M36 Live LLM observe-only evaluation is ready.'
        : 'Run M36 until m36LiveLlmEvaluationGate.ok is true with no TCC or desktop actions.',
    userOperated: false,
    artifactPath: summaryPath,
    details: <String, Object?>{
      'schemaName': summary['schemaName'],
      'tccBoundary': summary['tccBoundary'],
      'desktopActionBoundary': summary['desktopActionBoundary'],
      'requiredCoverageCount': coverage.length,
      'failureClasses': summary['failureClasses'],
    },
  );
}

MacosComputerUseBetaSignoffGate _m23UserOperatedCycleGate(
  Map<String, dynamic>? handoff,
  String? handoffPath,
) {
  if (handoff == null) {
    return const MacosComputerUseBetaSignoffGate(
      id: 'user_operated_action_cycle',
      label: 'User-operated observe-approve-execute-review cycle',
      status: 'missing',
      ready: false,
      nextAction:
          'Complete the M15-M23 report-only handoff chain around one user-operated runtime action and provide the M23 cycle outcome handoff.',
      userOperated: true,
    );
  }
  final gate = _mapValue(handoff['m23CycleOutcomeHandoffGate']);
  final ready =
      handoff['schemaName'] == 'macos_computer_use_m23_cycle_outcome_handoff' &&
      handoff['ready'] == true &&
      gate['status'] == 'ready' &&
      handoff['desktopActionBoundary'] == 'no_desktop_action' &&
      handoff['tccBoundary'] == 'no_tcc_operation' &&
      handoff['llmBoundary'] == 'no_llm_call';
  return MacosComputerUseBetaSignoffGate(
    id: 'user_operated_action_cycle',
    label: 'User-operated observe-approve-execute-review cycle',
    status: ready ? 'ready' : _statusValue(gate, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M23 cycle outcome handoff is ready.'
        : 'Complete M23 with a ready cycle outcome handoff after the user-operated runtime action is reviewed.',
    userOperated: true,
    artifactPath: handoffPath,
    details: <String, Object?>{
      'cycleOutcome': handoff['cycleOutcome'],
      'nextObserveNeeded': handoff['nextObserveNeeded'],
      'desktopActionBoundary': handoff['desktopActionBoundary'],
      'tccBoundary': handoff['tccBoundary'],
      'llmBoundary': handoff['llmBoundary'],
      'blockers': gate['blockers'],
    },
  );
}

Map<String, dynamic> _installMigrationGuardrails(
  Map<String, dynamic>? diagnostics,
) {
  if (diagnostics == null) {
    return const <String, dynamic>{};
  }
  if (diagnostics['schemaName'] ==
      'macos_computer_use_install_migration_guardrails') {
    return diagnostics;
  }
  return _mapValue(diagnostics['installMigrationGuardrails']);
}

bool _installMigrationReady(Map<String, dynamic> guardrails) {
  if (guardrails.isEmpty) {
    return false;
  }
  final gate = _mapValue(guardrails['m38InstallMigrationGate']);
  final blockers = _stringList(gate['blockers']);
  return guardrails['status'] == 'ready' &&
      gate['status'] == 'ready' &&
      guardrails['oldHelperActionRequestsBlocked'] == true &&
      blockers.isEmpty;
}

bool _readyValue(Map<String, dynamic> section) {
  return section['ready'] == true ||
      section['ok'] == true ||
      section['status'] == 'ready' ||
      section['status'] == 'passed';
}

String _statusValue(Map<dynamic, dynamic> json, {required String fallback}) {
  final status = json['status'];
  if (status is String && status.isNotEmpty) {
    return status;
  }
  return fallback;
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  return const <String, dynamic>{};
}

List<dynamic> _listValue(Object? value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}

List<String> _stringList(Object? value) {
  if (value is Iterable) {
    return value.map((item) => '$item').toList(growable: false);
  }
  return const <String>[];
}

File? _latestJsonMatching(
  Directory root,
  bool Function(Map<String, dynamic> json) matches,
) {
  final candidates = <File>[];
  for (final file in _jsonFiles(root)) {
    final json = _readJsonObject(file);
    if (json != null && matches(json)) {
      candidates.add(file);
    }
  }
  candidates.sort((left, right) {
    final modifiedCompare = left.statSync().modified.compareTo(
      right.statSync().modified,
    );
    if (modifiedCompare != 0) {
      return modifiedCompare;
    }
    return left.path.compareTo(right.path);
  });
  return candidates.isEmpty ? null : candidates.last;
}

Iterable<File> _jsonFiles(Directory root) {
  if (!root.existsSync()) {
    return const <File>[];
  }
  return root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'));
}

Map<String, dynamic>? _readJsonObject(File? file) {
  if (file == null || !file.existsSync()) {
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
  return null;
}

String _joinedOrNone(List<String> values) {
  return values.isEmpty ? 'none' : values.join(', ');
}

String _artifactCell(String? path) {
  return path == null || path.isEmpty ? '-' : '`$path`';
}

String _markdownCell(Object? value) {
  return '$value'.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
