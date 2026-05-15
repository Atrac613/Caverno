import 'dart:convert';
import 'dart:io';

class MacosComputerUseM51ProductionLaunchGate {
  const MacosComputerUseM51ProductionLaunchGate({
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

class MacosComputerUseM51ProductionLaunchSummary {
  const MacosComputerUseM51ProductionLaunchSummary({
    required this.status,
    required this.ready,
    required this.gates,
  });

  final String status;
  final bool ready;
  final List<MacosComputerUseM51ProductionLaunchGate> gates;

  List<MacosComputerUseM51ProductionLaunchGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  List<MacosComputerUseM51ProductionLaunchGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<MacosComputerUseM51ProductionLaunchGate> get userOperatedGates =>
      gates.where((gate) => gate.userOperated).toList(growable: false);

  Map<String, Object?> get launchReviewSummary {
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
      'status': ready ? 'ready_for_production_launch' : 'blocked_gates_present',
      'readyGateIds': readyGateIds,
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedUserOperatedGateIds,
      'blockedAutomationSafeGateIds': blockedAutomationSafeGateIds,
      'operationBoundarySummary':
          'M51 reads release evidence only; notarization, TCC, support validation, and desktop actions remain user-operated release steps.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m51_production_launch_gate',
      'schemaVersion': 1,
      'milestone': 'M51',
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
      'launchReviewSummary': launchReviewSummary,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = launchReviewSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M51 Production Launch Gate')
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
      ..writeln('## Launch Review Summary')
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
      ..writeln('## Launch Checklist Template')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(m51LaunchChecklistTemplate()),
      )
      ..writeln('```');

    return buffer.toString();
  }
}

class MacosComputerUseM51ProductionLaunchInputs {
  const MacosComputerUseM51ProductionLaunchInputs({
    required this.launchChecklist,
    required this.launchChecklistPath,
    required this.releaseArtifactReport,
    required this.releaseArtifactReportPath,
    required this.releasePackagingReport,
    required this.releasePackagingReportPath,
    required this.manualTccReport,
    required this.manualTccReportPath,
    required this.m46ElementGroundedLlmEvalSummary,
    required this.m46ElementGroundedLlmEvalSummaryPath,
    required this.m49PrivacyAuditReleasePack,
    required this.m49PrivacyAuditReleasePackPath,
    required this.m50SignedBetaGate,
    required this.m50SignedBetaGatePath,
    required this.diagnostics,
    required this.diagnosticsPath,
  });

  final Map<String, dynamic>? launchChecklist;
  final String? launchChecklistPath;
  final Map<String, dynamic>? releaseArtifactReport;
  final String? releaseArtifactReportPath;
  final Map<String, dynamic>? releasePackagingReport;
  final String? releasePackagingReportPath;
  final Map<String, dynamic>? manualTccReport;
  final String? manualTccReportPath;
  final Map<String, dynamic>? m46ElementGroundedLlmEvalSummary;
  final String? m46ElementGroundedLlmEvalSummaryPath;
  final Map<String, dynamic>? m49PrivacyAuditReleasePack;
  final String? m49PrivacyAuditReleasePackPath;
  final Map<String, dynamic>? m50SignedBetaGate;
  final String? m50SignedBetaGatePath;
  final Map<String, dynamic>? diagnostics;
  final String? diagnosticsPath;
}

Map<String, Object?> m51LaunchChecklistTemplate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m51_launch_checklist',
    'schemaVersion': 1,
    'milestone': 'M51',
    'automationBoundary': 'user_operated_release_steps',
    'notarization': _readyTemplate('<notarization ticket or release note>'),
    'manualTccRunbook': _readyTemplate('<manual TCC runbook sign-off note>'),
    'emergencyStop': _readyTemplate('<emergency stop validation note>'),
    'privacyCopy': _readyTemplate('<privacy copy review note>'),
    'supportDiagnostics': _readyTemplate('<support diagnostics export note>'),
    'productionLaunchBoundaries': _readyTemplate(
      '<default-off, rollback, and support escalation review note>',
    ),
  };
}

MacosComputerUseM51ProductionLaunchSummary
buildMacosComputerUseM51ProductionLaunchSummary(
  MacosComputerUseM51ProductionLaunchInputs inputs,
) {
  final gates = <MacosComputerUseM51ProductionLaunchGate>[
    _signedArtifactGate(
      inputs.releaseArtifactReport,
      inputs.releaseArtifactReportPath,
    ),
    _notarizationGate(inputs),
    _helperIdentityGate(inputs),
    _manualTccRunbookGate(inputs),
    _m46ElementGroundedLlmGate(
      inputs.m46ElementGroundedLlmEvalSummary,
      inputs.m46ElementGroundedLlmEvalSummaryPath,
    ),
    _m49PrivacyAuditReleasePackGate(
      inputs.m49PrivacyAuditReleasePack,
      inputs.m49PrivacyAuditReleasePackPath,
    ),
    _m50SignedBetaGate(inputs.m50SignedBetaGate, inputs.m50SignedBetaGatePath),
    _launchChecklistGate(
      id: 'emergency_stop',
      label: 'Emergency stop',
      field: 'emergencyStop',
      inputs: inputs,
      nextAction:
          'Ask the user to validate the emergency stop release behavior and record it in the M51 launch checklist.',
    ),
    _launchChecklistGate(
      id: 'privacy_copy',
      label: 'Privacy copy',
      field: 'privacyCopy',
      inputs: inputs,
      nextAction:
          'Ask the user to review the Computer Use privacy copy and record it in the M51 launch checklist.',
    ),
    _launchChecklistGate(
      id: 'support_diagnostics',
      label: 'Support diagnostics',
      field: 'supportDiagnostics',
      inputs: inputs,
      nextAction:
          'Ask the user to export support diagnostics and record the support sign-off in the M51 launch checklist.',
    ),
    _launchChecklistGate(
      id: 'production_launch_boundaries',
      label: 'Production launch boundaries',
      field: 'productionLaunchBoundaries',
      inputs: inputs,
      nextAction:
          'Ask the user to review default-off rollout, rollback, and support escalation boundaries in the M51 launch checklist.',
    ),
  ];
  final ready = gates.every((gate) => gate.ready);
  return MacosComputerUseM51ProductionLaunchSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    gates: List<MacosComputerUseM51ProductionLaunchGate>.unmodifiable(gates),
  );
}

MacosComputerUseM51ProductionLaunchInputs
readMacosComputerUseM51ProductionLaunchInputs({
  required Directory reportRoot,
  String? launchChecklistPath,
  String? releaseArtifactReportPath,
  String? releasePackagingReportPath,
  String? manualTccReportPath,
  String? m46ElementGroundedLlmEvalSummaryPath,
  String? m49PrivacyAuditReleasePackPath,
  String? m50SignedBetaGatePath,
  String? diagnosticsPath,
}) {
  final launchChecklistFile = launchChecklistPath == null
      ? discoverLatestM51LaunchChecklist(reportRoot)
      : File(launchChecklistPath);
  final releaseArtifactFile = releaseArtifactReportPath == null
      ? discoverLatestReleaseArtifactReport(reportRoot)
      : File(releaseArtifactReportPath);
  final releasePackagingFile = releasePackagingReportPath == null
      ? discoverLatestReleasePackagingReport(reportRoot)
      : File(releasePackagingReportPath);
  final manualTccFile = manualTccReportPath == null
      ? discoverLatestManualTccReport(reportRoot)
      : File(manualTccReportPath);
  final m46File = m46ElementGroundedLlmEvalSummaryPath == null
      ? discoverLatestM46ElementGroundedLlmEvalSummary(reportRoot)
      : File(m46ElementGroundedLlmEvalSummaryPath);
  final m49File = m49PrivacyAuditReleasePackPath == null
      ? discoverLatestM49PrivacyAuditReleasePack(reportRoot)
      : File(m49PrivacyAuditReleasePackPath);
  final m50File = m50SignedBetaGatePath == null
      ? discoverLatestM50SignedBetaGate(reportRoot)
      : File(m50SignedBetaGatePath);
  final diagnosticsFile = diagnosticsPath == null
      ? discoverLatestDiagnostics(reportRoot)
      : File(diagnosticsPath);

  return MacosComputerUseM51ProductionLaunchInputs(
    launchChecklist: _readJsonObject(launchChecklistFile),
    launchChecklistPath: launchChecklistFile?.path,
    releaseArtifactReport: _readJsonObject(releaseArtifactFile),
    releaseArtifactReportPath: releaseArtifactFile?.path,
    releasePackagingReport: _readJsonObject(releasePackagingFile),
    releasePackagingReportPath: releasePackagingFile?.path,
    manualTccReport: _readJsonObject(manualTccFile),
    manualTccReportPath: manualTccFile?.path,
    m46ElementGroundedLlmEvalSummary: _readJsonObject(m46File),
    m46ElementGroundedLlmEvalSummaryPath: m46File?.path,
    m49PrivacyAuditReleasePack: _readJsonObject(m49File),
    m49PrivacyAuditReleasePackPath: m49File?.path,
    m50SignedBetaGate: _readJsonObject(m50File),
    m50SignedBetaGatePath: m50File?.path,
    diagnostics: _readJsonObject(diagnosticsFile),
    diagnosticsPath: diagnosticsFile?.path,
  );
}

File? discoverLatestM51LaunchChecklist(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] == 'macos_computer_use_m51_launch_checklist';
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

File? discoverLatestManualTccReport(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
            'macos_computer_use_manual_tcc_report_summary' ||
        json.containsKey('releaseRuntimeSignoffGate');
  });
}

File? discoverLatestM46ElementGroundedLlmEvalSummary(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m46_element_grounded_llm_eval_summary';
  });
}

File? discoverLatestM49PrivacyAuditReleasePack(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] ==
        'macos_computer_use_m49_privacy_audit_release_pack';
  });
}

File? discoverLatestM50SignedBetaGate(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json['schemaName'] == 'macos_computer_use_m50_signed_beta_gate';
  });
}

File? discoverLatestDiagnostics(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json.containsKey('installMigrationGuardrails') ||
        json['schemaName'] == 'macos_computer_use_install_migration_guardrails';
  });
}

MacosComputerUseM51ProductionLaunchGate _signedArtifactGate(
  Map<String, dynamic>? report,
  String? reportPath,
) {
  if (report == null) {
    return const MacosComputerUseM51ProductionLaunchGate(
      id: 'signed_artifact',
      label: 'Signed release artifact',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M7 release artifact sign-off and attach the release artifact report.',
      userOperated: false,
    );
  }
  final gate = _mapValue(report['releaseSignoffGate']);
  final blockers = _stringList(gate['blockers']);
  final ready = gate['status'] == 'ready' && blockers.isEmpty;
  return MacosComputerUseM51ProductionLaunchGate(
    id: 'signed_artifact',
    label: 'Signed release artifact',
    status: ready ? 'ready' : _statusValue(gate, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'Signed release artifact evidence is ready.'
        : (gate['nextAction'] as String? ??
              'Resolve release artifact blockers and rerun M7 sign-off.'),
    userOperated: false,
    artifactPath: reportPath,
    details: <String, Object?>{'blockers': blockers},
  );
}

MacosComputerUseM51ProductionLaunchGate _notarizationGate(
  MacosComputerUseM51ProductionLaunchInputs inputs,
) {
  return _launchChecklistGate(
    id: 'notarization',
    label: 'Notarization and stapling',
    field: 'notarization',
    inputs: inputs,
    nextAction:
        'Ask the user to attach notarization ticket and stapler validation evidence in the M51 launch checklist.',
  );
}

MacosComputerUseM51ProductionLaunchGate _helperIdentityGate(
  MacosComputerUseM51ProductionLaunchInputs inputs,
) {
  final packaging = inputs.releasePackagingReport;
  final guardrails = _installMigrationGuardrails(inputs.diagnostics);
  final packagingReady =
      packaging?['schemaName'] == 'macos_computer_use_m33_release_packaging' &&
      packaging?['ready'] == true &&
      _releasePackagingChecksReady(packaging, const <String>{
        'helper_bundle_identity',
        'launch_agent_mach_service',
      });
  final guardrailsReady = _installMigrationReady(guardrails);
  final ready = packagingReady && guardrailsReady;
  return MacosComputerUseM51ProductionLaunchGate(
    id: 'helper_identity',
    label: 'Helper identity',
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    nextAction: ready
        ? 'Helper bundle identity and migration guardrails are ready.'
        : 'Provide ready M33 packaging and M38 diagnostics proving helper identity and migration guardrails.',
    userOperated: false,
    artifactPath: inputs.releasePackagingReportPath ?? inputs.diagnosticsPath,
    details: <String, Object?>{
      'releasePackagingReady': packagingReady,
      'installMigrationGuardrailsReady': guardrailsReady,
      'releasePackagingPath': inputs.releasePackagingReportPath,
      'diagnosticsPath': inputs.diagnosticsPath,
    },
  );
}

MacosComputerUseM51ProductionLaunchGate _manualTccRunbookGate(
  MacosComputerUseM51ProductionLaunchInputs inputs,
) {
  final checklistGate = _launchChecklistGate(
    id: 'manual_tcc_runbook',
    label: 'Manual TCC runbook',
    field: 'manualTccRunbook',
    inputs: inputs,
    nextAction:
        'Ask the user to complete the manual TCC runbook sign-off and attach it to the M51 launch checklist.',
  );
  final manualTccReady = _manualTccReady(inputs.manualTccReport);
  final ready = checklistGate.ready || manualTccReady;
  return MacosComputerUseM51ProductionLaunchGate(
    id: 'manual_tcc_runbook',
    label: 'Manual TCC runbook',
    status: ready ? 'ready' : checklistGate.status,
    ready: ready,
    nextAction: ready
        ? 'Manual TCC runbook evidence is ready.'
        : checklistGate.nextAction,
    userOperated: true,
    artifactPath: checklistGate.artifactPath ?? inputs.manualTccReportPath,
    details: <String, Object?>{
      ...checklistGate.details,
      'manualTccReportReady': manualTccReady,
      'manualTccReportPath': inputs.manualTccReportPath,
    },
  );
}

MacosComputerUseM51ProductionLaunchGate _m46ElementGroundedLlmGate(
  Map<String, dynamic>? summary,
  String? summaryPath,
) {
  if (summary == null) {
    return const MacosComputerUseM51ProductionLaunchGate(
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
  return MacosComputerUseM51ProductionLaunchGate(
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

MacosComputerUseM51ProductionLaunchGate _m49PrivacyAuditReleasePackGate(
  Map<String, dynamic>? pack,
  String? packPath,
) {
  if (pack == null) {
    return const MacosComputerUseM51ProductionLaunchGate(
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
  return MacosComputerUseM51ProductionLaunchGate(
    id: 'privacy_audit_release_pack',
    label: 'Privacy and audit release pack',
    status: ready ? 'ready' : _statusValue(gate, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M49 privacy and audit release pack is ready.'
        : 'Resolve M49 privacy and audit blockers before production launch.',
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

MacosComputerUseM51ProductionLaunchGate _m50SignedBetaGate(
  Map<String, dynamic>? summary,
  String? summaryPath,
) {
  if (summary == null) {
    return const MacosComputerUseM51ProductionLaunchGate(
      id: 'signed_beta_gate',
      label: 'Signed beta gate',
      status: 'missing',
      ready: false,
      nextAction: 'Run M50 signed beta gate and attach its ready summary.',
      userOperated: true,
    );
  }
  final gate = _mapValue(summary['m50SignedBetaGate']);
  final review = _mapValue(summary['signedBetaReviewSummary']);
  final blockers = _stringList(gate['blockers']);
  final ready =
      summary['schemaName'] == 'macos_computer_use_m50_signed_beta_gate' &&
      summary['ready'] == true &&
      gate['status'] == 'ready' &&
      review['status'] == 'ready_for_signed_beta' &&
      blockers.isEmpty;
  return MacosComputerUseM51ProductionLaunchGate(
    id: 'signed_beta_gate',
    label: 'Signed beta gate',
    status: ready ? 'ready' : _statusValue(summary, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? 'M50 signed beta gate is ready.'
        : 'Resolve M50 signed beta blockers before production launch.',
    userOperated: true,
    artifactPath: summaryPath,
    details: <String, Object?>{
      'reviewStatus': review['status'],
      'blockers': blockers,
      'blockedGateIds': summary['blockedGateIds'],
    },
  );
}

MacosComputerUseM51ProductionLaunchGate _launchChecklistGate({
  required String id,
  required String label,
  required String field,
  required MacosComputerUseM51ProductionLaunchInputs inputs,
  required String nextAction,
}) {
  final checklist = inputs.launchChecklist;
  if (checklist == null) {
    return MacosComputerUseM51ProductionLaunchGate(
      id: id,
      label: label,
      status: 'manual_required',
      ready: false,
      nextAction: nextAction,
      userOperated: true,
      artifactPath: inputs.launchChecklistPath,
    );
  }
  final section = _mapValue(checklist[field]);
  final ready = _readyValue(section);
  return MacosComputerUseM51ProductionLaunchGate(
    id: id,
    label: label,
    status: ready ? 'ready' : _statusValue(section, fallback: 'blocked'),
    ready: ready,
    nextAction: ready
        ? '$label launch evidence is ready.'
        : (section['nextAction'] as String? ?? nextAction),
    userOperated: true,
    artifactPath: inputs.launchChecklistPath,
    details: <String, Object?>{
      'checklistField': field,
      'evidence': section['evidence'],
      'notes': section['notes'],
    },
  );
}

bool _releasePackagingChecksReady(
  Map<String, dynamic>? packaging,
  Set<String> requiredIds,
) {
  if (packaging == null) {
    return false;
  }
  final checks = _listValue(packaging['checks']);
  final readyIds = <String>{};
  for (final check in checks) {
    if (check is! Map || check['ok'] != true) {
      continue;
    }
    readyIds.add('${check['id']}');
  }
  return readyIds.containsAll(requiredIds);
}

bool _manualTccReady(Map<String, dynamic>? report) {
  if (report == null) {
    return false;
  }
  if (report['schemaName'] == 'macos_computer_use_manual_tcc_report_summary') {
    return report['ready'] == true || report['status'] == 'ready';
  }
  final gate = _mapValue(report['releaseRuntimeSignoffGate']);
  final blockers = _stringList(gate['blockers']);
  return gate['status'] == 'ready' && blockers.isEmpty;
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
