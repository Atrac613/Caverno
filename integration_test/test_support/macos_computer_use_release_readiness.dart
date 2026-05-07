import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_setup.dart';

import 'macos_computer_use_canary_history.dart';
import 'macos_computer_use_manual_tcc_report.dart';

class ReleaseReadinessGate {
  const ReleaseReadinessGate({
    required this.id,
    required this.label,
    required this.status,
    required this.ready,
    required this.nextAction,
    this.artifactPath,
    this.details = const <String, Object?>{},
  });

  final String id;
  final String label;
  final String status;
  final bool ready;
  final String nextAction;
  final String? artifactPath;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'status': status,
      'ready': ready,
      'nextAction': nextAction,
      'artifactPath': artifactPath,
      'details': details,
    };
  }
}

class ReleaseReadinessSummary {
  const ReleaseReadinessSummary({
    required this.status,
    required this.ready,
    required this.gates,
  });

  final String status;
  final bool ready;
  final List<ReleaseReadinessGate> gates;

  List<ReleaseReadinessGate> get blockedGates =>
      gates.where((gate) => !gate.ready).toList(growable: false);

  List<ReleaseReadinessGate> get readyGates =>
      gates.where((gate) => gate.ready).toList(growable: false);

  Map<String, Object?> get prReviewSummary {
    final userOperated = MacosComputerUseMvpGuidance.userOperatedEvidenceIds
        .toSet();
    final readyGateIds = readyGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final blockedGateIds = blockedGates
        .map((gate) => gate.id)
        .toList(growable: false);
    final pendingUserOperatedEvidenceIds = blockedGateIds
        .where(userOperated.contains)
        .toList(growable: false);
    final pendingAutomationSafeEvidenceIds = blockedGateIds
        .where((id) => !userOperated.contains(id))
        .toList(growable: false);
    return <String, Object?>{
      'status': ready ? 'ready_for_release_signoff' : 'blocked_gates_present',
      'readyGateIds': readyGateIds,
      'blockedGateIds': blockedGateIds,
      'pendingUserOperatedEvidenceIds': pendingUserOperatedEvidenceIds,
      'pendingAutomationSafeEvidenceIds': pendingAutomationSafeEvidenceIds,
      'operationBoundarySummary':
          'Release readiness reads reports only; TCC grants and desktop actions remain user-operated.',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_release_readiness',
      'schemaVersion': 1,
      'automationBoundary': 'read_reports_only',
      'status': status,
      'ready': ready,
      'readyGateIds': readyGates.map((gate) => gate.id).toList(growable: false),
      'blockedGateIds': blockedGates
          .map((gate) => gate.id)
          .toList(growable: false),
      'prReviewSummary': prReviewSummary,
      'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final review = prReviewSummary;
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use Release Readiness')
      ..writeln()
      ..writeln('- Automation boundary: read reports only')
      ..writeln('- Status: $status')
      ..writeln('- Ready: $ready')
      ..writeln(
        '- Blocked gates: ${blockedGates.isEmpty ? 'none' : blockedGates.map((gate) => gate.id).join(', ')}',
      )
      ..writeln(
        '- Ready gates: ${readyGates.map((gate) => gate.id).join(', ')}',
      )
      ..writeln();

    buffer
      ..writeln('## PR Review Summary')
      ..writeln()
      ..writeln('- Status: ${review['status']}')
      ..writeln(
        '- Ready gates: ${_joinedOrNone(_stringList(review['readyGateIds']))}',
      )
      ..writeln(
        '- Blocked gates: ${_joinedOrNone(_stringList(review['blockedGateIds']))}',
      )
      ..writeln(
        '- Pending user-operated evidence: ${_joinedOrNone(_stringList(review['pendingUserOperatedEvidenceIds']))}',
      )
      ..writeln(
        '- Pending automation-safe evidence: ${_joinedOrNone(_stringList(review['pendingAutomationSafeEvidenceIds']))}',
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
      ..writeln('| Gate | Status | Ready | Next Action | Artifact |')
      ..writeln('| --- | --- | --- | --- | --- |');

    for (final gate in gates) {
      buffer.writeln(
        '| ${_markdownCell(gate.label)} | ${_markdownCell(gate.status)} | ${gate.ready} | ${_markdownCell(gate.nextAction)} | ${_artifactCell(gate.artifactPath)} |',
      );
    }

    ReleaseReadinessGate? desktopActionGate;
    ReleaseReadinessGate? llmGate;
    for (final gate in gates) {
      if (gate.id == 'desktop_action_canary') {
        desktopActionGate = gate;
      }
      if (gate.id == 'llm_canary') {
        llmGate = gate;
      }
    }

    final desktopActionRuns = desktopActionGate?.details['runs'];
    final desktopActionPhases = _stringList(
      desktopActionGate?.details['expectedPhases'],
    );
    if (desktopActionGate != null &&
        (desktopActionPhases.isNotEmpty ||
            (desktopActionRuns is List && desktopActionRuns.isNotEmpty))) {
      final safeTargetGuidance = _stringList(
        desktopActionGate.details['safeTargetGuidance'],
      );
      buffer
        ..writeln()
        ..writeln('## Desktop Action Evidence')
        ..writeln()
        ..writeln(
          '- Desktop action status: ${_markdownCell(desktopActionGate.status)}',
        )
        ..writeln(
          '- Desktop action runs: ${_markdownCell(desktopActionGate.details['runCount'])}',
        )
        ..writeln(
          '- Desktop action failures: ${_markdownCell(desktopActionGate.details['failed'])}',
        );
      if (desktopActionPhases.isNotEmpty) {
        buffer.writeln(
          '- Expected phases: ${desktopActionPhases.map((phase) => '`${_escapeMarkdownCode(phase)}`').join(', ')}',
        );
      }
      if (safeTargetGuidance.isNotEmpty) {
        buffer.writeln(
          '- Safe target guidance: ${safeTargetGuidance.map(_markdownCell).join('; ')}',
        );
      }
      if (desktopActionRuns is List && desktopActionRuns.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(
            '| Run | Status | Failure Class | Pre Observe | Click | Post Observe | Changed Evidence |',
          )
          ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
        for (final run in desktopActionRuns) {
          if (run is! Map) {
            continue;
          }
          final phaseStatus = run['phaseStatus'];
          final phaseStatusMap = phaseStatus is Map
              ? phaseStatus
              : const <Object?, Object?>{};
          buffer.writeln(
            '| ${_markdownCell(run['name'])} | ${_markdownCell(run['status'])} | ${_markdownCell(run['failureClass'])} | ${_markdownCell(phaseStatusMap['preObserve'])} | ${_markdownCell(phaseStatusMap['click'])} | ${_markdownCell(phaseStatusMap['postObserve'])} | ${_markdownCell(phaseStatusMap['changedEvidence'])} |',
          );
        }
      }
    }

    final mvpEvidenceGate = llmGate?.details['mvpEvidenceGate'];
    if (mvpEvidenceGate is Map && mvpEvidenceGate.isNotEmpty) {
      final blockers = _stringList(mvpEvidenceGate['blockers']);
      final checks = mvpEvidenceGate['checks'];
      final phases = _stringList(
        llmGate?.details['expectedUserOperatedRuntimePhases'],
      );
      buffer
        ..writeln()
        ..writeln('## LLM Evidence Gate')
        ..writeln()
        ..writeln(
          '- MVP evidence gate: ${_markdownCell(mvpEvidenceGate['status'])}',
        )
        ..writeln(
          '- MVP evidence blockers: ${blockers.isEmpty ? 'none' : blockers.join(', ')}',
        );
      if (phases.isNotEmpty) {
        buffer.writeln(
          '- Expected user-operated runtime phases: ${phases.map((phase) => '`${_escapeMarkdownCode(phase)}`').join(', ')}',
        );
      }
      if (checks is List && checks.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('| Check | Status | Next Action |')
          ..writeln('| --- | --- | --- |');
        for (final check in checks) {
          if (check is! Map) {
            continue;
          }
          buffer.writeln(
            '| ${_markdownCell(check['id'])} | ${check['ok'] == true ? 'passed' : 'blocked'} | ${_markdownCell(check['nextAction'])} |',
          );
        }
      }
    }

    return buffer.toString();
  }
}

class ReleaseReadinessInputs {
  const ReleaseReadinessInputs({
    required this.releaseReport,
    required this.releaseReportPath,
    required this.computerUseHistory,
    required this.computerUseHistoryPath,
    required this.desktopActionCanarySummary,
    required this.desktopActionCanarySummaryPath,
    required this.manualTccReport,
    required this.manualTccReportPath,
    required this.llmCanarySummary,
    required this.llmCanarySummaryPath,
  });

  final Map<String, dynamic>? releaseReport;
  final String? releaseReportPath;
  final ComputerUseCanaryHistory? computerUseHistory;
  final String? computerUseHistoryPath;
  final Map<String, dynamic>? desktopActionCanarySummary;
  final String? desktopActionCanarySummaryPath;
  final ManualTccReportSummary? manualTccReport;
  final String? manualTccReportPath;
  final Map<String, dynamic>? llmCanarySummary;
  final String? llmCanarySummaryPath;
}

ReleaseReadinessSummary buildReleaseReadinessSummary(
  ReleaseReadinessInputs inputs,
) {
  final gates = <ReleaseReadinessGate>[
    _releaseArtifactGate(inputs.releaseReport, inputs.releaseReportPath),
    _computerUseCanaryGate(
      inputs.computerUseHistory,
      inputs.computerUseHistoryPath,
    ),
    _desktopActionCanaryGate(
      inputs.desktopActionCanarySummary,
      inputs.desktopActionCanarySummaryPath,
    ),
    _manualTccGate(inputs.manualTccReport, inputs.manualTccReportPath),
    _llmCanaryGate(inputs.llmCanarySummary, inputs.llmCanarySummaryPath),
  ];
  final ready = gates.every((gate) => gate.ready);
  return ReleaseReadinessSummary(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    gates: List<ReleaseReadinessGate>.unmodifiable(gates),
  );
}

ReleaseReadinessInputs readReleaseReadinessInputs({
  required Directory reportRoot,
  String? releaseReportPath,
  String? computerUseHistoryPath,
  String? desktopActionCanarySummaryPath,
  String? manualTccReportPath,
  String? llmCanarySummaryPath,
  int computerUseHistoryLimit = 10,
}) {
  final releaseReportFile = releaseReportPath == null
      ? discoverLatestReleaseReport(reportRoot)
      : File(releaseReportPath);
  final manualTccReportFile = manualTccReportPath == null
      ? discoverLatestManualTccReport(reportRoot)
      : File(manualTccReportPath);
  final desktopActionCanarySummaryFile = desktopActionCanarySummaryPath == null
      ? discoverLatestDesktopActionCanarySummary(reportRoot)
      : File(desktopActionCanarySummaryPath);
  final llmCanarySummaryFile = llmCanarySummaryPath == null
      ? discoverLatestLlmCanarySummary(reportRoot)
      : File(llmCanarySummaryPath);
  final historyFile = computerUseHistoryPath == null
      ? File('${reportRoot.path}/macos_computer_use_canary_history.json')
      : File(computerUseHistoryPath);

  return ReleaseReadinessInputs(
    releaseReport: _readJsonObject(releaseReportFile),
    releaseReportPath: releaseReportFile?.path,
    computerUseHistory: _readComputerUseHistory(
      historyFile,
      reportRoot,
      computerUseHistoryLimit,
    ),
    computerUseHistoryPath: historyFile.path,
    desktopActionCanarySummary: _readJsonObject(desktopActionCanarySummaryFile),
    desktopActionCanarySummaryPath: desktopActionCanarySummaryFile?.path,
    manualTccReport: manualTccReportFile == null
        ? null
        : _readManualTccSummaryOrReport(manualTccReportFile),
    manualTccReportPath: manualTccReportFile?.path,
    llmCanarySummary: _readJsonObject(llmCanarySummaryFile),
    llmCanarySummaryPath: llmCanarySummaryFile?.path,
  );
}

File? discoverLatestReleaseReport(Directory reportRoot) {
  return _latestJsonMatching(reportRoot, (json) {
    return json.containsKey('releaseSignoffGate');
  });
}

File? discoverLatestManualTccReport(Directory reportRoot) {
  final candidates = <_ManualTccCandidate>[];
  for (final file in _jsonFiles(reportRoot)) {
    final summary = _readManualTccSummaryOrReport(file);
    if (summary != null) {
      candidates.add(
        _ManualTccCandidate(
          file: file,
          ready: summary.ready,
          modifiedAt: file.statSync().modified,
        ),
      );
    }
  }
  candidates.sort((left, right) {
    if (left.ready != right.ready) {
      return left.ready ? 1 : -1;
    }
    final modifiedCompare = left.modifiedAt.compareTo(right.modifiedAt);
    if (modifiedCompare != 0) {
      return modifiedCompare;
    }
    return left.file.path.compareTo(right.file.path);
  });
  return candidates.isEmpty ? null : candidates.last.file;
}

File? discoverLatestDesktopActionCanarySummary(Directory reportRoot) {
  final candidates =
      _jsonFiles(reportRoot)
          .where(
            (file) =>
                _basename(
                  file.parent.path,
                ).startsWith('macos_computer_use_desktop_action_canary_') &&
                _basename(file.path) == 'canary_summary.json',
          )
          .toList(growable: false)
        ..sort((left, right) => left.parent.path.compareTo(right.parent.path));
  return candidates.isEmpty ? null : candidates.last;
}

File? discoverLatestLlmCanarySummary(Directory reportRoot) {
  final visionCandidates =
      _jsonFiles(reportRoot)
          .where((file) {
            final parent = _basename(file.parent.path);
            return _basename(file.path) == 'canary_summary.json' &&
                parent.startsWith(
                  'macos_computer_use_mvp_fixture_vision_llm_canary_',
                );
          })
          .toList(growable: false)
        ..sort((left, right) => left.parent.path.compareTo(right.parent.path));
  if (visionCandidates.isNotEmpty) {
    return visionCandidates.last;
  }

  final aggregateCandidates =
      _jsonFiles(reportRoot)
          .where((file) {
            final parent = _basename(file.parent.path);
            return _basename(file.path) == 'canary_summary.json' &&
                parent.startsWith('macos_computer_use_mvp_fixture_llm_canary_');
          })
          .toList(growable: false)
        ..sort((left, right) => left.parent.path.compareTo(right.parent.path));
  if (aggregateCandidates.isNotEmpty) {
    return aggregateCandidates.last;
  }

  final computerUseCandidates =
      _jsonFiles(reportRoot)
          .where((file) {
            final parent = _basename(file.parent.path);
            return _basename(file.path) == 'canary_summary.json' &&
                parent.startsWith('macos_computer_use_llm_decision_canary_');
          })
          .toList(growable: false)
        ..sort((left, right) => left.parent.path.compareTo(right.parent.path));
  if (computerUseCandidates.isNotEmpty) {
    final mvpFixtureCandidates = computerUseCandidates
        .where((file) {
          final json = _readJsonObject(file);
          final scenario = json?['scenario'] as String?;
          return scenario != null && scenario.startsWith('mvp-fixture');
        })
        .toList(growable: false);
    if (mvpFixtureCandidates.isNotEmpty) {
      return mvpFixtureCandidates.last;
    }
    return computerUseCandidates.last;
  }

  final legacyCandidates =
      _jsonFiles(reportRoot)
          .where(
            (file) =>
                _basename(file.path) == 'canary_summary.json' &&
                _basename(
                  file.parent.path,
                ).startsWith('plan_mode_ping_cli_canary_'),
          )
          .toList(growable: false)
        ..sort((left, right) => left.parent.path.compareTo(right.parent.path));
  return legacyCandidates.isEmpty ? null : legacyCandidates.last;
}

ReleaseReadinessGate _releaseArtifactGate(
  Map<String, dynamic>? releaseReport,
  String? reportPath,
) {
  if (releaseReport == null) {
    return const ReleaseReadinessGate(
      id: 'release_artifact',
      label: 'Release artifact',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the M7 release artifact sign-off and provide its report.',
    );
  }

  final gate = _mapValue(releaseReport['releaseSignoffGate']);
  final blockers = _stringList(gate['blockers']);
  final status = gate['status'] as String? ?? 'missing';
  final ready = status == 'ready' && blockers.isEmpty;
  return ReleaseReadinessGate(
    id: 'release_artifact',
    label: 'Release artifact',
    status: status,
    ready: ready,
    nextAction: ready
        ? 'Release artifact gate is ready.'
        : (gate['nextAction'] as String? ??
              'Resolve release artifact blockers and rerun M7 sign-off.'),
    artifactPath: reportPath,
    details: <String, Object?>{'blockers': blockers},
  );
}

ReleaseReadinessGate _computerUseCanaryGate(
  ComputerUseCanaryHistory? history,
  String? historyPath,
) {
  final latest = history?.latest;
  if (latest == null) {
    return const ReleaseReadinessGate(
      id: 'computer_use_canary',
      label: 'Computer Use runtime canary',
      status: 'missing',
      ready: false,
      nextAction: 'Run the Computer Use live canary and generate history.',
    );
  }

  final ready = latest.stable && latest.runCount > 0;
  return ReleaseReadinessGate(
    id: 'computer_use_canary',
    label: 'Computer Use runtime canary',
    status: ready ? 'stable' : 'unstable',
    ready: ready,
    nextAction: ready
        ? 'Computer Use runtime canary is stable.'
        : 'Investigate the latest Computer Use failure class and rerun the canary.',
    artifactPath: historyPath ?? latest.summaryPath,
    details: <String, Object?>{
      'latestRun': latest.name,
      'runCount': latest.runCount,
      'passRate': latest.passRate,
      'failureClasses': latest.failureClasses,
      'overlayForegroundCanary': latest.overlayForegroundCanary,
      'overlaySmokeStatus': latest.overlaySmokeStatus,
      'helperProcessPolicy': latest.helperProcessPolicy,
      'manualTccHandoff': latest.manualTccHandoff,
    },
  );
}

ReleaseReadinessGate _manualTccGate(
  ManualTccReportSummary? manualTccReport,
  String? reportPath,
) {
  if (manualTccReport == null) {
    return const ReleaseReadinessGate(
      id: 'manual_tcc',
      label: 'Manual TCC sign-off',
      status: 'manual_required',
      ready: false,
      nextAction: MacosComputerUseMvpGuidance.manualTccNextAction,
    );
  }

  return ReleaseReadinessGate(
    id: 'manual_tcc',
    label: 'Manual TCC sign-off',
    status: manualTccReport.status,
    ready: manualTccReport.ready,
    nextAction: manualTccReport.ready
        ? 'Manual TCC sign-off is ready.'
        : (manualTccReport.nextAction ??
              'Ask the user to complete the manual TCC sign-off steps.'),
    artifactPath: reportPath ?? manualTccReport.reportPath,
    details: <String, Object?>{
      'blockers': manualTccReport.blockers,
      'failureClasses': manualTccReport.failureClasses,
      'failedChecks': manualTccReport.failedChecks
          .map((check) => check.toJson())
          .toList(growable: false),
      'appPath': manualTccReport.appPath,
      'helperPath': manualTccReport.helperPath,
    },
  );
}

ReleaseReadinessGate _desktopActionCanaryGate(
  Map<String, dynamic>? summary,
  String? summaryPath,
) {
  if (summary == null) {
    return const ReleaseReadinessGate(
      id: 'desktop_action_canary',
      label: 'Desktop action canary',
      status: 'manual_required',
      ready: false,
      nextAction: MacosComputerUseMvpGuidance.desktopActionCanaryNextAction,
    );
  }

  final runCount = _intValue(summary['runCount']);
  final failed = _intValue(summary['failed']);
  final stable = summary['stable'] == true;
  final ready = runCount > 0 && failed == 0 && stable;
  return ReleaseReadinessGate(
    id: 'desktop_action_canary',
    label: 'Desktop action canary',
    status: ready ? 'passed' : 'blocked',
    ready: ready,
    nextAction: ready
        ? 'Desktop action canary is passing.'
        : MacosComputerUseMvpGuidance.desktopActionCanaryNextAction,
    artifactPath: summaryPath,
    details: <String, Object?>{
      'purpose': summary['purpose'],
      'tccBoundary': summary['tccBoundary'],
      'runCount': runCount,
      'failed': failed,
      'failureClasses': summary['failureClasses'],
      'expectedPhases': summary['expectedPhases'],
      'safeTargetGuidance': summary['safeTargetGuidance'],
      'failureClassGuidance': summary['failureClassGuidance'],
      'runs': summary['runs'],
    },
  );
}

ReleaseReadinessGate _llmCanaryGate(
  Map<String, dynamic>? llmSummary,
  String? summaryPath,
) {
  if (llmSummary == null) {
    return const ReleaseReadinessGate(
      id: 'llm_canary',
      label: 'Computer Use LLM decision canary',
      status: 'missing',
      ready: false,
      nextAction:
          'Run the Computer Use LLM decision canary and provide its summary.',
    );
  }

  final purpose = llmSummary['purpose'] as String?;
  final runCount = _intValue(llmSummary['runCount']);
  final failed = _intValue(llmSummary['failedCount'] ?? llmSummary['failed']);
  final mvpEvidenceGate = _mapValue(llmSummary['mvpEvidenceGate']);
  final hasMvpEvidenceGate = mvpEvidenceGate.isNotEmpty;
  final mvpEvidenceReady =
      !hasMvpEvidenceGate || mvpEvidenceGate['ready'] == true;
  final ready = runCount > 0 && failed == 0 && mvpEvidenceReady;
  final isComputerUseDecision = purpose == 'computer_use_llm_vision_decision';
  final isMvpFixture = purpose == 'computer_use_mvp_fixture_llm_canary';
  final isFixtureVision =
      purpose == 'computer_use_mvp_fixture_vision_llm_canary';
  return ReleaseReadinessGate(
    id: 'llm_canary',
    label: isComputerUseDecision || isMvpFixture || isFixtureVision
        ? 'Computer Use LLM decision canary'
        : 'LLM tool-loop canary',
    status: ready ? 'passed' : 'blocked',
    ready: ready,
    nextAction: ready
        ? 'Computer Use LLM decision canary is passing.'
        : 'Inspect the LLM canary failure classes and rerun after fixes.',
    artifactPath: summaryPath,
    details: <String, Object?>{
      'purpose': purpose,
      'runCount': runCount,
      'failed': failed,
      'failureClassCounts':
          llmSummary['failureClassCounts'] ?? llmSummary['failureClasses'],
      'scenario': llmSummary['scenario'],
      'scenarioCount': llmSummary['scenarioCount'],
      'scenarios': llmSummary['scenarios'],
      'mvpEvidenceGate': mvpEvidenceGate,
      'expectedUserOperatedRuntimePhases':
          llmSummary['expectedUserOperatedRuntimePhases'],
      'fixtureApp': llmSummary['fixtureApp'],
      'visionDecision': llmSummary['visionDecision'],
      'safeTargetReasoning': llmSummary['safeTargetReasoning'],
      'visibleFixtureWindow': llmSummary['visibleFixtureWindow'],
      'requiresUserClick': llmSummary['requiresUserClick'],
      'requiresUserTextInput': llmSummary['requiresUserTextInput'],
      'selectedTarget': llmSummary['selectedTarget'],
      'typeConfirmTarget': llmSummary['typeConfirmTarget'],
      'refusedTargets': llmSummary['refusedTargets'],
      'screenshotPath': llmSummary['screenshotPath'],
      'desktopActionBoundary': llmSummary['desktopActionBoundary'],
    },
  );
}

ComputerUseCanaryHistory? _readComputerUseHistory(
  File historyFile,
  Directory reportRoot,
  int limit,
) {
  if (!historyFile.existsSync()) {
    return buildComputerUseCanaryHistory(reportRoot, limit: limit);
  }
  final json = _readJsonObject(historyFile);
  if (json == null) {
    return buildComputerUseCanaryHistory(reportRoot, limit: limit);
  }
  final entries = (json['entries'] as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(_historyEntryFromJson)
      .toList(growable: false);
  return ComputerUseCanaryHistory(
    entries: List<ComputerUseCanaryHistoryEntry>.unmodifiable(entries),
    limit: _intValue(json['limit']),
  );
}

ComputerUseCanaryHistoryEntry _historyEntryFromJson(Map<String, dynamic> json) {
  final failureClasses = <String, int>{};
  final rawFailureClasses = json['failureClasses'];
  if (rawFailureClasses is Map<String, dynamic>) {
    for (final entry in rawFailureClasses.entries) {
      failureClasses[entry.key] = _intValue(entry.value);
    }
  }
  return ComputerUseCanaryHistoryEntry(
    name: json['name'] as String? ?? 'unknown',
    directory: json['directory'] as String? ?? '',
    summaryPath: json['summaryPath'] as String? ?? '',
    preset: json['preset'] as String? ?? 'unknown',
    tccBoundary: json['tccBoundary'] as String? ?? 'unknown',
    overlayForegroundCanary: json['overlayForegroundCanary'] == true,
    overlaySmokeStatus: json['overlaySmokeStatus'] as String? ?? 'not_run',
    helperProcessPolicy: Map<String, Object?>.unmodifiable(
      _mapValue(json['helperProcessPolicy']),
    ),
    manualTccHandoff: Map<String, Object?>.unmodifiable(
      _mapValue(json['manualTccHandoff']),
    ),
    stabilityMode: json['stabilityMode'] == true,
    stable: json['stable'] == true,
    runCount: _intValue(json['runCount']),
    passed: _intValue(json['passed']),
    failed: _intValue(json['failed']),
    passRate: _doubleValue(json['passRate']),
    failureClasses: Map<String, int>.unmodifiable(failureClasses),
    modifiedAt:
        DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

ManualTccReportSummary? _readManualTccSummaryOrReport(File file) {
  final json = _readJsonObject(file);
  if (json == null) {
    return null;
  }
  if (json['schemaName'] == 'macos_computer_use_manual_tcc_report_summary') {
    return _manualTccSummaryFromJson(json, file.path);
  }
  if (json.containsKey('releaseRuntimeSignoffGate')) {
    return buildManualTccReportSummary(json, reportPath: file.path);
  }
  return null;
}

ManualTccReportSummary _manualTccSummaryFromJson(
  Map<String, dynamic> json,
  String path,
) {
  final checks = (json['checks'] as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(
        (check) => ManualTccCheckSummary(
          id: check['id'] as String? ?? 'unknown',
          label: check['label'] as String? ?? 'unknown',
          status: check['status'] as String? ?? 'unknown',
          ok: check['ok'] == true,
          nextAction: check['nextAction'] as String?,
        ),
      )
      .toList(growable: false);
  return ManualTccReportSummary(
    reportPath: json['reportPath'] as String? ?? path,
    status: json['status'] as String? ?? 'missing',
    ready: json['ready'] == true,
    blockers: List<String>.unmodifiable(_stringList(json['blockers'])),
    failureClasses: List<String>.unmodifiable(
      _stringList(json['failureClasses']),
    ),
    appPath: json['appPath'] as String?,
    helperPath: json['helperPath'] as String?,
    nextAction: json['nextAction'] as String?,
    checks: List<ManualTccCheckSummary>.unmodifiable(checks),
    captureFailureClasses: List<String>.unmodifiable(
      _stringList(json['captureFailureClasses']),
    ),
    captureNextAction: json['captureNextAction'] as String?,
  );
}

File? _latestJsonMatching(
  Directory reportRoot,
  bool Function(Map<String, dynamic> json) matches,
) {
  final candidates = <File>[];
  for (final file in _jsonFiles(reportRoot)) {
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

class _ManualTccCandidate {
  const _ManualTccCandidate({
    required this.file,
    required this.ready,
    required this.modifiedAt,
  });

  final File file;
  final bool ready;
  final DateTime modifiedAt;
}

List<File> _jsonFiles(Directory root) {
  if (!root.existsSync()) {
    return const <File>[];
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList(growable: false);
}

Map<String, dynamic>? _readJsonObject(File? file) {
  if (file == null || !file.existsSync()) {
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
  return value is Map<String, dynamic> ? value : const <String, dynamic>{};
}

List<String> _stringList(Object? value) {
  if (value is! List<dynamic>) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

double _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

String _artifactCell(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '-';
  }
  return '`${_escapeMarkdownCode(value)}`';
}

String _markdownCell(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return '-';
  }
  return text.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}

String _joinedOrNone(List<String> values) {
  if (values.isEmpty) {
    return 'none';
  }
  return values.join(', ');
}

String _escapeMarkdownCode(String value) {
  return value.replaceAll('`', r'\`');
}

String _basename(String path) {
  final segments = path.split(Platform.pathSeparator);
  for (final segment in segments.reversed) {
    if (segment.isNotEmpty) {
      return segment;
    }
  }
  return path;
}
