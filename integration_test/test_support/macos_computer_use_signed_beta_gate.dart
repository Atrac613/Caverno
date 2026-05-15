import 'dart:convert';
import 'dart:io';

class MacosComputerUseSignedBetaGate {
  const MacosComputerUseSignedBetaGate({
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

class MacosComputerUseSignedBetaSummary {
  const MacosComputerUseSignedBetaSummary({
    required this.status,
    required this.ready,
    required this.gates,
  });

  final String status;
  final bool ready;
  final List<MacosComputerUseSignedBetaGate> gates;

  List<MacosComputerUseSignedBetaGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  List<MacosComputerUseSignedBetaGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<MacosComputerUseSignedBetaGate> get userOperatedGates =>
      gates.where((gate) => gate.userOperated).toList(growable: false);

  Map<String, Object?> get signedBetaReviewSummary {
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
      'status': ready ? 'ready_for_signed_beta' : 'blocked_gates_present',
      'readyGateIds': readyGateIds,
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedUserOperatedGateIds,
      'blockedAutomationSafeGateIds': blockedAutomationSafeGateIds,
      'operationBoundarySummary':
          'M50 reads signed beta evidence only; notarization, TCC grants, permission revocation, helper restart, and desktop actions remain user-operated release steps.',
    };
  }

  Map<String, Object?> get m50SignedBetaGate {
    final blockers = blockedGates
        .map((gate) => '${gate.id}:${gate.status}')
        .toList(growable: false);
    return <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockers,
      'checks': gates.map((gate) => gate.toJson()).toList(growable: false),
      'nextAction': ready
          ? 'M50 signed beta evidence is ready for M51 production launch gate refresh.'
          : 'Resolve blocked M50 signed beta checks before starting M51.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m50_signed_beta_gate',
      'schemaVersion': 1,
      'milestone': 'M50',
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
      'signedBetaReviewSummary': signedBetaReviewSummary,
      'm50SignedBetaGate': m50SignedBetaGate,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = signedBetaReviewSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M50 Signed Beta Gate')
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
      ..writeln('## Signed Beta Review Summary')
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
      ..writeln('## Signed Beta Checklist Template')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(signedBetaChecklistTemplate()),
      )
      ..writeln('```');

    return buffer.toString();
  }
}

class MacosComputerUseSignedBetaInputs {
  const MacosComputerUseSignedBetaInputs({
    required this.signedBetaChecklist,
    required this.signedBetaChecklistPath,
    required this.releaseArtifactReport,
    required this.releaseArtifactReportPath,
    required this.releasePackagingReport,
    required this.releasePackagingReportPath,
    required this.m46ElementGroundedLlmEvalSummary,
    required this.m46ElementGroundedLlmEvalSummaryPath,
    required this.m48UserOperatedActionPilot,
    required this.m48UserOperatedActionPilotPath,
    required this.m49PrivacyAuditReleasePack,
    required this.m49PrivacyAuditReleasePackPath,
  });

  final Map<String, dynamic>? signedBetaChecklist;
  final String? signedBetaChecklistPath;
  final Map<String, dynamic>? releaseArtifactReport;
  final String? releaseArtifactReportPath;
  final Map<String, dynamic>? releasePackagingReport;
  final String? releasePackagingReportPath;
  final Map<String, dynamic>? m46ElementGroundedLlmEvalSummary;
  final String? m46ElementGroundedLlmEvalSummaryPath;
  final Map<String, dynamic>? m48UserOperatedActionPilot;
  final String? m48UserOperatedActionPilotPath;
  final Map<String, dynamic>? m49PrivacyAuditReleasePack;
  final String? m49PrivacyAuditReleasePackPath;
}

Map<String, Object?> signedBetaChecklistTemplate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m50_signed_beta_checklist',
    'schemaVersion': 1,
    'milestone': 'M50',
    'automationBoundary': 'user_operated_signed_beta_checks',
    'notarizedBetaBuild': _readyTemplate(
      '<notarization ticket, stapler validation, or signed beta build note>',
    ),
    'cleanInstall': _readyTemplate('<clean install note or artifact path>'),
    'upgradeMigration': _readyTemplate(
      '<upgrade and migration note or artifact path>',
    ),
    'permissionGrant': _readyTemplate(
      '<permission grant note or artifact path>',
    ),
    'permissionRevocation': _readyTemplate(
      '<permission revocation recovery note or artifact path>',
    ),
    'helperRestart': _readyTemplate('<helper restart note or artifact path>'),
    'xpcFallbackObservability': _readyTemplate(
      '<XPC fallback diagnostics note or artifact path>',
    ),
  };
}

MacosComputerUseSignedBetaSummary buildMacosComputerUseSignedBetaSummary(
  MacosComputerUseSignedBetaInputs inputs,
) {
  final gates = <MacosComputerUseSignedBetaGate>[
    _signedArtifactGate(
      inputs.releaseArtifactReport,
      inputs.releaseArtifactReportPath,
    ),
    _releasePackagingGate(
      inputs.releasePackagingReport,
      inputs.releasePackagingReportPath,
    ),
    _checklistGate(
      id: 'notarized_beta_build',
      label: 'Notarized signed beta build',
      field: 'notarizedBetaBuild',
      inputs: inputs,
      nextAction:
          'Ask the user to notarize and staple the signed beta build, then record the evidence in the M50 signed beta checklist.',
    ),
    _checklistGate(
      id: 'clean_install',
      label: 'Clean install',
      field: 'cleanInstall',
      inputs: inputs,
      nextAction:
          'Ask the user to complete a clean install pass with the signed beta build and record the evidence.',
    ),
    _checklistGate(
      id: 'upgrade_migration',
      label: 'Upgrade and migration',
      field: 'upgradeMigration',
      inputs: inputs,
      nextAction:
          'Ask the user to complete an upgrade pass from the previous build and record the migration evidence.',
    ),
    _checklistGate(
      id: 'permission_grant',
      label: 'Permission grant',
      field: 'permissionGrant',
      inputs: inputs,
      nextAction:
          'Ask the user to grant helper-owned Accessibility and Screen & System Audio Recording for the signed beta build, then record the evidence.',
    ),
    _checklistGate(
      id: 'permission_revocation',
      label: 'Permission revocation recovery',
      field: 'permissionRevocation',
      inputs: inputs,
      nextAction:
          'Ask the user to revoke and recover helper-owned permissions for the signed beta build, then record the evidence.',
    ),
    _checklistGate(
      id: 'helper_restart',
      label: 'Helper restart',
      field: 'helperRestart',
      inputs: inputs,
      nextAction:
          'Ask the user to restart the signed beta app and helper, then record one-helper process evidence.',
    ),
    _checklistGate(
      id: 'xpc_fallback_observability',
      label: 'XPC fallback observability',
      field: 'xpcFallbackObservability',
      inputs: inputs,
      nextAction:
          'Ask the user to verify XPC fallback diagnostics are visible in the signed beta build, then record the evidence.',
    ),
    _m46ElementGroundedLlmGate(
      inputs.m46ElementGroundedLlmEvalSummary,
      inputs.m46ElementGroundedLlmEvalSummaryPath,
    ),
    _m48UserOperatedActionCycleGate(
      inputs.m48UserOperatedActionPilot,
      inputs.m48UserOperatedActionPilotPath,
    ),
    _m49PrivacyAuditReleasePackGate(
      inputs.m49PrivacyAuditReleasePack,
      inputs.m49PrivacyAuditReleasePackPath,
    ),
  ];
  final ready = gates.every((gate) => gate.ready);
  return MacosComputerUseSignedBetaSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    gates: List<MacosComputerUseSignedBetaGate>.unmodifiable(gates),
  );
}

MacosComputerUseSignedBetaInputs readMacosComputerUseSignedBetaInputs({
  required Directory reportRoot,
  String? signedBetaChecklistPath,
  String? releaseArtifactReportPath,
  String? releasePackagingReportPath,
  String? m46ElementGroundedLlmEvalSummaryPath,
  String? m48UserOperatedActionPilotPath,
  String? m49PrivacyAuditReleasePackPath,
}) {
  final checklistFile = signedBetaChecklistPath == null
      ? discoverLatestM50SignedBetaChecklist(reportRoot)
      : File(signedBetaChecklistPath);
  final releaseArtifactFile = releaseArtifactReportPath == null
      ? discoverLatestReleaseArtifactReport(reportRoot)
      : File(releaseArtifactReportPath);
  final releasePackagingFile = releasePackagingReportPath == null
      ? discoverLatestReleasePackagingReport(reportRoot)
      : File(releasePackagingReportPath);
  final m46File = m46ElementGroundedLlmEvalSummaryPath == null
      ? discoverLatestM46ElementGroundedLlmEvalSummary(reportRoot)
      : File(m46ElementGroundedLlmEvalSummaryPath);
  final m48File = m48UserOperatedActionPilotPath == null
      ? discoverLatestM48UserOperatedActionPilot(reportRoot)
      : File(m48UserOperatedActionPilotPath);
  final m49File = m49PrivacyAuditReleasePackPath == null
      ? discoverLatestM49PrivacyAuditReleasePack(reportRoot)
      : File(m49PrivacyAuditReleasePackPath);

  return MacosComputerUseSignedBetaInputs(
    signedBetaChecklist: _readJsonObject(checklistFile),
    signedBetaChecklistPath: checklistFile?.path,
    releaseArtifactReport: _readJsonObject(releaseArtifactFile),
    releaseArtifactReportPath: releaseArtifactFile?.path,
    releasePackagingReport: _readJsonObject(releasePackagingFile),
    releasePackagingReportPath: releasePackagingFile?.path,
    m46ElementGroundedLlmEvalSummary: _readJsonObject(m46File),
    m46ElementGroundedLlmEvalSummaryPath: m46File?.path,
    m48UserOperatedActionPilot: _readJsonObject(m48File),
    m48UserOperatedActionPilotPath: m48File?.path,
    m49PrivacyAuditReleasePack: _readJsonObject(m49File),
    m49PrivacyAuditReleasePackPath: m49File?.path,
  );
}

File? discoverLatestM50SignedBetaChecklist(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] == 'macos_computer_use_m50_signed_beta_checklist';
  });
}

File? discoverLatestReleaseArtifactReport(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json.containsKey('releaseSignoffGate');
  });
}

File? discoverLatestReleasePackagingReport(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] == 'macos_computer_use_m33_release_packaging';
  });
}

File? discoverLatestM46ElementGroundedLlmEvalSummary(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m46_element_grounded_llm_eval_summary';
  });
}

File? discoverLatestM48UserOperatedActionPilot(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m48_user_operated_action_pilot';
  });
}

File? discoverLatestM49PrivacyAuditReleasePack(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m49_privacy_audit_release_pack';
  });
}

MacosComputerUseSignedBetaGate _signedArtifactGate(
  Map<String, dynamic>? report,
  String? reportPath,
) {
  if (report == null) {
    return const MacosComputerUseSignedBetaGate(
      id: 'signed_beta_artifact',
      label: 'Signed beta artifact',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M7 release artifact sign-off and attach the signed beta artifact report.',
      userOperated: false,
    );
  }
  final gate = _mapValue(report['releaseSignoffGate']);
  final blockers = _stringList(gate['blockers']);
  final ready = gate['status'] == 'ready' && blockers.isEmpty;
  return MacosComputerUseSignedBetaGate(
    id: 'signed_beta_artifact',
    label: 'Signed beta artifact',
    status: ready ? 'ready' : _statusValue(gate, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'Signed beta artifact evidence is ready.'
        : (gate['nextAction'] as String? ??
              'Resolve release artifact blockers and rerun M7 sign-off.'),
    userOperated: false,
    artifactPath: reportPath,
    details: <String, Object?>{'blockers': blockers},
  );
}

MacosComputerUseSignedBetaGate _releasePackagingGate(
  Map<String, dynamic>? packaging,
  String? packagingPath,
) {
  if (packaging == null) {
    return const MacosComputerUseSignedBetaGate(
      id: 'release_packaging_lane',
      label: 'Release packaging lane',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M33 release packaging report and attach the ready JSON.',
      userOperated: false,
    );
  }
  const requiredIds = <String>{
    'main_release_entitlements',
    'helper_release_entitlements',
    'hardened_runtime',
    'helper_bundle_identity',
    'launch_agent_mach_service',
    'embed_helper_phase',
    'identity_free_signing_defaults',
  };
  final readyIds = <String>{};
  for (final check in _listValue(packaging['checks'])) {
    if (check is Map && check['ok'] == true) {
      readyIds.add('${check['id']}');
    }
  }
  final ready =
      packaging['schemaName'] == 'macos_computer_use_m33_release_packaging' &&
      packaging['ready'] == true &&
      readyIds.containsAll(requiredIds);
  return MacosComputerUseSignedBetaGate(
    id: 'release_packaging_lane',
    label: 'Release packaging lane',
    status: ready ? 'ready' : _statusValue(packaging, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M33 release packaging lane is ready.'
        : 'Resolve M33 release packaging blockers before signed beta.',
    userOperated: false,
    artifactPath: packagingPath,
    details: <String, Object?>{
      'readyCheckIds': readyIds.toList(growable: false)..sort(),
      'missingCheckIds':
          requiredIds.difference(readyIds).toList(growable: false)..sort(),
    },
  );
}

MacosComputerUseSignedBetaGate _checklistGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseSignedBetaInputs inputs,
  required String nextAction,
}) {
  final checklist = inputs.signedBetaChecklist;
  if (checklist == null) {
    return MacosComputerUseSignedBetaGate(
      id: id,
      label: label,
      status: 'manual_required',
      ready: false,
      nextAction: nextAction,
      userOperated: true,
      artifactPath: inputs.signedBetaChecklistPath,
    );
  }
  final section = _mapValue(checklist[field]);
  final ready = _readyValue(section);
  return MacosComputerUseSignedBetaGate(
    id: id,
    label: label,
    status: ready ? 'ready' : _statusValue(section, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? '$label signed beta evidence is ready.'
        : (section['nextAction'] as String? ?? nextAction),
    userOperated: true,
    artifactPath: inputs.signedBetaChecklistPath,
    details: <String, Object?>{
      'checklistField': field,
      'evidence': section['evidence'],
      'notes': section['notes'],
    },
  );
}

MacosComputerUseSignedBetaGate _m46ElementGroundedLlmGate(
  Map<String, dynamic>? summary,
  String? summaryPath,
) {
  if (summary == null) {
    return const MacosComputerUseSignedBetaGate(
      id: 'element_grounded_llm_evaluation',
      label: 'Element-grounded LLM evaluation',
      status: 'missing',
      ready: false,
      nextAction:
          'Run M46 element-grounded LLM evaluation and attach the ready canary_summary.json.',
      userOperated: false,
    );
  }
  final gate = _mapValue(summary['m46ElementGroundedLlmEvaluationGate']);
  final coverage = _listValue(summary['requiredCoverage']);
  final coverageReady =
      coverage.isNotEmpty &&
      coverage.every((item) => item is Map && item['ok'] == true);
  final ready =
      summary['schemaName'] ==
          'macos_computer_use_m46_element_grounded_llm_eval_summary' &&
      summary['ready'] == true &&
      gate['ok'] == true &&
      summary['desktopActionBoundary'] == 'no_desktop_action' &&
      summary['tccBoundary'] == 'no_tcc_operation' &&
      coverageReady;
  return MacosComputerUseSignedBetaGate(
    id: 'element_grounded_llm_evaluation',
    label: 'Element-grounded LLM evaluation',
    status: ready ? 'ready' : _statusValue(summary, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M46 element-grounded LLM evaluation is ready.'
        : 'Rerun M46 until all required coverage is ready with no TCC or desktop actions.',
    userOperated: false,
    artifactPath: summaryPath,
    details: <String, Object?>{
      'requiredCoverageCount': coverage.length,
      'tccBoundary': summary['tccBoundary'],
      'desktopActionBoundary': summary['desktopActionBoundary'],
      'failureClasses': summary['failureClasses'],
    },
  );
}

MacosComputerUseSignedBetaGate _m48UserOperatedActionCycleGate(
  Map<String, dynamic>? pilot,
  String? pilotPath,
) {
  if (pilot == null) {
    return const MacosComputerUseSignedBetaGate(
      id: 'user_operated_action_cycle',
      label: 'User-operated action cycle',
      status: 'missing',
      ready: false,
      nextAction:
          'Run M48 user-operated action pilot and attach the ready user_operated_action_pilot.json.',
      userOperated: true,
    );
  }
  final gate = _mapValue(pilot['m48UserOperatedActionPilotGate']);
  final ready =
      pilot['schemaName'] ==
          'macos_computer_use_m48_user_operated_action_pilot' &&
      pilot['ready'] == true &&
      gate['status'] == 'ready' &&
      _stringList(gate['blockers']).isEmpty &&
      pilot['desktopActionBoundary'] == 'user_operated' &&
      pilot['tccBoundary'] == 'user_operated' &&
      pilot['llmBoundary'] == 'no_llm_call';
  return MacosComputerUseSignedBetaGate(
    id: 'user_operated_action_cycle',
    label: 'User-operated action cycle',
    status: ready ? 'ready' : _statusValue(gate, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M48 user-operated action cycle is ready.'
        : 'Resolve M48 action-cycle blockers before signed beta.',
    userOperated: true,
    artifactPath: pilotPath,
    details: <String, Object?>{
      'desktopActionBoundary': pilot['desktopActionBoundary'],
      'tccBoundary': pilot['tccBoundary'],
      'llmBoundary': pilot['llmBoundary'],
      'blockers': gate['blockers'],
    },
  );
}

MacosComputerUseSignedBetaGate _m49PrivacyAuditReleasePackGate(
  Map<String, dynamic>? pack,
  String? packPath,
) {
  if (pack == null) {
    return const MacosComputerUseSignedBetaGate(
      id: 'privacy_audit_release_pack',
      label: 'Privacy and audit release pack',
      status: 'missing',
      ready: false,
      nextAction:
          'Run M49 privacy and audit release pack and attach the ready privacy_audit_release_pack.json.',
      userOperated: true,
    );
  }
  final gate = _mapValue(pack['m49PrivacyAuditReleasePackGate']);
  final ready =
      pack['schemaName'] ==
          'macos_computer_use_m49_privacy_audit_release_pack' &&
      pack['ready'] == true &&
      gate['status'] == 'ready' &&
      _stringList(gate['blockers']).isEmpty &&
      pack['desktopActionBoundary'] == 'no_desktop_action' &&
      pack['tccBoundary'] == 'no_tcc_operation' &&
      pack['llmBoundary'] == 'no_llm_call' &&
      pack['rawPayloadExportBoundary'] == 'no_raw_payload_export';
  return MacosComputerUseSignedBetaGate(
    id: 'privacy_audit_release_pack',
    label: 'Privacy and audit release pack',
    status: ready ? 'ready' : _statusValue(gate, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M49 privacy and audit release pack is ready.'
        : 'Resolve M49 privacy and audit blockers before signed beta.',
    userOperated: true,
    artifactPath: packPath,
    details: <String, Object?>{
      'desktopActionBoundary': pack['desktopActionBoundary'],
      'tccBoundary': pack['tccBoundary'],
      'llmBoundary': pack['llmBoundary'],
      'rawPayloadExportBoundary': pack['rawPayloadExportBoundary'],
      'blockers': gate['blockers'],
    },
  );
}

bool _readyValue(Map<String, dynamic> section) {
  return section['ready'] == true ||
      section['ok'] == true ||
      section['status'] == 'ready' ||
      section['status'] == 'passed';
}

Map<String, Object?> _readyTemplate(String evidence) {
  return <String, Object?>{
    'status': 'ready',
    'ready': true,
    'evidence': evidence,
  };
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
