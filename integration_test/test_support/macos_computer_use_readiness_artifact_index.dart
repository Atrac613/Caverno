import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_setup.dart';

class ReadinessArtifactEntry {
  const ReadinessArtifactEntry({
    required this.id,
    required this.label,
    required this.path,
    required this.exists,
    this.status,
    this.nextAction,
    this.details = const <String, Object?>{},
  });

  final String id;
  final String label;
  final String path;
  final bool exists;
  final String? status;
  final String? nextAction;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'path': path,
      'exists': exists,
      if (status != null) 'status': status,
      if (nextAction != null) 'nextAction': nextAction,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

class ReadinessArtifactIndex {
  const ReadinessArtifactIndex({
    required this.reportRoot,
    required this.entries,
    required this.mvpFinalSignoffRehearsal,
  });

  final String reportRoot;
  final List<ReadinessArtifactEntry> entries;
  final ReadinessFinalSignoffRehearsal mvpFinalSignoffRehearsal;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_readiness_artifact_index',
      'schemaVersion': 1,
      'reportRoot': reportRoot,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'mvpFinalSignoffRehearsal': mvpFinalSignoffRehearsal.toJson(),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use Readiness Artifact Index')
      ..writeln()
      ..writeln('- Report root: `$reportRoot`')
      ..writeln()
      ..writeln('| Artifact | Exists | Status | Path |')
      ..writeln('| --- | --- | --- | --- |');
    for (final entry in entries) {
      buffer.writeln(
        '| ${_markdownCell(entry.label)} | ${entry.exists} | ${_markdownCell(entry.status ?? (entry.exists ? 'present' : 'missing'))} | `${_escapeMarkdownCode(entry.path)}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## MVP Final Sign-Off Rehearsal')
      ..writeln()
      ..writeln('- Ready: ${mvpFinalSignoffRehearsal.ready}')
      ..writeln(
        '- Missing required artifacts: ${mvpFinalSignoffRehearsal.missingArtifactIds.isEmpty ? 'none' : mvpFinalSignoffRehearsal.missingArtifactIds.join(', ')}',
      );
    buffer
      ..writeln()
      ..writeln('## PR Review Summary')
      ..writeln()
      ..writeln('- Status: ${mvpFinalSignoffRehearsal.prReviewSummary.status}')
      ..writeln(
        '- Ready artifacts: ${_joinedOrNone(mvpFinalSignoffRehearsal.prReviewSummary.readyArtifactIds)}',
      )
      ..writeln(
        '- Missing artifacts: ${_joinedOrNone(mvpFinalSignoffRehearsal.prReviewSummary.missingArtifactIds)}',
      )
      ..writeln(
        '- Pending user-operated evidence: ${_joinedOrNone(mvpFinalSignoffRehearsal.prReviewSummary.pendingUserOperatedEvidenceIds)}',
      )
      ..writeln(
        '- Pending automation-safe evidence: ${_joinedOrNone(mvpFinalSignoffRehearsal.prReviewSummary.pendingAutomationSafeEvidenceIds)}',
      )
      ..writeln(
        '- Boundary: ${mvpFinalSignoffRehearsal.prReviewSummary.operationBoundarySummary}',
      )
      ..writeln(
        '- Report-only preflight command: `${_escapeMarkdownCode(mvpFinalSignoffRehearsal.reportOnlyPreflightCommand)}`',
      );
    ReadinessArtifactEntry? m15Entry;
    for (final entry in entries) {
      if (entry.id == 'm15_action_proposal_handoff') {
        m15Entry = entry;
        break;
      }
    }
    if (m15Entry != null && m15Entry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M15 Action Proposal Review Targets')
        ..writeln()
        ..writeln(
          '- Exact text candidates: ${m15Entry.details['exactTextCandidateCount'] ?? 0}',
        )
        ..writeln(
          '- Text-entry targets: ${m15Entry.details['textEntryTargetCount'] ?? 0}',
        )
        ..writeln(
          '- Public-action targets: ${m15Entry.details['publicActionTargetCount'] ?? 0}',
        );
    }
    buffer
      ..writeln()
      ..writeln('Operation boundary:')
      ..writeln()
      ..writeln(
        '- `tccGrants`: ${mvpFinalSignoffRehearsal.operationBoundary['tccGrants']}',
      )
      ..writeln(
        '- `desktopActions`: ${mvpFinalSignoffRehearsal.operationBoundary['desktopActions']}',
      )
      ..writeln(
        '- `inputSmokeRequiresArming`: ${mvpFinalSignoffRehearsal.operationBoundary['inputSmokeRequiresArming']}',
      )
      ..writeln(
        '- `systemAudioSmokeRequiresArming`: ${mvpFinalSignoffRehearsal.operationBoundary['systemAudioSmokeRequiresArming']}',
      );
    if (mvpFinalSignoffRehearsal.finalAggregationCommand != null) {
      buffer
        ..writeln()
        ..writeln('Final MVP aggregation command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.finalAggregationCommand)
        ..writeln('```');
    }
    buffer
      ..writeln()
      ..writeln('| Required Artifact | Present | Path |')
      ..writeln('| --- | --- | --- |');
    for (final artifact in mvpFinalSignoffRehearsal.requiredArtifacts) {
      buffer.writeln(
        '| ${_markdownCell(artifact.label)} | ${artifact.exists} | `${_escapeMarkdownCode(artifact.path)}` |',
      );
    }
    if (mvpFinalSignoffRehearsal.missingArtifactActions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Missing Required Artifact Checklist')
        ..writeln()
        ..writeln('| Artifact | Next Action |')
        ..writeln('| --- | --- |');
      for (final action in mvpFinalSignoffRehearsal.missingArtifactActions) {
        buffer.writeln(
          '| `${_escapeMarkdownCode(action.artifactId)}` | ${_markdownCell(action.nextAction)} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('## MVP Rehearsal Next Actions')
      ..writeln();
    if (mvpFinalSignoffRehearsal.nextActions.isEmpty) {
      buffer.writeln(
        '- All required input evidence is present. Run final MVP sign-off aggregation.',
      );
    } else {
      for (final action in mvpFinalSignoffRehearsal.nextActions) {
        buffer.writeln('- $action');
      }
    }
    return buffer.toString();
  }
}

class ReadinessFinalSignoffRehearsal {
  const ReadinessFinalSignoffRehearsal({
    required this.ready,
    required this.requiredArtifacts,
    required this.missingArtifactIds,
    required this.missingArtifactActions,
    required this.prReviewSummary,
    required this.nextActions,
    required this.finalAggregationCommand,
    required this.reportOnlyPreflightCommand,
    this.operationBoundary = MacosComputerUseOperationBoundary.values,
  });

  final bool ready;
  final List<ReadinessArtifactEntry> requiredArtifacts;
  final List<String> missingArtifactIds;
  final List<ReadinessMissingArtifactAction> missingArtifactActions;
  final ReadinessPrReviewSummary prReviewSummary;
  final List<String> nextActions;
  final String? finalAggregationCommand;
  final String reportOnlyPreflightCommand;
  final Map<String, Object?> operationBoundary;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'requiredArtifacts': requiredArtifacts
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'missingArtifactIds': missingArtifactIds,
      'missingArtifactActions': missingArtifactActions
          .map((action) => action.toJson())
          .toList(growable: false),
      'prReviewSummary': prReviewSummary.toJson(),
      'nextActions': nextActions,
      'finalAggregationCommand': finalAggregationCommand,
      'reportOnlyPreflightCommand': reportOnlyPreflightCommand,
      'operationBoundary': operationBoundary,
    };
  }
}

class ReadinessMissingArtifactAction {
  const ReadinessMissingArtifactAction({
    required this.artifactId,
    required this.label,
    required this.nextAction,
  });

  final String artifactId;
  final String label;
  final String nextAction;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'artifactId': artifactId,
      'label': label,
      'nextAction': nextAction,
    };
  }
}

class ReadinessPrReviewSummary {
  const ReadinessPrReviewSummary({
    required this.status,
    required this.readyArtifactIds,
    required this.missingArtifactIds,
    required this.pendingUserOperatedEvidenceIds,
    required this.pendingAutomationSafeEvidenceIds,
    required this.operationBoundarySummary,
  });

  final String status;
  final List<String> readyArtifactIds;
  final List<String> missingArtifactIds;
  final List<String> pendingUserOperatedEvidenceIds;
  final List<String> pendingAutomationSafeEvidenceIds;
  final String operationBoundarySummary;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'readyArtifactIds': readyArtifactIds,
      'missingArtifactIds': missingArtifactIds,
      'pendingUserOperatedEvidenceIds': pendingUserOperatedEvidenceIds,
      'pendingAutomationSafeEvidenceIds': pendingAutomationSafeEvidenceIds,
      'operationBoundarySummary': operationBoundarySummary,
    };
  }
}

ReadinessArtifactIndex buildReadinessArtifactIndex(Directory reportRoot) {
  final entries = <ReadinessArtifactEntry>[
    _entry(
      'release_artifact',
      'M7 release artifact report',
      '${reportRoot.path}/macos_computer_use_release_artifact_signoff.json',
    ),
    _entry(
      'canary_history',
      'Computer Use canary history',
      '${reportRoot.path}/macos_computer_use_canary_history.json',
    ),
    _entry(
      'readiness_ci_json',
      'CI readiness JSON',
      '${reportRoot.path}/macos_computer_use_release_readiness_ci.json',
    ),
    _entry(
      'readiness_ci_md',
      'CI readiness Markdown',
      '${reportRoot.path}/macos_computer_use_release_readiness_ci.md',
    ),
    _entry(
      'readiness_signoff_json',
      'Sign-off readiness JSON',
      '${reportRoot.path}/macos_computer_use_release_readiness_signoff.json',
    ),
    _entry(
      'readiness_signoff_md',
      'Sign-off readiness Markdown',
      '${reportRoot.path}/macos_computer_use_release_readiness_signoff.md',
    ),
    _latestEntry(
      'manual_tcc',
      'Latest manual TCC evidence',
      reportRoot,
      (json) =>
          json['schemaName'] ==
              'macos_computer_use_manual_tcc_report_summary' ||
          json.containsKey('releaseRuntimeSignoffGate'),
    ),
    _latestEntry(
      'desktop_action_canary',
      'Latest desktop action canary summary',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_desktop_action_canary_summary',
      parentPrefix: 'macos_computer_use_desktop_action_canary_',
      fileName: 'canary_summary.json',
    ),
    _latestLlmCanaryEntry(
      'llm_canary',
      'Latest LLM canary summary',
      reportRoot,
    ),
    _latestEntry(
      'mvp_llm_readiness',
      'Latest MVP LLM readiness summary',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_mvp_llm_readiness_summary',
      parentPrefix: 'macos_computer_use_mvp_llm_readiness_',
      fileName: 'mvp_llm_readiness_summary.json',
    ),
    _latestEntry(
      'mvp_demo_readiness',
      'Latest MVP demo readiness summary',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_mvp_demo_readiness_summary',
      parentPrefix: 'macos_computer_use_mvp_demo_readiness_',
      fileName: 'mvp_demo_readiness_summary.json',
    ),
    _latestEntry(
      'm15_action_proposal_handoff',
      'Latest M15 action proposal handoff',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_m15_action_proposal_handoff',
      parentPrefix: 'macos_computer_use_m15_action_proposal_handoff_',
      fileName: 'action_proposal_handoff.json',
      status: _m15ActionProposalStatus,
      nextAction: _m15ActionProposalNextAction,
      details: _m15ActionProposalDetails,
    ),
  ];
  return ReadinessArtifactIndex(
    reportRoot: reportRoot.path,
    entries: List<ReadinessArtifactEntry>.unmodifiable(entries),
    mvpFinalSignoffRehearsal: _mvpFinalSignoffRehearsal(reportRoot, entries),
  );
}

ReadinessFinalSignoffRehearsal _mvpFinalSignoffRehearsal(
  Directory reportRoot,
  List<ReadinessArtifactEntry> entries,
) {
  final byId = <String, ReadinessArtifactEntry>{
    for (final entry in entries) entry.id: entry,
  };
  final requiredIds = MacosComputerUseMvpGuidance.requiredEvidenceIds;
  final requiredArtifacts = requiredIds
      .map((id) => byId[id])
      .whereType<ReadinessArtifactEntry>()
      .toList(growable: false);
  final missingArtifactIds = requiredArtifacts
      .where((entry) => !entry.exists)
      .map((entry) => entry.id)
      .toList(growable: false);
  final readyArtifactIds = requiredArtifacts
      .where((entry) => entry.exists)
      .map((entry) => entry.id)
      .toList(growable: false);
  final missingArtifactActions = requiredArtifacts
      .where((entry) => !entry.exists)
      .map(
        (entry) => ReadinessMissingArtifactAction(
          artifactId: entry.id,
          label: entry.label,
          nextAction: _mvpMissingArtifactNextAction(entry.id),
        ),
      )
      .toList(growable: false);
  final nextActions = missingArtifactActions
      .map((action) => action.nextAction)
      .toList(growable: false);
  final finalAggregationCommand = missingArtifactIds.isEmpty
      ? _mvpFinalAggregationCommand(reportRoot, byId)
      : null;
  final prReviewSummary = _mvpPrReviewSummary(
    readyArtifactIds: readyArtifactIds,
    missingArtifactIds: missingArtifactIds,
  );
  return ReadinessFinalSignoffRehearsal(
    ready: missingArtifactIds.isEmpty,
    requiredArtifacts: List<ReadinessArtifactEntry>.unmodifiable(
      requiredArtifacts,
    ),
    missingArtifactIds: List<String>.unmodifiable(missingArtifactIds),
    missingArtifactActions: List<ReadinessMissingArtifactAction>.unmodifiable(
      missingArtifactActions,
    ),
    prReviewSummary: prReviewSummary,
    nextActions: List<String>.unmodifiable(nextActions),
    finalAggregationCommand: finalAggregationCommand,
    reportOnlyPreflightCommand: _mvpReadinessPreflightCommand(reportRoot),
  );
}

ReadinessPrReviewSummary _mvpPrReviewSummary({
  required List<String> readyArtifactIds,
  required List<String> missingArtifactIds,
}) {
  final userOperated = MacosComputerUseMvpGuidance.userOperatedEvidenceIds
      .toSet();
  final pendingUserOperatedEvidenceIds = missingArtifactIds
      .where(userOperated.contains)
      .toList(growable: false);
  final pendingAutomationSafeEvidenceIds = missingArtifactIds
      .where((id) => !userOperated.contains(id))
      .toList(growable: false);
  return ReadinessPrReviewSummary(
    status: missingArtifactIds.isEmpty
        ? 'ready_for_final_aggregation'
        : 'blocked_pending_evidence',
    readyArtifactIds: List<String>.unmodifiable(readyArtifactIds),
    missingArtifactIds: List<String>.unmodifiable(missingArtifactIds),
    pendingUserOperatedEvidenceIds: List<String>.unmodifiable(
      pendingUserOperatedEvidenceIds,
    ),
    pendingAutomationSafeEvidenceIds: List<String>.unmodifiable(
      pendingAutomationSafeEvidenceIds,
    ),
    operationBoundarySummary:
        'TCC grants and desktop actions remain user-operated; report-only checks may be automated.',
  );
}

String _mvpFinalAggregationCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  return <String>[
    'bash',
    'tool/run_macos_computer_use_mvp_signoff.sh',
    '--final-signoff',
    '--root',
    reportRoot.path,
    '--manual-tcc-report',
    entriesById['manual_tcc']?.path ?? '',
    '--desktop-action-canary-summary',
    entriesById['desktop_action_canary']?.path ?? '',
    '--llm-canary-summary',
    entriesById['llm_canary']?.path ?? '',
  ].map(_shellQuote).join(' ');
}

String _mvpReadinessPreflightCommand(Directory reportRoot) {
  return <String>[
    'bash',
    'tool/run_macos_computer_use_mvp_readiness_preflight.sh',
    '--root',
    reportRoot.path,
  ].map(_shellQuote).join(' ');
}

String _mvpMissingArtifactNextAction(String artifactId) {
  return MacosComputerUseMvpGuidance.missingArtifactNextAction(artifactId);
}

Future<ReadinessArtifactIndex> writeReadinessArtifactIndex(
  Directory reportRoot, {
  String? outputJsonPath,
  String? outputMarkdownPath,
}) async {
  reportRoot.createSync(recursive: true);
  final index = buildReadinessArtifactIndex(reportRoot);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_readiness_artifact_index.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_readiness_artifact_index.md',
  );
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(index.toJson()),
  );
  await outputMarkdown.writeAsString(index.toMarkdown());
  return index;
}

ReadinessArtifactEntry _latestLlmCanaryEntry(
  String id,
  String label,
  Directory reportRoot,
) {
  final files = reportRoot.existsSync()
      ? reportRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => _basename(file.path) == 'canary_summary.json')
            .where((file) {
              final parent = _basename(file.parent.path);
              return parent.startsWith(
                    'macos_computer_use_llm_decision_canary_',
                  ) ||
                  parent.startsWith(
                    'macos_computer_use_mvp_fixture_llm_canary_',
                  ) ||
                  parent.startsWith(
                    'macos_computer_use_mvp_fixture_vision_llm_canary_',
                  ) ||
                  parent.startsWith(
                    'macos_computer_use_real_app_observe_canary_',
                  ) ||
                  parent.startsWith('plan_mode_ping_cli_canary_');
            })
            .where((file) {
              final json = _readJsonObject(file);
              return json != null &&
                  json.containsKey('runCount') &&
                  (json.containsKey('passedCount') ||
                      json['schemaName'] ==
                          'macos_computer_use_mvp_fixture_llm_canary_summary' ||
                      json['schemaName'] ==
                          'macos_computer_use_mvp_fixture_vision_llm_canary_summary' ||
                      json['schemaName'] ==
                          'macos_computer_use_real_app_observe_canary_summary');
            })
            .toList(growable: false)
      : <File>[];
  files.sort((left, right) {
    final modifiedCompare = left.statSync().modified.compareTo(
      right.statSync().modified,
    );
    if (modifiedCompare != 0) {
      return modifiedCompare;
    }
    return left.path.compareTo(right.path);
  });

  final computerUseFiles = files
      .where((file) {
        return _basename(
              file.parent.path,
            ).startsWith('macos_computer_use_llm_decision_canary_') ||
            _basename(
              file.parent.path,
            ).startsWith('macos_computer_use_mvp_fixture_vision_llm_canary_') ||
            _basename(
              file.parent.path,
            ).startsWith('macos_computer_use_real_app_observe_canary_') ||
            _basename(
              file.parent.path,
            ).startsWith('macos_computer_use_mvp_fixture_llm_canary_');
      })
      .toList(growable: false);
  final realAppObserveFiles = computerUseFiles
      .where((file) {
        return _basename(
          file.parent.path,
        ).startsWith('macos_computer_use_real_app_observe_canary_');
      })
      .toList(growable: false);
  final visionFiles = computerUseFiles
      .where((file) {
        return _basename(
          file.parent.path,
        ).startsWith('macos_computer_use_mvp_fixture_vision_llm_canary_');
      })
      .toList(growable: false);
  final aggregateFiles = computerUseFiles
      .where((file) {
        return _basename(
          file.parent.path,
        ).startsWith('macos_computer_use_mvp_fixture_llm_canary_');
      })
      .toList(growable: false);
  final mvpFixtureFiles = computerUseFiles
      .where((file) {
        final json = _readJsonObject(file);
        final scenario = json?['scenario'] as String?;
        return scenario != null && scenario.startsWith('mvp-fixture');
      })
      .toList(growable: false);
  final latest = realAppObserveFiles.isNotEmpty
      ? realAppObserveFiles.last
      : visionFiles.isNotEmpty
      ? visionFiles.last
      : aggregateFiles.isNotEmpty
      ? aggregateFiles.last
      : mvpFixtureFiles.isNotEmpty
      ? mvpFixtureFiles.last
      : computerUseFiles.isNotEmpty
      ? computerUseFiles.last
      : files.isEmpty
      ? null
      : files.last;
  return ReadinessArtifactEntry(
    id: id,
    label: label,
    path: latest?.path ?? '',
    exists: latest != null,
  );
}

ReadinessArtifactEntry _entry(String id, String label, String path) {
  return ReadinessArtifactEntry(
    id: id,
    label: label,
    path: path,
    exists: File(path).existsSync(),
  );
}

ReadinessArtifactEntry _latestEntry(
  String id,
  String label,
  Directory reportRoot,
  bool Function(Map<String, dynamic> json) matches, {
  String? parentPrefix,
  String? fileName,
  String? Function(Map<String, dynamic> json)? status,
  String? Function(Map<String, dynamic> json)? nextAction,
  Map<String, Object?> Function(Map<String, dynamic> json)? details,
}) {
  final files = reportRoot.existsSync()
      ? reportRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .where((file) {
              if (fileName != null && _basename(file.path) != fileName) {
                return false;
              }
              if (parentPrefix != null &&
                  !_basename(file.parent.path).startsWith(parentPrefix)) {
                return false;
              }
              final json = _readJsonObject(file);
              return json != null && matches(json);
            })
            .toList(growable: false)
      : <File>[];
  files.sort((left, right) {
    final modifiedCompare = left.statSync().modified.compareTo(
      right.statSync().modified,
    );
    if (modifiedCompare != 0) {
      return modifiedCompare;
    }
    return left.path.compareTo(right.path);
  });
  final latest = files.isEmpty ? null : files.last;
  final latestJson = latest == null ? null : _readJsonObject(latest);
  return ReadinessArtifactEntry(
    id: id,
    label: label,
    path: latest?.path ?? '',
    exists: latest != null,
    status: latestJson == null ? null : status?.call(latestJson),
    nextAction: latestJson == null ? null : nextAction?.call(latestJson),
    details: latestJson == null
        ? const <String, Object?>{}
        : details?.call(latestJson) ?? const <String, Object?>{},
  );
}

String? _m15ActionProposalStatus(Map<String, dynamic> json) {
  final gate = json['m15ActionProposalGate'];
  if (gate is Map<String, dynamic>) {
    return gate['status']?.toString();
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m15ActionProposalNextAction(Map<String, dynamic> json) {
  final gate = json['m15ActionProposalGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m15ActionProposalStatus(json);
  if (status == 'ready') {
    return 'M15 action proposal handoff is ready for user review.';
  }
  if (status == 'blocked') {
    return 'Resolve blocked M15 handoff checks before proposing any action.';
  }
  return null;
}

Map<String, Object?> _m15ActionProposalDetails(Map<String, dynamic> json) {
  return <String, Object?>{
    'exactTextCandidateCount': _jsonList(json['exactTextCandidates']).length,
    'textEntryTargetCount': _jsonList(json['textEntryTargets']).length,
    'publicActionTargetCount': _jsonList(json['publicActionTargets']).length,
  };
}

List<Object?> _jsonList(Object? value) {
  return value is List ? value : const <Object?>[];
}

Map<String, dynamic>? _readJsonObject(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
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

String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (RegExp(r'^[A-Za-z0-9_./:=@%+-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}
