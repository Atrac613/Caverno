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
        '- Blocked review evidence: ${_joinedOrNone(mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds)}',
      )
      ..writeln(
        '- Boundary: ${mvpFinalSignoffRehearsal.prReviewSummary.operationBoundarySummary}',
      )
      ..writeln(
        '- Report-only preflight command: `${_escapeMarkdownCode(mvpFinalSignoffRehearsal.reportOnlyPreflightCommand)}`',
      );
    ReadinessArtifactEntry? m15Entry;
    ReadinessArtifactEntry? m15LlmReviewEntry;
    ReadinessArtifactEntry? m16ApprovalPacketEntry;
    ReadinessArtifactEntry? m17ExecutionRehearsalEntry;
    ReadinessArtifactEntry? m18ExecutionHandoffEntry;
    ReadinessArtifactEntry? m20ExecutionResultIntakeEntry;
    ReadinessArtifactEntry? m22PostActionReviewEntry;
    ReadinessArtifactEntry? m23CycleOutcomeHandoffEntry;
    ReadinessArtifactEntry? m25NextCycleSeedHandoffEntry;
    ReadinessArtifactEntry? m26ObserveRestartPacketEntry;
    ReadinessArtifactEntry? m27ScreenshotRequestHandoffEntry;
    for (final entry in entries) {
      if (entry.id == 'm15_action_proposal_handoff') {
        m15Entry = entry;
      }
      if (entry.id == 'm15_llm_review_canary') {
        m15LlmReviewEntry = entry;
      }
      if (entry.id == 'm16_approval_packet') {
        m16ApprovalPacketEntry = entry;
      }
      if (entry.id == 'm17_execution_rehearsal') {
        m17ExecutionRehearsalEntry = entry;
      }
      if (entry.id == 'm18_execution_handoff') {
        m18ExecutionHandoffEntry = entry;
      }
      if (entry.id == 'm20_execution_result_intake') {
        m20ExecutionResultIntakeEntry = entry;
      }
      if (entry.id == 'm22_post_action_review') {
        m22PostActionReviewEntry = entry;
      }
      if (entry.id == 'm23_cycle_outcome_handoff') {
        m23CycleOutcomeHandoffEntry = entry;
      }
      if (entry.id == 'm25_next_cycle_seed_handoff') {
        m25NextCycleSeedHandoffEntry = entry;
      }
      if (entry.id == 'm26_observe_restart_packet') {
        m26ObserveRestartPacketEntry = entry;
      }
      if (entry.id == 'm27_screenshot_request_handoff') {
        m27ScreenshotRequestHandoffEntry = entry;
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
        )
        ..writeln(
          '- PR review status: ${m15Entry.details['prReviewStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Review/gate consistency: ${m15Entry.details['reviewGateConsistencyStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blocked review evidence: ${_joinedOrNone(_detailsStringList(m15Entry.details['blockedReviewEvidence']))}',
        );
    }
    if (m15LlmReviewEntry != null && m15LlmReviewEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M15 LLM Review Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m15LlmReviewEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Passed runs: ${m15LlmReviewEntry.details['passedCount'] ?? 0}',
        )
        ..writeln(
          '- Failed runs: ${m15LlmReviewEntry.details['failedCount'] ?? 0}',
        )
        ..writeln(
          '- Boundary decision: ${m15LlmReviewEntry.details['boundaryDecision'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m15LlmReviewEntry.details['blockers']))}',
        );
    }
    if (m16ApprovalPacketEntry != null &&
        m16ApprovalPacketEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M16 Approval Packet Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m16ApprovalPacketEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Approval status: ${m16ApprovalPacketEntry.details['approvalStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Approval blockers: ${_joinedOrNone(_detailsStringList(m16ApprovalPacketEntry.details['approvalBlockers']))}',
        )
        ..writeln(
          '- Execution boundary: ${m16ApprovalPacketEntry.details['executionBoundary'] ?? 'unknown'}',
        );
    }
    if (m17ExecutionRehearsalEntry != null &&
        m17ExecutionRehearsalEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M17 Execution Rehearsal Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m17ExecutionRehearsalEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Approval status: ${m17ExecutionRehearsalEntry.details['approvalStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution phases: ${m17ExecutionRehearsalEntry.details['executionPhaseCount'] ?? 0}',
        )
        ..writeln(
          '- Execution boundary: ${m17ExecutionRehearsalEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m17ExecutionRehearsalEntry.details['gateBlockers']))}',
        );
    }
    if (m18ExecutionHandoffEntry != null &&
        m18ExecutionHandoffEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M18 Execution Handoff Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m18ExecutionHandoffEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Action-time confirmations: ${m18ExecutionHandoffEntry.details['actionTimeConfirmationCount'] ?? 0}',
        )
        ..writeln(
          '- Execution checklist steps: ${m18ExecutionHandoffEntry.details['executionChecklistCount'] ?? 0}',
        )
        ..writeln(
          '- Execution boundary: ${m18ExecutionHandoffEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m18ExecutionHandoffEntry.details['gateBlockers']))}',
        );
    }
    if (m20ExecutionResultIntakeEntry != null &&
        m20ExecutionResultIntakeEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M20 Execution Result Intake Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m20ExecutionResultIntakeEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Runtime action: ${m20ExecutionResultIntakeEntry.details['runtimeAction'] ?? 'unknown'}',
        )
        ..writeln(
          '- Result sequence steps: ${m20ExecutionResultIntakeEntry.details['resultSequenceCount'] ?? 0}',
        )
        ..writeln(
          '- Execution boundary: ${m20ExecutionResultIntakeEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m20ExecutionResultIntakeEntry.details['gateBlockers']))}',
        );
    }
    if (m22PostActionReviewEntry != null &&
        m22PostActionReviewEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M22 Post-Action Review Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m22PostActionReviewEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Result reviewed: ${m22PostActionReviewEntry.details['resultReviewed'] ?? 'unknown'}',
        )
        ..writeln(
          '- Post-action state: ${m22PostActionReviewEntry.details['postActionState'] ?? 'unknown'}',
        )
        ..writeln(
          '- Next cycle recommendation: ${m22PostActionReviewEntry.details['nextCycleRecommendation'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution boundary: ${m22PostActionReviewEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m22PostActionReviewEntry.details['gateBlockers']))}',
        );
    }
    if (m23CycleOutcomeHandoffEntry != null &&
        m23CycleOutcomeHandoffEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M23 Cycle Outcome Handoff Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m23CycleOutcomeHandoffEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Cycle outcome: ${m23CycleOutcomeHandoffEntry.details['cycleOutcome'] ?? 'unknown'}',
        )
        ..writeln(
          '- Next observe needed: ${m23CycleOutcomeHandoffEntry.details['nextObserveNeeded'] ?? 'unknown'}',
        )
        ..writeln(
          '- Source recommendation: ${m23CycleOutcomeHandoffEntry.details['sourceNextCycleRecommendation'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution boundary: ${m23CycleOutcomeHandoffEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m23CycleOutcomeHandoffEntry.details['gateBlockers']))}',
        );
    }
    if (m25NextCycleSeedHandoffEntry != null &&
        m25NextCycleSeedHandoffEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M25 Next-Cycle Seed Handoff Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m25NextCycleSeedHandoffEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Return milestone: ${m25NextCycleSeedHandoffEntry.details['returnMilestone'] ?? 'unknown'}',
        )
        ..writeln(
          '- Seed boundary: ${m25NextCycleSeedHandoffEntry.details['seedBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Seed accepted: ${m25NextCycleSeedHandoffEntry.details['seedAccepted'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution boundary: ${m25NextCycleSeedHandoffEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m25NextCycleSeedHandoffEntry.details['gateBlockers']))}',
        );
    }
    if (m26ObserveRestartPacketEntry != null &&
        m26ObserveRestartPacketEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M26 Observe Restart Packet Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m26ObserveRestartPacketEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target app: ${m26ObserveRestartPacketEntry.details['targetApp'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target intent: ${m26ObserveRestartPacketEntry.details['targetIntent'] ?? 'unknown'}',
        )
        ..writeln(
          '- Return milestone: ${m26ObserveRestartPacketEntry.details['returnMilestone'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution boundary: ${m26ObserveRestartPacketEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m26ObserveRestartPacketEntry.details['gateBlockers']))}',
        );
    }
    if (m27ScreenshotRequestHandoffEntry != null &&
        m27ScreenshotRequestHandoffEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M27 Screenshot Request Handoff Evidence')
        ..writeln()
        ..writeln(
          '- Gate status: ${m27ScreenshotRequestHandoffEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target app: ${m27ScreenshotRequestHandoffEntry.details['targetApp'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target intent: ${m27ScreenshotRequestHandoffEntry.details['targetIntent'] ?? 'unknown'}',
        )
        ..writeln(
          '- Screenshot provided: ${m27ScreenshotRequestHandoffEntry.details['screenshotProvided'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution boundary: ${m27ScreenshotRequestHandoffEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m27ScreenshotRequestHandoffEntry.details['gateBlockers']))}',
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
    if (mvpFinalSignoffRehearsal.m15ActionProposalCommand != null) {
      buffer
        ..writeln()
        ..writeln('M15 action proposal command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m15ActionProposalCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m15LlmReviewCommand != null) {
      buffer
        ..writeln()
        ..writeln('M15 LLM review command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m15LlmReviewCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m16ApprovalPacketCommand != null) {
      buffer
        ..writeln()
        ..writeln('M16 approval packet command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m16ApprovalPacketCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m17ExecutionRehearsalCommand != null) {
      buffer
        ..writeln()
        ..writeln('M17 execution rehearsal command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m17ExecutionRehearsalCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m18ExecutionHandoffCommand != null) {
      buffer
        ..writeln()
        ..writeln('M18 execution handoff command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m18ExecutionHandoffCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m20ExecutionResultIntakeCommand != null) {
      buffer
        ..writeln()
        ..writeln('M20 execution result intake command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m20ExecutionResultIntakeCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m22PostActionReviewCommand != null) {
      buffer
        ..writeln()
        ..writeln('M22 post-action review command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m22PostActionReviewCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m23CycleOutcomeHandoffCommand != null) {
      buffer
        ..writeln()
        ..writeln('M23 cycle outcome handoff command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m23CycleOutcomeHandoffCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m25NextCycleSeedHandoffCommand != null) {
      buffer
        ..writeln()
        ..writeln('M25 next-cycle seed handoff command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m25NextCycleSeedHandoffCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m26ObserveRestartPacketCommand != null) {
      buffer
        ..writeln()
        ..writeln('M26 observe restart packet command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m26ObserveRestartPacketCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m27ScreenshotRequestHandoffCommand != null) {
      buffer
        ..writeln()
        ..writeln('M27 screenshot request handoff command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m27ScreenshotRequestHandoffCommand)
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
    this.m15ActionProposalCommand,
    this.m15LlmReviewCommand,
    this.m16ApprovalPacketCommand,
    this.m17ExecutionRehearsalCommand,
    this.m18ExecutionHandoffCommand,
    this.m20ExecutionResultIntakeCommand,
    this.m22PostActionReviewCommand,
    this.m23CycleOutcomeHandoffCommand,
    this.m25NextCycleSeedHandoffCommand,
    this.m26ObserveRestartPacketCommand,
    this.m27ScreenshotRequestHandoffCommand,
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
  final String? m15ActionProposalCommand;
  final String? m15LlmReviewCommand;
  final String? m16ApprovalPacketCommand;
  final String? m17ExecutionRehearsalCommand;
  final String? m18ExecutionHandoffCommand;
  final String? m20ExecutionResultIntakeCommand;
  final String? m22PostActionReviewCommand;
  final String? m23CycleOutcomeHandoffCommand;
  final String? m25NextCycleSeedHandoffCommand;
  final String? m26ObserveRestartPacketCommand;
  final String? m27ScreenshotRequestHandoffCommand;
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
      'm15ActionProposalCommand': m15ActionProposalCommand,
      'm15LlmReviewCommand': m15LlmReviewCommand,
      'm16ApprovalPacketCommand': m16ApprovalPacketCommand,
      'm17ExecutionRehearsalCommand': m17ExecutionRehearsalCommand,
      'm18ExecutionHandoffCommand': m18ExecutionHandoffCommand,
      'm20ExecutionResultIntakeCommand': m20ExecutionResultIntakeCommand,
      'm22PostActionReviewCommand': m22PostActionReviewCommand,
      'm23CycleOutcomeHandoffCommand': m23CycleOutcomeHandoffCommand,
      'm25NextCycleSeedHandoffCommand': m25NextCycleSeedHandoffCommand,
      'm26ObserveRestartPacketCommand': m26ObserveRestartPacketCommand,
      'm27ScreenshotRequestHandoffCommand': m27ScreenshotRequestHandoffCommand,
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
    required this.blockedReviewEvidenceIds,
    required this.operationBoundarySummary,
  });

  final String status;
  final List<String> readyArtifactIds;
  final List<String> missingArtifactIds;
  final List<String> pendingUserOperatedEvidenceIds;
  final List<String> pendingAutomationSafeEvidenceIds;
  final List<String> blockedReviewEvidenceIds;
  final String operationBoundarySummary;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'readyArtifactIds': readyArtifactIds,
      'missingArtifactIds': missingArtifactIds,
      'pendingUserOperatedEvidenceIds': pendingUserOperatedEvidenceIds,
      'pendingAutomationSafeEvidenceIds': pendingAutomationSafeEvidenceIds,
      'blockedReviewEvidenceIds': blockedReviewEvidenceIds,
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
    _latestEntry(
      'm15_llm_review_canary',
      'Latest M15 LLM review canary summary',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_m15_llm_review_canary_summary',
      parentPrefix: 'macos_computer_use_m15_llm_review_canary_',
      fileName: 'canary_summary.json',
      status: _m15LlmReviewStatus,
      nextAction: _m15LlmReviewNextAction,
      details: _m15LlmReviewDetails,
    ),
    _latestEntry(
      'm16_approval_packet',
      'Latest M16 approval packet',
      reportRoot,
      (json) => json['schemaName'] == 'macos_computer_use_m16_approval_packet',
      parentPrefix: 'macos_computer_use_m16_approval_packet_',
      fileName: 'approval_packet.json',
      status: _m16ApprovalPacketStatus,
      nextAction: _m16ApprovalPacketNextAction,
      details: _m16ApprovalPacketDetails,
    ),
    _latestEntry(
      'm17_execution_rehearsal',
      'Latest M17 execution rehearsal',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_m17_execution_rehearsal',
      parentPrefix: 'macos_computer_use_m17_execution_rehearsal_',
      fileName: 'execution_rehearsal.json',
      status: _m17ExecutionRehearsalStatus,
      nextAction: _m17ExecutionRehearsalNextAction,
      details: _m17ExecutionRehearsalDetails,
    ),
    _latestEntry(
      'm18_execution_handoff',
      'Latest M18 execution handoff',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_m18_execution_handoff',
      parentPrefix: 'macos_computer_use_m18_execution_handoff_',
      fileName: 'execution_handoff.json',
      status: _m18ExecutionHandoffStatus,
      nextAction: _m18ExecutionHandoffNextAction,
      details: _m18ExecutionHandoffDetails,
    ),
    _latestEntry(
      'm20_execution_result_intake',
      'Latest M20 execution result intake',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_m20_execution_result_intake',
      parentPrefix: 'macos_computer_use_m20_execution_result_intake_',
      fileName: 'execution_result_intake.json',
      status: _m20ExecutionResultIntakeStatus,
      nextAction: _m20ExecutionResultIntakeNextAction,
      details: _m20ExecutionResultIntakeDetails,
    ),
    _latestEntry(
      'm22_post_action_review',
      'Latest M22 post-action review',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_m22_post_action_review',
      parentPrefix: 'macos_computer_use_m22_post_action_review_',
      fileName: 'post_action_review.json',
      status: _m22PostActionReviewStatus,
      nextAction: _m22PostActionReviewNextAction,
      details: _m22PostActionReviewDetails,
    ),
    _latestEntry(
      'm23_cycle_outcome_handoff',
      'Latest M23 cycle outcome handoff',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_m23_cycle_outcome_handoff',
      parentPrefix: 'macos_computer_use_m23_cycle_outcome_handoff_',
      fileName: 'cycle_outcome_handoff.json',
      status: _m23CycleOutcomeHandoffStatus,
      nextAction: _m23CycleOutcomeHandoffNextAction,
      details: _m23CycleOutcomeHandoffDetails,
    ),
    _latestEntry(
      'm25_next_cycle_seed_handoff',
      'Latest M25 next-cycle seed handoff',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_m25_next_cycle_seed_handoff',
      parentPrefix: 'macos_computer_use_m25_next_cycle_seed_handoff_',
      fileName: 'next_cycle_seed_handoff.json',
      status: _m25NextCycleSeedHandoffStatus,
      nextAction: _m25NextCycleSeedHandoffNextAction,
      details: _m25NextCycleSeedHandoffDetails,
    ),
    _latestEntry(
      'm26_observe_restart_packet',
      'Latest M26 observe restart packet',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_m26_observe_restart_packet',
      parentPrefix: 'macos_computer_use_m26_observe_restart_packet_',
      fileName: 'observe_restart_packet.json',
      status: _m26ObserveRestartPacketStatus,
      nextAction: _m26ObserveRestartPacketNextAction,
      details: _m26ObserveRestartPacketDetails,
    ),
    _latestEntry(
      'm27_screenshot_request_handoff',
      'Latest M27 screenshot request handoff',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_m27_screenshot_request_handoff',
      parentPrefix: 'macos_computer_use_m27_screenshot_request_handoff_',
      fileName: 'screenshot_request_handoff.json',
      status: _m27ScreenshotRequestHandoffStatus,
      nextAction: _m27ScreenshotRequestHandoffNextAction,
      details: _m27ScreenshotRequestHandoffDetails,
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
  final blockedReviewArtifacts = _blockedReviewArtifacts(entries);
  final blockedReviewActions = blockedReviewArtifacts
      .map(
        (entry) => ReadinessMissingArtifactAction(
          artifactId: entry.id,
          label: entry.label,
          nextAction:
              entry.nextAction ??
              'Resolve blocked review evidence before final aggregation.',
        ),
      )
      .toList(growable: false);
  final nextActions = <String>[
    ...missingArtifactActions.map((action) => action.nextAction),
    ...blockedReviewActions.map((action) => action.nextAction),
  ];
  final ready = missingArtifactIds.isEmpty && blockedReviewArtifacts.isEmpty;
  final finalAggregationCommand = ready
      ? _mvpFinalAggregationCommand(reportRoot, byId)
      : null;
  final m15ActionProposalCommand = _m15ActionProposalCommand(reportRoot, byId);
  final m15LlmReviewCommand = _m15LlmReviewCommand(reportRoot, byId);
  final m16ApprovalPacketCommand = _m16ApprovalPacketCommand(reportRoot, byId);
  final m17ExecutionRehearsalCommand = _m17ExecutionRehearsalCommand(
    reportRoot,
    byId,
  );
  final m18ExecutionHandoffCommand = _m18ExecutionHandoffCommand(
    reportRoot,
    byId,
  );
  final m20ExecutionResultIntakeCommand = _m20ExecutionResultIntakeCommand(
    reportRoot,
    byId,
  );
  final m22PostActionReviewCommand = _m22PostActionReviewCommand(
    reportRoot,
    byId,
  );
  final m23CycleOutcomeHandoffCommand = _m23CycleOutcomeHandoffCommand(
    reportRoot,
    byId,
  );
  final m25NextCycleSeedHandoffCommand = _m25NextCycleSeedHandoffCommand(
    reportRoot,
    byId,
  );
  final m26ObserveRestartPacketCommand = _m26ObserveRestartPacketCommand(
    reportRoot,
    byId,
  );
  final m27ScreenshotRequestHandoffCommand =
      _m27ScreenshotRequestHandoffCommand(reportRoot, byId);
  final prReviewSummary = _mvpPrReviewSummary(
    readyArtifactIds: readyArtifactIds,
    missingArtifactIds: missingArtifactIds,
    blockedReviewArtifactIds: blockedReviewArtifacts
        .map((entry) => entry.id)
        .toList(growable: false),
  );
  return ReadinessFinalSignoffRehearsal(
    ready: ready,
    requiredArtifacts: List<ReadinessArtifactEntry>.unmodifiable(
      requiredArtifacts,
    ),
    missingArtifactIds: List<String>.unmodifiable(missingArtifactIds),
    missingArtifactActions: List<ReadinessMissingArtifactAction>.unmodifiable([
      ...missingArtifactActions,
      ...blockedReviewActions,
    ]),
    prReviewSummary: prReviewSummary,
    nextActions: List<String>.unmodifiable(nextActions),
    finalAggregationCommand: finalAggregationCommand,
    reportOnlyPreflightCommand: _mvpReadinessPreflightCommand(reportRoot),
    m15ActionProposalCommand: m15ActionProposalCommand,
    m15LlmReviewCommand: m15LlmReviewCommand,
    m16ApprovalPacketCommand: m16ApprovalPacketCommand,
    m17ExecutionRehearsalCommand: m17ExecutionRehearsalCommand,
    m18ExecutionHandoffCommand: m18ExecutionHandoffCommand,
    m20ExecutionResultIntakeCommand: m20ExecutionResultIntakeCommand,
    m22PostActionReviewCommand: m22PostActionReviewCommand,
    m23CycleOutcomeHandoffCommand: m23CycleOutcomeHandoffCommand,
    m25NextCycleSeedHandoffCommand: m25NextCycleSeedHandoffCommand,
    m26ObserveRestartPacketCommand: m26ObserveRestartPacketCommand,
    m27ScreenshotRequestHandoffCommand: m27ScreenshotRequestHandoffCommand,
  );
}

List<ReadinessArtifactEntry> _blockedReviewArtifacts(
  List<ReadinessArtifactEntry> entries,
) {
  return entries
      .where(
        (entry) =>
            (entry.id == 'm15_action_proposal_handoff' ||
                entry.id == 'm15_llm_review_canary' ||
                entry.id == 'm16_approval_packet' ||
                entry.id == 'm17_execution_rehearsal' ||
                entry.id == 'm18_execution_handoff' ||
                entry.id == 'm20_execution_result_intake' ||
                entry.id == 'm22_post_action_review' ||
                entry.id == 'm23_cycle_outcome_handoff' ||
                entry.id == 'm25_next_cycle_seed_handoff' ||
                entry.id == 'm26_observe_restart_packet' ||
                entry.id == 'm27_screenshot_request_handoff') &&
            entry.exists &&
            entry.status != null &&
            entry.status != 'ready',
      )
      .toList(growable: false);
}

ReadinessPrReviewSummary _mvpPrReviewSummary({
  required List<String> readyArtifactIds,
  required List<String> missingArtifactIds,
  required List<String> blockedReviewArtifactIds,
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
        ? blockedReviewArtifactIds.isEmpty
              ? 'ready_for_final_aggregation'
              : 'blocked_pending_review_evidence'
        : 'blocked_pending_evidence',
    readyArtifactIds: List<String>.unmodifiable(readyArtifactIds),
    missingArtifactIds: List<String>.unmodifiable(missingArtifactIds),
    pendingUserOperatedEvidenceIds: List<String>.unmodifiable(
      pendingUserOperatedEvidenceIds,
    ),
    pendingAutomationSafeEvidenceIds: List<String>.unmodifiable(
      pendingAutomationSafeEvidenceIds,
    ),
    blockedReviewEvidenceIds: List<String>.unmodifiable(
      blockedReviewArtifactIds,
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

String? _m15ActionProposalCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final llmEntry = entriesById['llm_canary'];
  final m14SummaryPath = llmEntry?.path ?? '';
  if (m14SummaryPath.isEmpty ||
      !m14SummaryPath.contains('macos_computer_use_real_app_observe_canary_')) {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m15_action_proposal_handoff.sh',
    '--root',
    reportRoot.path,
    '--m14-summary',
    m14SummaryPath,
  ].map(_shellQuote).join(' ');
}

String? _m15LlmReviewCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final handoffEntry = entriesById['m15_action_proposal_handoff'];
  final handoffPath = handoffEntry?.path ?? '';
  if (handoffPath.isEmpty || handoffEntry?.status != 'ready') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m15_llm_review_canary.sh',
    '--root',
    reportRoot.path,
    '--handoff',
    handoffPath,
  ].map(_shellQuote).join(' ');
}

String? _m16ApprovalPacketCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final handoffEntry = entriesById['m15_action_proposal_handoff'];
  final handoffPath = handoffEntry?.path ?? '';
  if (handoffPath.isEmpty || handoffEntry?.status != 'ready') {
    return null;
  }
  final command = <String>[
    'bash',
    'tool/run_macos_computer_use_m16_approval_packet.sh',
    '--root',
    reportRoot.path,
    '--m15-handoff',
    handoffPath,
  ];
  final reviewEntry = entriesById['m15_llm_review_canary'];
  final reviewPath = reviewEntry?.path ?? '';
  if (reviewPath.isNotEmpty && reviewEntry?.status == 'ready') {
    command.addAll(<String>['--m15-llm-review', reviewPath]);
  }
  return command.map(_shellQuote).join(' ');
}

String? _m17ExecutionRehearsalCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final packetEntry = entriesById['m16_approval_packet'];
  final packetPath = packetEntry?.path ?? '';
  if (packetPath.isEmpty || packetEntry?.status != 'ready') {
    return null;
  }
  if (packetEntry?.details['approvalStatus'] != 'approved') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m17_execution_rehearsal.sh',
    '--root',
    reportRoot.path,
    '--m16-packet',
    packetPath,
  ].map(_shellQuote).join(' ');
}

String? _m18ExecutionHandoffCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final rehearsalEntry = entriesById['m17_execution_rehearsal'];
  final rehearsalPath = rehearsalEntry?.path ?? '';
  if (rehearsalPath.isEmpty || rehearsalEntry?.status != 'ready') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m18_execution_handoff.sh',
    '--root',
    reportRoot.path,
    '--m17-rehearsal',
    rehearsalPath,
  ].map(_shellQuote).join(' ');
}

String? _m20ExecutionResultIntakeCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final handoffEntry = entriesById['m18_execution_handoff'];
  final handoffPath = handoffEntry?.path ?? '';
  if (handoffPath.isEmpty || handoffEntry?.status != 'ready') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m20_execution_result_intake.sh',
    '--root',
    reportRoot.path,
    '--m18-handoff',
    handoffPath,
    '--fresh-observation',
    'done',
    '--target-confirmed',
    'yes',
    '--exact-text-confirmed',
    'yes',
    '--public-action-confirmed',
    '<yes-or-not-applicable>',
    '--runtime-action',
    'succeeded',
    '--post-action-observation',
    'done',
  ].map(_shellQuote).join(' ');
}

String? _m22PostActionReviewCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final intakeEntry = entriesById['m20_execution_result_intake'];
  final intakePath = intakeEntry?.path ?? '';
  if (intakePath.isEmpty || intakeEntry?.status != 'ready') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m22_post_action_review.sh',
    '--root',
    reportRoot.path,
    '--m20-intake',
    intakePath,
    '--result-reviewed',
    'yes',
    '--post-action-state',
    '<stable-or-needs-follow-up>',
    '--follow-up-required',
    '<yes-or-no>',
  ].map(_shellQuote).join(' ');
}

String? _m23CycleOutcomeHandoffCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final reviewEntry = entriesById['m22_post_action_review'];
  final reviewPath = reviewEntry?.path ?? '';
  if (reviewPath.isEmpty || reviewEntry?.status != 'ready') {
    return null;
  }
  final nextCycleRecommendation = reviewEntry
      ?.details['nextCycleRecommendation']
      ?.toString();
  final nextObserveNeeded =
      nextCycleRecommendation == 'start_new_observe_action_cycle'
      ? 'yes'
      : 'no';
  final command = <String>[
    'bash',
    'tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh',
    '--root',
    reportRoot.path,
    '--m22-review',
    reviewPath,
    '--outcome-accepted',
    'yes',
    '--next-observe-needed',
    nextObserveNeeded,
  ];
  if (nextObserveNeeded == 'yes') {
    command.addAll(<String>['--next-observe-note', '<follow-up-note>']);
  }
  return command.map(_shellQuote).join(' ');
}

String? _m25NextCycleSeedHandoffCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final m23Entry = entriesById['m23_cycle_outcome_handoff'];
  final m23Path = m23Entry?.path ?? '';
  if (m23Path.isEmpty || m23Entry?.status != 'ready') {
    return null;
  }
  if (m23Entry?.details['cycleOutcome'] != 'restart_observe_action_cycle') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh',
    '--root',
    reportRoot.path,
    '--m23-handoff',
    m23Path,
    '--seed-accepted',
    'yes',
  ].map(_shellQuote).join(' ');
}

String? _m26ObserveRestartPacketCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final m25Entry = entriesById['m25_next_cycle_seed_handoff'];
  final m25Path = m25Entry?.path ?? '';
  if (m25Path.isEmpty || m25Entry?.status != 'ready') {
    return null;
  }
  if (m25Entry?.details['returnMilestone'] != 'M14') {
    return null;
  }
  final command = <String>[
    'bash',
    'tool/run_macos_computer_use_m26_observe_restart_packet.sh',
    '--root',
    reportRoot.path,
    '--m25-handoff',
    m25Path,
    '--target-app',
    'Safari',
  ];
  final seedNote = m25Entry?.details['seedNote']?.toString();
  if (seedNote != null && seedNote.isNotEmpty) {
    command.addAll(<String>['--target-intent', seedNote]);
  }
  return command.map(_shellQuote).join(' ');
}

String? _m27ScreenshotRequestHandoffCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final m26Entry = entriesById['m26_observe_restart_packet'];
  final m26Path = m26Entry?.path ?? '';
  if (m26Path.isEmpty || m26Entry?.status != 'ready') {
    return null;
  }
  if (m26Entry?.details['returnMilestone'] != 'M14') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m27_screenshot_request_handoff.sh',
    '--root',
    reportRoot.path,
    '--m26-packet',
    m26Path,
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
  String? gateStatus;
  if (gate is Map<String, dynamic>) {
    gateStatus = gate['status']?.toString();
  }
  if (gateStatus == 'blocked' ||
      _m15ReviewSummaryBlocked(json) ||
      _m15ReviewGateConsistencyBlocked(json)) {
    return 'blocked';
  }
  if (gateStatus != null) {
    return gateStatus;
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m15ActionProposalNextAction(Map<String, dynamic> json) {
  final gate = json['m15ActionProposalGate'];
  final gateStatus = gate is Map<String, dynamic>
      ? gate['status']?.toString()
      : null;
  final status = _m15ActionProposalStatus(json);
  if (status == 'blocked' &&
      gateStatus == 'ready' &&
      _m15ReviewSummaryBlocked(json)) {
    return 'Resolve blocked M15 review evidence before proposing any action.';
  }
  if (status == 'blocked' && _m15ReviewGateConsistencyBlocked(json)) {
    return 'Resolve inconsistent M15 review and gate evidence before proposing any action.';
  }
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  if (status == 'ready') {
    return 'M15 action proposal handoff is ready for user review.';
  }
  if (status == 'blocked') {
    return 'Resolve blocked M15 handoff checks before proposing any action.';
  }
  return null;
}

bool _m15ReviewSummaryBlocked(Map<String, dynamic> json) {
  final review = json['prReviewSummary'];
  if (review is! Map<String, dynamic>) {
    return false;
  }
  final status = review['status']?.toString();
  final blockedReviewEvidence = _jsonStringList(
    review['blockedReviewEvidence'],
  );
  return blockedReviewEvidence.isNotEmpty ||
      (status != null && status != 'ready_for_review');
}

bool _m15ReviewGateConsistencyBlocked(Map<String, dynamic> json) {
  final consistency = json['reviewGateConsistency'];
  if (consistency is! Map<String, dynamic>) {
    return false;
  }
  final ok = consistency['ok'];
  final status = consistency['status']?.toString();
  return ok == false || (status != null && status != 'consistent');
}

Map<String, Object?> _m15ActionProposalDetails(Map<String, dynamic> json) {
  final review = json['prReviewSummary'];
  final reviewMap = review is Map<String, dynamic> ? review : null;
  final consistency = json['reviewGateConsistency'];
  final consistencyMap = consistency is Map<String, dynamic>
      ? consistency
      : null;
  return <String, Object?>{
    'exactTextCandidateCount': _jsonList(json['exactTextCandidates']).length,
    'textEntryTargetCount': _jsonList(json['textEntryTargets']).length,
    'publicActionTargetCount': _jsonList(json['publicActionTargets']).length,
    if (consistencyMap != null) ...<String, Object?>{
      'reviewGateConsistencyStatus': consistencyMap['status']?.toString(),
      'reviewGateConsistencyOk': consistencyMap['ok'],
    },
    if (reviewMap != null) ...<String, Object?>{
      'prReviewStatus': reviewMap['status']?.toString(),
      'blockedReviewEvidence': _jsonStringList(
        reviewMap['blockedReviewEvidence'],
      ),
    },
  };
}

String? _m15LlmReviewStatus(Map<String, dynamic> json) {
  final gate = json['m15LlmReviewGate'];
  String? gateStatus;
  if (gate is Map<String, dynamic>) {
    gateStatus = gate['status']?.toString();
  }
  if (gateStatus != null) {
    return gateStatus;
  }
  final failedCount = json['failedCount'];
  if (failedCount is num) {
    return failedCount == 0 ? 'ready' : 'blocked';
  }
  return null;
}

String? _m15LlmReviewNextAction(Map<String, dynamic> json) {
  final gate = json['m15LlmReviewGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m15LlmReviewStatus(json);
  if (status == 'ready') {
    return 'M15 LLM review canary is ready for user review.';
  }
  if (status == 'blocked') {
    return 'Resolve M15 LLM review boundary failures before any action proposal execution.';
  }
  return null;
}

Map<String, Object?> _m15LlmReviewDetails(Map<String, dynamic> json) {
  final gate = json['m15LlmReviewGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  return <String, Object?>{
    'passedCount': json['passedCount'],
    'failedCount': json['failedCount'],
    'boundaryDecision': json['boundaryDecision']?.toString(),
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'blockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m16ApprovalPacketStatus(Map<String, dynamic> json) {
  final gate = json['m16ApprovalPacketGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m16ApprovalPacketNextAction(Map<String, dynamic> json) {
  final gate = json['m16ApprovalPacketGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m16ApprovalPacketStatus(json);
  if (status == 'ready') {
    return 'M16 approval packet is ready for user approval review.';
  }
  if (status == 'blocked') {
    return 'Resolve blocked M15 evidence before preparing the M16 approval packet.';
  }
  return null;
}

Map<String, Object?> _m16ApprovalPacketDetails(Map<String, dynamic> json) {
  final gate = json['m16ApprovalPacketGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  return <String, Object?>{
    'approvalStatus': json['approvalStatus']?.toString(),
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'requiredApprovalCount': _jsonList(json['requiredApprovals']).length,
    'exactTextCandidateCount': _jsonList(json['exactTextCandidates']).length,
    'textEntryTargetCount': _jsonList(json['textEntryTargets']).length,
    'publicActionTargetCount': _jsonList(json['publicActionTargets']).length,
    'approvalBlockers': _jsonStringList(json['approvalBlockers']),
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m17ExecutionRehearsalStatus(Map<String, dynamic> json) {
  final gate = json['m17ExecutionRehearsalGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m17ExecutionRehearsalNextAction(Map<String, dynamic> json) {
  final gate = json['m17ExecutionRehearsalGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m17ExecutionRehearsalStatus(json);
  if (status == 'ready') {
    return 'M17 execution rehearsal is ready for future user-operated execution review.';
  }
  if (status == 'blocked') {
    return 'Resolve blocked M17 rehearsal checks before future execution.';
  }
  return null;
}

Map<String, Object?> _m17ExecutionRehearsalDetails(Map<String, dynamic> json) {
  final gate = json['m17ExecutionRehearsalGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final approvedValues = json['approvedValues'];
  final approvedValuesMap = approvedValues is Map<String, dynamic>
      ? approvedValues
      : null;
  return <String, Object?>{
    'approvalStatus': json['approvalStatus']?.toString(),
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'executionPhaseCount': _jsonList(json['executionPhases']).length,
    if (approvedValuesMap != null) ...<String, Object?>{
      'approvedExactText': approvedValuesMap['exactText']?.toString(),
      'approvedTargetLabel': approvedValuesMap['targetLabel']?.toString(),
      'approvedPublicActionLabel': approvedValuesMap['publicActionLabel']
          ?.toString(),
    },
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m18ExecutionHandoffStatus(Map<String, dynamic> json) {
  final gate = json['m18ExecutionHandoffGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m18ExecutionHandoffNextAction(Map<String, dynamic> json) {
  final gate = json['m18ExecutionHandoffGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m18ExecutionHandoffStatus(json);
  if (status == 'ready') {
    return 'Ask the user to perform the runtime step manually with fresh observation and action-time confirmations.';
  }
  if (status == 'blocked') {
    return 'Resolve M18 handoff blockers before preparing any runtime execution step.';
  }
  return null;
}

Map<String, Object?> _m18ExecutionHandoffDetails(Map<String, dynamic> json) {
  final gate = json['m18ExecutionHandoffGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final approvedValues = json['approvedValues'];
  final approvedValuesMap = approvedValues is Map<String, dynamic>
      ? approvedValues
      : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'publicActionRequiresSeparateApproval':
        json['publicActionRequiresSeparateApproval'],
    'actionTimeConfirmationCount': _jsonList(
      json['actionTimeConfirmations'],
    ).length,
    'executionChecklistCount': _jsonList(json['executionChecklist']).length,
    if (approvedValuesMap != null) ...<String, Object?>{
      'approvedExactText': approvedValuesMap['exactText']?.toString(),
      'approvedTargetLabel': approvedValuesMap['targetLabel']?.toString(),
      'approvedPublicActionLabel': approvedValuesMap['publicActionLabel']
          ?.toString(),
    },
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m20ExecutionResultIntakeStatus(Map<String, dynamic> json) {
  final gate = json['m20ExecutionResultIntakeGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m20ExecutionResultIntakeNextAction(Map<String, dynamic> json) {
  final gate = json['m20ExecutionResultIntakeGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m20ExecutionResultIntakeStatus(json);
  if (status == 'ready') {
    return 'Review the user-operated runtime result evidence before any follow-up action.';
  }
  if (status == 'blocked') {
    return 'Resolve M20 result intake blockers before accepting runtime evidence.';
  }
  return null;
}

Map<String, Object?> _m20ExecutionResultIntakeDetails(
  Map<String, dynamic> json,
) {
  final gate = json['m20ExecutionResultIntakeGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final manualInputs = json['manualInputs'];
  final manualInputsMap = manualInputs is Map<String, dynamic>
      ? manualInputs
      : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM18ExecutionHandoff': json['sourceM18ExecutionHandoff']?.toString(),
    'resultSequenceCount': _jsonList(json['resultSequence']).length,
    if (manualInputsMap != null) ...<String, Object?>{
      'freshObservation': manualInputsMap['freshObservation']?.toString(),
      'targetConfirmed': manualInputsMap['targetConfirmed']?.toString(),
      'exactTextConfirmed': manualInputsMap['exactTextConfirmed']?.toString(),
      'publicActionConfirmed': manualInputsMap['publicActionConfirmed']
          ?.toString(),
      'runtimeAction': manualInputsMap['runtimeAction']?.toString(),
      'postActionObservation': manualInputsMap['postActionObservation']
          ?.toString(),
    },
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m22PostActionReviewStatus(Map<String, dynamic> json) {
  final gate = json['m22PostActionReviewGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m22PostActionReviewNextAction(Map<String, dynamic> json) {
  final gate = json['m22PostActionReviewGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m22PostActionReviewStatus(json);
  if (status == 'ready') {
    final recommendation = json['nextCycleRecommendation']?.toString();
    if (recommendation == 'start_new_observe_action_cycle') {
      return 'Return to M14 observe-only evidence before proposing any follow-up action.';
    }
    return 'Archive the reviewed M20 result as the completed action cycle evidence.';
  }
  if (status == 'blocked') {
    return 'Resolve M22 post-action review blockers before closing the action cycle.';
  }
  return null;
}

Map<String, Object?> _m22PostActionReviewDetails(Map<String, dynamic> json) {
  final gate = json['m22PostActionReviewGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final reviewInputs = json['reviewInputs'];
  final reviewInputsMap = reviewInputs is Map<String, dynamic>
      ? reviewInputs
      : null;
  final sourceManualInputs = json['sourceManualInputs'];
  final sourceManualInputsMap = sourceManualInputs is Map<String, dynamic>
      ? sourceManualInputs
      : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM20ExecutionResultIntake': json['sourceM20ExecutionResultIntake']
        ?.toString(),
    'nextCycleRecommendation': json['nextCycleRecommendation']?.toString(),
    if (reviewInputsMap != null) ...<String, Object?>{
      'resultReviewed': reviewInputsMap['resultReviewed']?.toString(),
      'postActionState': reviewInputsMap['postActionState']?.toString(),
      'followUpRequired': reviewInputsMap['followUpRequired']?.toString(),
    },
    if (sourceManualInputsMap != null) ...<String, Object?>{
      'runtimeAction': sourceManualInputsMap['runtimeAction']?.toString(),
      'postActionObservation': sourceManualInputsMap['postActionObservation']
          ?.toString(),
    },
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m23CycleOutcomeHandoffStatus(Map<String, dynamic> json) {
  final gate = json['m23CycleOutcomeHandoffGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m23CycleOutcomeHandoffNextAction(Map<String, dynamic> json) {
  final gate = json['m23CycleOutcomeHandoffGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m23CycleOutcomeHandoffStatus(json);
  if (status == 'ready') {
    final cycleOutcome = json['cycleOutcome']?.toString();
    if (cycleOutcome == 'restart_observe_action_cycle') {
      return 'Start a new M14 observe-only evidence pass with the recorded follow-up note.';
    }
    return 'Archive the completed action cycle evidence.';
  }
  if (status == 'blocked') {
    return 'Resolve M23 cycle outcome blockers before closing or restarting the action cycle.';
  }
  return null;
}

Map<String, Object?> _m23CycleOutcomeHandoffDetails(Map<String, dynamic> json) {
  final gate = json['m23CycleOutcomeHandoffGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final handoffInputs = json['handoffInputs'];
  final handoffInputsMap = handoffInputs is Map<String, dynamic>
      ? handoffInputs
      : null;
  final nextObserveSeed = json['nextObserveSeed'];
  final nextObserveSeedMap = nextObserveSeed is Map<String, dynamic>
      ? nextObserveSeed
      : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM22PostActionReview': json['sourceM22PostActionReview']?.toString(),
    'sourceNextCycleRecommendation': json['sourceNextCycleRecommendation']
        ?.toString(),
    'cycleOutcome': json['cycleOutcome']?.toString(),
    if (handoffInputsMap != null) ...<String, Object?>{
      'outcomeAccepted': handoffInputsMap['outcomeAccepted']?.toString(),
      'nextObserveNeeded': handoffInputsMap['nextObserveNeeded']?.toString(),
    },
    if (nextObserveSeedMap != null) ...<String, Object?>{
      'nextObserveRequired': nextObserveSeedMap['required'],
      'nextObserveReturnMilestone': nextObserveSeedMap['returnMilestone']
          ?.toString(),
      'nextObserveBoundary': nextObserveSeedMap['boundary']?.toString(),
    },
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m25NextCycleSeedHandoffStatus(Map<String, dynamic> json) {
  final gate = json['m25NextCycleSeedHandoffGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m25NextCycleSeedHandoffNextAction(Map<String, dynamic> json) {
  final gate = json['m25NextCycleSeedHandoffGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m25NextCycleSeedHandoffStatus(json);
  if (status == 'ready') {
    return 'Start a new M14 observe-only evidence pass using the recorded next-cycle seed.';
  }
  if (status == 'blocked') {
    return 'Resolve M25 next-cycle seed blockers before starting the next observe-only pass.';
  }
  return null;
}

Map<String, Object?> _m25NextCycleSeedHandoffDetails(
  Map<String, dynamic> json,
) {
  final gate = json['m25NextCycleSeedHandoffGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final seedInputs = json['seedInputs'];
  final seedInputsMap = seedInputs is Map<String, dynamic> ? seedInputs : null;
  final nextCycleSeed = json['nextCycleSeed'];
  final nextCycleSeedMap = nextCycleSeed is Map<String, dynamic>
      ? nextCycleSeed
      : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM23CycleOutcomeHandoff': json['sourceM23CycleOutcomeHandoff']
        ?.toString(),
    'sourceCycleOutcome': json['sourceCycleOutcome']?.toString(),
    if (seedInputsMap != null) ...<String, Object?>{
      'seedAccepted': seedInputsMap['seedAccepted']?.toString(),
    },
    if (nextCycleSeedMap != null) ...<String, Object?>{
      'returnMilestone': nextCycleSeedMap['returnMilestone']?.toString(),
      'seedBoundary': nextCycleSeedMap['boundary']?.toString(),
      'seedNote': nextCycleSeedMap['note']?.toString(),
      'requiresNewApprovalCycle': nextCycleSeedMap['requiresNewApprovalCycle'],
    },
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m26ObserveRestartPacketStatus(Map<String, dynamic> json) {
  final gate = json['m26ObserveRestartPacketGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m26ObserveRestartPacketNextAction(Map<String, dynamic> json) {
  final gate = json['m26ObserveRestartPacketGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m26ObserveRestartPacketStatus(json);
  if (status == 'ready') {
    return 'Ask the user to manually prepare the target app, capture a screenshot, and run the M14 observe-only canary command.';
  }
  if (status == 'blocked') {
    return 'Resolve M26 observe restart packet blockers before asking for a new M14 screenshot.';
  }
  return null;
}

Map<String, Object?> _m26ObserveRestartPacketDetails(
  Map<String, dynamic> json,
) {
  final gate = json['m26ObserveRestartPacketGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final nextObservePreparation = json['nextObservePreparation'];
  final nextObservePreparationMap =
      nextObservePreparation is Map<String, dynamic>
      ? nextObservePreparation
      : null;
  final commands = json['commands'];
  final commandsMap = commands is Map<String, dynamic> ? commands : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM25NextCycleSeedHandoff': json['sourceM25NextCycleSeedHandoff']
        ?.toString(),
    'targetApp': json['targetApp']?.toString(),
    'targetIntent': json['targetIntent']?.toString(),
    'screenshotPath': json['screenshotPath']?.toString(),
    if (nextObservePreparationMap != null) ...<String, Object?>{
      'returnMilestone': nextObservePreparationMap['returnMilestone']
          ?.toString(),
      'observeBoundary': nextObservePreparationMap['boundary']?.toString(),
      'screenshotRequired': nextObservePreparationMap['screenshotRequired'],
      'screenshotProvided': nextObservePreparationMap['screenshotProvided'],
    },
    if (commandsMap != null) ...<String, Object?>{
      'm14RealAppHandoffCommand': commandsMap['m14RealAppHandoff']?.toString(),
      'm14ObserveCanaryCommand': commandsMap['m14ObserveCanary']?.toString(),
      'artifactIndexCommand': commandsMap['artifactIndex']?.toString(),
      'mvpSignoffDryRunCommand': commandsMap['mvpSignoffDryRun']?.toString(),
    },
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

String? _m27ScreenshotRequestHandoffStatus(Map<String, dynamic> json) {
  final gate = json['m27ScreenshotRequestHandoffGate'];
  if (gate is Map<String, dynamic>) {
    final status = gate['status']?.toString();
    if (status != null && status.isNotEmpty) {
      return status;
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  return null;
}

String? _m27ScreenshotRequestHandoffNextAction(Map<String, dynamic> json) {
  final gate = json['m27ScreenshotRequestHandoffGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m27ScreenshotRequestHandoffStatus(json);
  if (status == 'ready') {
    return 'Ask the user to manually prepare the target app, capture the requested screenshot, and run the M14 observe-only canary command.';
  }
  if (status == 'blocked') {
    return 'Resolve M27 screenshot request handoff blockers before asking for the manual screenshot.';
  }
  return null;
}

Map<String, Object?> _m27ScreenshotRequestHandoffDetails(
  Map<String, dynamic> json,
) {
  final gate = json['m27ScreenshotRequestHandoffGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final request = json['userScreenshotRequest'];
  final requestMap = request is Map<String, dynamic> ? request : null;
  final commands = json['commands'];
  final commandsMap = commands is Map<String, dynamic> ? commands : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM26ObserveRestartPacket': json['sourceM26ObserveRestartPacket']
        ?.toString(),
    'targetApp': json['targetApp']?.toString(),
    'targetIntent': json['targetIntent']?.toString(),
    'screenshotPath': json['screenshotPath']?.toString(),
    if (requestMap != null) ...<String, Object?>{
      'returnMilestone': requestMap['returnMilestone']?.toString(),
      'observeBoundary': requestMap['boundary']?.toString(),
      'screenshotRequired': requestMap['required'],
      'screenshotProvided': requestMap['provided'],
    },
    if (commandsMap != null) ...<String, Object?>{
      'm14RealAppHandoffCommand': commandsMap['m14RealAppHandoff']?.toString(),
      'm14ObserveCanaryCommand': commandsMap['m14ObserveCanary']?.toString(),
      'artifactIndexCommand': commandsMap['artifactIndex']?.toString(),
      'mvpSignoffDryRunCommand': commandsMap['mvpSignoffDryRun']?.toString(),
    },
    if (gateMap != null) ...<String, Object?>{
      'gateStatus': gateMap['status']?.toString(),
      'gateReady': gateMap['ready'],
      'gateBlockers': _jsonStringList(gateMap['blockers']),
    },
  };
}

List<String> _detailsStringList(Object? value) {
  return value is List
      ? value.map((item) => item.toString()).toList()
      : const [];
}

List<Object?> _jsonList(Object? value) {
  return value is List ? value : const <Object?>[];
}

List<String> _jsonStringList(Object? value) {
  return value is List
      ? value.map((item) => item.toString()).toList(growable: false)
      : const <String>[];
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
