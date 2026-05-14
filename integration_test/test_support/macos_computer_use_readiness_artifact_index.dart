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
    required this.nextStepNavigator,
  });

  final String reportRoot;
  final List<ReadinessArtifactEntry> entries;
  final ReadinessFinalSignoffRehearsal mvpFinalSignoffRehearsal;
  final ReadinessNextStepNavigator nextStepNavigator;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_readiness_artifact_index',
      'schemaVersion': 1,
      'reportRoot': reportRoot,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'mvpFinalSignoffRehearsal': mvpFinalSignoffRehearsal.toJson(),
      'nextStepNavigator': nextStepNavigator.toJson(),
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
    buffer
      ..writeln()
      ..writeln('## M31 Next Step Navigator')
      ..writeln()
      ..writeln('- Status: ${nextStepNavigator.status}')
      ..writeln('- Priority: ${nextStepNavigator.recommendation.priority}')
      ..writeln(
        '- Artifact: `${_escapeMarkdownCode(nextStepNavigator.recommendation.artifactId)}`',
      )
      ..writeln(
        '- Evidence path: `${_escapeMarkdownCode(nextStepNavigator.recommendation.evidencePath)}`',
      )
      ..writeln(
        '- Next action: ${_markdownCell(nextStepNavigator.recommendation.nextAction)}',
      )
      ..writeln(
        '- Requires user operation: ${nextStepNavigator.recommendation.requiresUserOperation}',
      );
    if (nextStepNavigator.recommendation.recommendedCommand != null) {
      buffer
        ..writeln()
        ..writeln('Recommended next command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(nextStepNavigator.recommendation.recommendedCommand)
        ..writeln('```');
    }
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
    ReadinessArtifactEntry? m28ScreenshotEvidenceIntakeEntry;
    ReadinessArtifactEntry? m29ObserveCanaryRunPacketEntry;
    ReadinessArtifactEntry? m30ObserveResultIntakeEntry;
    ReadinessArtifactEntry? m39BetaSignoffEntry;
    ReadinessArtifactEntry? m40ProductionLaunchGateEntry;
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
      if (entry.id == 'm28_screenshot_evidence_intake') {
        m28ScreenshotEvidenceIntakeEntry = entry;
      }
      if (entry.id == 'm29_observe_canary_run_packet') {
        m29ObserveCanaryRunPacketEntry = entry;
      }
      if (entry.id == 'm30_observe_result_intake') {
        m30ObserveResultIntakeEntry = entry;
      }
      if (entry.id == 'm39_beta_signoff') {
        m39BetaSignoffEntry = entry;
      }
      if (entry.id == 'm40_production_launch_gate') {
        m40ProductionLaunchGateEntry = entry;
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
    if (m28ScreenshotEvidenceIntakeEntry != null &&
        m28ScreenshotEvidenceIntakeEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M28 Screenshot Evidence Intake')
        ..writeln()
        ..writeln(
          '- Gate status: ${m28ScreenshotEvidenceIntakeEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target app: ${m28ScreenshotEvidenceIntakeEntry.details['targetApp'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target intent: ${m28ScreenshotEvidenceIntakeEntry.details['targetIntent'] ?? 'unknown'}',
        )
        ..writeln(
          '- Screenshot path: ${m28ScreenshotEvidenceIntakeEntry.details['screenshotPath'] ?? 'unknown'}',
        )
        ..writeln(
          '- Screenshot bytes: ${m28ScreenshotEvidenceIntakeEntry.details['screenshotSizeBytes'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution boundary: ${m28ScreenshotEvidenceIntakeEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m28ScreenshotEvidenceIntakeEntry.details['gateBlockers']))}',
        );
    }
    if (m29ObserveCanaryRunPacketEntry != null &&
        m29ObserveCanaryRunPacketEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M29 Observe Canary Run Packet')
        ..writeln()
        ..writeln(
          '- Gate status: ${m29ObserveCanaryRunPacketEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target app: ${m29ObserveCanaryRunPacketEntry.details['targetApp'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target intent: ${m29ObserveCanaryRunPacketEntry.details['targetIntent'] ?? 'unknown'}',
        )
        ..writeln(
          '- Screenshot path: ${m29ObserveCanaryRunPacketEntry.details['screenshotPath'] ?? 'unknown'}',
        )
        ..writeln(
          '- M14 observe command: ${m29ObserveCanaryRunPacketEntry.details['m14ObserveCanaryCommand'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution boundary: ${m29ObserveCanaryRunPacketEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m29ObserveCanaryRunPacketEntry.details['gateBlockers']))}',
        );
    }
    if (m30ObserveResultIntakeEntry != null &&
        m30ObserveResultIntakeEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M30 Observe Result Intake')
        ..writeln()
        ..writeln(
          '- Gate status: ${m30ObserveResultIntakeEntry.details['gateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target app: ${m30ObserveResultIntakeEntry.details['targetApp'] ?? 'unknown'}',
        )
        ..writeln(
          '- Target intent: ${m30ObserveResultIntakeEntry.details['targetIntent'] ?? 'unknown'}',
        )
        ..writeln(
          '- Screenshot path: ${m30ObserveResultIntakeEntry.details['screenshotPath'] ?? 'unknown'}',
        )
        ..writeln(
          '- M14 evidence gate: ${m30ObserveResultIntakeEntry.details['m14EvidenceGateStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- M15 command: ${m30ObserveResultIntakeEntry.details['m15ActionProposalHandoffCommand'] ?? 'unknown'}',
        )
        ..writeln(
          '- Execution boundary: ${m30ObserveResultIntakeEntry.details['executionBoundary'] ?? 'unknown'}',
        )
        ..writeln(
          '- Blockers: ${_joinedOrNone(_detailsStringList(m30ObserveResultIntakeEntry.details['gateBlockers']))}',
        );
    }
    if (m39BetaSignoffEntry != null && m39BetaSignoffEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M39 Beta Sign-Off')
        ..writeln()
        ..writeln(
          '- Review status: ${m39BetaSignoffEntry.details['reviewStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Ready gates: ${_joinedOrNone(_detailsStringList(m39BetaSignoffEntry.details['readyGateIds']))}',
        )
        ..writeln(
          '- Blocked gates: ${_joinedOrNone(_detailsStringList(m39BetaSignoffEntry.details['blockedGateIds']))}',
        )
        ..writeln(
          '- Blocked user-operated gates: ${_joinedOrNone(_detailsStringList(m39BetaSignoffEntry.details['blockedUserOperatedGateIds']))}',
        )
        ..writeln(
          '- Boundary: ${m39BetaSignoffEntry.details['operationBoundarySummary'] ?? 'unknown'}',
        );
    }
    if (m40ProductionLaunchGateEntry != null &&
        m40ProductionLaunchGateEntry.details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## M40 Production Launch Gate')
        ..writeln()
        ..writeln(
          '- Review status: ${m40ProductionLaunchGateEntry.details['reviewStatus'] ?? 'unknown'}',
        )
        ..writeln(
          '- Ready gates: ${_joinedOrNone(_detailsStringList(m40ProductionLaunchGateEntry.details['readyGateIds']))}',
        )
        ..writeln(
          '- Blocked gates: ${_joinedOrNone(_detailsStringList(m40ProductionLaunchGateEntry.details['blockedGateIds']))}',
        )
        ..writeln(
          '- Blocked user-operated gates: ${_joinedOrNone(_detailsStringList(m40ProductionLaunchGateEntry.details['blockedUserOperatedGateIds']))}',
        )
        ..writeln(
          '- Boundary: ${m40ProductionLaunchGateEntry.details['operationBoundarySummary'] ?? 'unknown'}',
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
    if (mvpFinalSignoffRehearsal.m28ScreenshotEvidenceIntakeCommand != null) {
      buffer
        ..writeln()
        ..writeln('M28 screenshot evidence intake command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m28ScreenshotEvidenceIntakeCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m29ObserveCanaryRunPacketCommand != null) {
      buffer
        ..writeln()
        ..writeln('M29 observe canary run packet command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m29ObserveCanaryRunPacketCommand)
        ..writeln('```');
    }
    if (mvpFinalSignoffRehearsal.m30ObserveResultIntakeCommand != null) {
      buffer
        ..writeln()
        ..writeln('M30 observe result intake command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.m30ObserveResultIntakeCommand)
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
    this.m28ScreenshotEvidenceIntakeCommand,
    this.m29ObserveCanaryRunPacketCommand,
    this.m30ObserveResultIntakeCommand,
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
  final String? m28ScreenshotEvidenceIntakeCommand;
  final String? m29ObserveCanaryRunPacketCommand;
  final String? m30ObserveResultIntakeCommand;
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
      'm28ScreenshotEvidenceIntakeCommand': m28ScreenshotEvidenceIntakeCommand,
      'm29ObserveCanaryRunPacketCommand': m29ObserveCanaryRunPacketCommand,
      'm30ObserveResultIntakeCommand': m30ObserveResultIntakeCommand,
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

class ReadinessNextStepNavigator {
  const ReadinessNextStepNavigator({
    required this.status,
    required this.reportRoot,
    required this.recommendation,
    required this.operationBoundary,
  });

  final String status;
  final String reportRoot;
  final ReadinessNextStepRecommendation recommendation;
  final Map<String, Object?> operationBoundary;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m31_next_step_navigator',
      'schemaVersion': 1,
      'milestone': 'M31',
      'status': status,
      'reportRoot': reportRoot,
      'recommendation': recommendation.toJson(),
      'operationBoundary': operationBoundary,
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M31 Next Step Navigator')
      ..writeln()
      ..writeln('- Status: $status')
      ..writeln('- Report root: `$reportRoot`')
      ..writeln('- Priority: ${recommendation.priority}')
      ..writeln('- Artifact: `${recommendation.artifactId}`')
      ..writeln('- Artifact status: ${recommendation.artifactStatus}')
      ..writeln(
        '- Evidence path: `${_escapeMarkdownCode(recommendation.evidencePath)}`',
      )
      ..writeln('- Next action: ${recommendation.nextAction}')
      ..writeln(
        '- Requires user operation: ${recommendation.requiresUserOperation}',
      )
      ..writeln('- Boundary: ${recommendation.boundary}');
    if (recommendation.recommendedCommand != null) {
      buffer
        ..writeln()
        ..writeln('Recommended next command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(recommendation.recommendedCommand)
        ..writeln('```');
    }
    buffer
      ..writeln()
      ..writeln('Operation boundary:')
      ..writeln()
      ..writeln('- `tccGrants`: ${operationBoundary['tccGrants']}')
      ..writeln('- `desktopActions`: ${operationBoundary['desktopActions']}');
    return buffer.toString();
  }
}

class ReadinessNextStepRecommendation {
  const ReadinessNextStepRecommendation({
    required this.priority,
    required this.artifactId,
    required this.artifactLabel,
    required this.artifactStatus,
    required this.evidencePath,
    required this.nextAction,
    required this.boundary,
    required this.requiresUserOperation,
    this.recommendedCommand,
  });

  final String priority;
  final String artifactId;
  final String artifactLabel;
  final String artifactStatus;
  final String evidencePath;
  final String nextAction;
  final String boundary;
  final bool requiresUserOperation;
  final String? recommendedCommand;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'priority': priority,
      'artifactId': artifactId,
      'artifactLabel': artifactLabel,
      'artifactStatus': artifactStatus,
      'evidencePath': evidencePath,
      'nextAction': nextAction,
      'boundary': boundary,
      'requiresUserOperation': requiresUserOperation,
      if (recommendedCommand != null) 'recommendedCommand': recommendedCommand,
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
      'release_packaging',
      'M33 release packaging report',
      '${reportRoot.path}/${MacosComputerUseMvpGuidance.releasePackagingJsonFile}',
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
    _latestEntry(
      'm28_screenshot_evidence_intake',
      'Latest M28 screenshot evidence intake',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_m28_screenshot_evidence_intake',
      parentPrefix: 'macos_computer_use_m28_screenshot_evidence_intake_',
      fileName: 'screenshot_evidence_intake.json',
      status: _m28ScreenshotEvidenceIntakeStatus,
      nextAction: _m28ScreenshotEvidenceIntakeNextAction,
      details: _m28ScreenshotEvidenceIntakeDetails,
    ),
    _latestEntry(
      'm29_observe_canary_run_packet',
      'Latest M29 observe canary run packet',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_m29_observe_canary_run_packet',
      parentPrefix: 'macos_computer_use_m29_observe_canary_run_packet_',
      fileName: 'observe_canary_run_packet.json',
      status: _m29ObserveCanaryRunPacketStatus,
      nextAction: _m29ObserveCanaryRunPacketNextAction,
      details: _m29ObserveCanaryRunPacketDetails,
    ),
    _latestEntry(
      'm30_observe_result_intake',
      'Latest M30 observe result intake',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_m30_observe_result_intake',
      parentPrefix: 'macos_computer_use_m30_observe_result_intake_',
      fileName: 'observe_result_intake.json',
      status: _m30ObserveResultIntakeStatus,
      nextAction: _m30ObserveResultIntakeNextAction,
      details: _m30ObserveResultIntakeDetails,
    ),
    _latestEntry(
      'm39_beta_signoff',
      'Latest M39 internal beta sign-off',
      reportRoot,
      (json) => json['schemaName'] == 'macos_computer_use_m39_beta_signoff',
      parentPrefix: 'macos_computer_use_m39_beta_signoff_',
      fileName: MacosComputerUseMvpGuidance.m39BetaSignoffJsonFile,
      status: _m39BetaSignoffStatus,
      nextAction: _m39BetaSignoffNextAction,
      details: _m39BetaSignoffDetails,
    ),
    _latestEntry(
      'm40_production_launch_gate',
      'Latest M40 production launch gate',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_m40_production_launch_gate',
      parentPrefix: 'macos_computer_use_m40_production_launch_gate_',
      fileName: MacosComputerUseMvpGuidance.m40ProductionLaunchGateJsonFile,
      status: _m40ProductionLaunchGateStatus,
      nextAction: _m40ProductionLaunchGateNextAction,
      details: _m40ProductionLaunchGateDetails,
    ),
  ];
  return ReadinessArtifactIndex(
    reportRoot: reportRoot.path,
    entries: List<ReadinessArtifactEntry>.unmodifiable(entries),
    mvpFinalSignoffRehearsal: _mvpFinalSignoffRehearsal(reportRoot, entries),
    nextStepNavigator: buildReadinessNextStepNavigator(reportRoot, entries),
  );
}

ReadinessNextStepNavigator buildReadinessNextStepNavigator(
  Directory reportRoot, [
  List<ReadinessArtifactEntry>? entries,
]) {
  final indexEntries =
      entries ?? buildReadinessArtifactIndex(reportRoot).entries;
  final rehearsal = _mvpFinalSignoffRehearsal(reportRoot, indexEntries);
  final byId = <String, ReadinessArtifactEntry>{
    for (final entry in indexEntries) entry.id: entry,
  };
  final recommendation = _nextStepRecommendation(reportRoot, byId, rehearsal);
  return ReadinessNextStepNavigator(
    status: recommendation.artifactId == 'none'
        ? 'no_action_available'
        : 'ready',
    reportRoot: reportRoot.path,
    recommendation: recommendation,
    operationBoundary: MacosComputerUseOperationBoundary.values,
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
  final m28ScreenshotEvidenceIntakeCommand =
      _m28ScreenshotEvidenceIntakeCommand(reportRoot, byId);
  final m29ObserveCanaryRunPacketCommand = _m29ObserveCanaryRunPacketCommand(
    reportRoot,
    byId,
  );
  final m30ObserveResultIntakeCommand = _m30ObserveResultIntakeCommand(
    reportRoot,
    byId,
  );
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
    m28ScreenshotEvidenceIntakeCommand: m28ScreenshotEvidenceIntakeCommand,
    m29ObserveCanaryRunPacketCommand: m29ObserveCanaryRunPacketCommand,
    m30ObserveResultIntakeCommand: m30ObserveResultIntakeCommand,
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
                entry.id == 'm27_screenshot_request_handoff' ||
                entry.id == 'm28_screenshot_evidence_intake' ||
                entry.id == 'm29_observe_canary_run_packet' ||
                entry.id == 'm30_observe_result_intake' ||
                entry.id == 'm39_beta_signoff' ||
                entry.id == 'm40_production_launch_gate') &&
            entry.exists &&
            entry.status != null &&
            entry.status != 'ready',
      )
      .toList(growable: false);
}

ReadinessNextStepRecommendation _nextStepRecommendation(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
  ReadinessFinalSignoffRehearsal rehearsal,
) {
  final blocked = _firstEntryByPriority(
    entriesById,
    const <String>[
      'm15_action_proposal_handoff',
      'm15_llm_review_canary',
      'm16_approval_packet',
      'm17_execution_rehearsal',
      'm18_execution_handoff',
      'm20_execution_result_intake',
      'm22_post_action_review',
      'm23_cycle_outcome_handoff',
      'm25_next_cycle_seed_handoff',
      'm26_observe_restart_packet',
      'm27_screenshot_request_handoff',
      'm28_screenshot_evidence_intake',
      'm29_observe_canary_run_packet',
      'm30_observe_result_intake',
      'm39_beta_signoff',
      'm40_production_launch_gate',
    ],
    (entry) => entry.exists && entry.status != null && entry.status != 'ready',
  );
  if (blocked != null) {
    return _recommendationForEntry(
      priority: 'resolve_blocked_evidence',
      entry: blocked,
      nextAction:
          blocked.nextAction ??
          'Resolve blocked ${blocked.label} evidence before continuing.',
      recommendedCommand: MacosComputerUseMvpGuidance.artifactIndexCommand
          .replaceFirst('build/integration_test_reports', reportRoot.path),
    );
  }

  final m16Entry = entriesById['m16_approval_packet'];
  if (m16Entry?.status == 'ready' &&
      m16Entry?.details['approvalStatus'] != 'approved') {
    return _recommendationForEntry(
      priority: 'collect_m16_user_approvals',
      entry: m16Entry!,
      nextAction:
          m16Entry.nextAction ??
          'Ask the user to approve exact text, target, and public action before the future execution milestone.',
      recommendedCommand: rehearsal.m16ApprovalPacketCommand,
      requiresUserOperation: true,
    );
  }

  for (final candidate in _commandCandidates(rehearsal)) {
    final entry = entriesById[candidate.artifactId];
    if (entry == null || entry.exists) {
      continue;
    }
    return _recommendationForEntry(
      priority: candidate.priority,
      entry: entry,
      nextAction: candidate.nextAction,
      recommendedCommand: candidate.command,
      requiresUserOperation: candidate.requiresUserOperation,
    );
  }

  final missing = _firstEntryByPriority(
    entriesById,
    MacosComputerUseMvpGuidance.requiredEvidenceIds,
    (entry) => !entry.exists,
  );
  if (missing != null) {
    return _recommendationForEntry(
      priority: 'collect_required_evidence',
      entry: missing,
      nextAction: MacosComputerUseMvpGuidance.missingArtifactNextAction(
        missing.id,
      ),
      recommendedCommand: _requiredEvidenceCommand(missing.id, reportRoot),
      requiresUserOperation: MacosComputerUseMvpGuidance.userOperatedEvidenceIds
          .contains(missing.id),
    );
  }

  final m39Entry = entriesById['m39_beta_signoff'];
  if (m39Entry != null && !m39Entry.exists) {
    return _recommendationForEntry(
      priority: 'run_m39_beta_signoff',
      entry: m39Entry,
      nextAction:
          'Run the M39 internal beta sign-off after MVP evidence and the user-operated action cycle are ready.',
      recommendedCommand: _m39BetaSignoffCommand(reportRoot),
      requiresUserOperation: true,
    );
  }

  final m40Entry = entriesById['m40_production_launch_gate'];
  if (m40Entry != null && !m40Entry.exists) {
    return _recommendationForEntry(
      priority: 'run_m40_production_launch_gate',
      entry: m40Entry,
      nextAction:
          'Run the M40 production launch gate after M39 beta sign-off is ready.',
      recommendedCommand: _m40ProductionLaunchGateCommand(reportRoot),
      requiresUserOperation: true,
    );
  }

  if (rehearsal.finalAggregationCommand != null) {
    return ReadinessNextStepRecommendation(
      priority: 'final_aggregation',
      artifactId: 'mvp_final_signoff',
      artifactLabel: 'MVP final sign-off aggregation',
      artifactStatus: 'ready',
      evidencePath: reportRoot.path,
      nextAction: 'Run final MVP sign-off aggregation.',
      recommendedCommand: rehearsal.finalAggregationCommand,
      boundary:
          'report-only aggregation; TCC and desktop actions remain user-operated',
      requiresUserOperation: false,
    );
  }

  return ReadinessNextStepRecommendation(
    priority: 'none',
    artifactId: 'none',
    artifactLabel: 'No recommended next step',
    artifactStatus: 'missing',
    evidencePath: reportRoot.path,
    nextAction: 'Produce Computer Use readiness evidence before continuing.',
    recommendedCommand: _mvpReadinessPreflightCommand(reportRoot),
    boundary:
        'report-only navigation; TCC and desktop actions remain user-operated',
    requiresUserOperation: false,
  );
}

ReadinessArtifactEntry? _firstEntryByPriority(
  Map<String, ReadinessArtifactEntry> entriesById,
  List<String> priority,
  bool Function(ReadinessArtifactEntry entry) matches,
) {
  for (final id in priority) {
    final entry = entriesById[id];
    if (entry != null && matches(entry)) {
      return entry;
    }
  }
  return null;
}

ReadinessNextStepRecommendation _recommendationForEntry({
  required String priority,
  required ReadinessArtifactEntry entry,
  required String nextAction,
  String? recommendedCommand,
  bool requiresUserOperation = false,
}) {
  return ReadinessNextStepRecommendation(
    priority: priority,
    artifactId: entry.id,
    artifactLabel: entry.label,
    artifactStatus: entry.status ?? (entry.exists ? 'present' : 'missing'),
    evidencePath: entry.path,
    nextAction: nextAction,
    recommendedCommand: recommendedCommand,
    boundary:
        'report-only navigation; TCC and desktop actions remain user-operated',
    requiresUserOperation: requiresUserOperation,
  );
}

List<_NextStepCommandCandidate> _commandCandidates(
  ReadinessFinalSignoffRehearsal rehearsal,
) {
  return <_NextStepCommandCandidate>[
    if (rehearsal.m15ActionProposalCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m15_action_proposal_handoff',
        artifactId: 'm15_action_proposal_handoff',
        command: rehearsal.m15ActionProposalCommand!,
        nextAction:
            'Run the M15 action proposal handoff from the latest ready observe evidence.',
      ),
    if (rehearsal.m15LlmReviewCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m15_llm_review_canary',
        artifactId: 'm15_llm_review_canary',
        command: rehearsal.m15LlmReviewCommand!,
        nextAction:
            'Run the M15 LLM review canary before preparing the approval packet.',
      ),
    if (rehearsal.m16ApprovalPacketCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m16_approval_packet',
        artifactId: 'm16_approval_packet',
        command: rehearsal.m16ApprovalPacketCommand!,
        nextAction:
            'Run the M16 approval packet generator from ready M15 evidence.',
      ),
    if (rehearsal.m17ExecutionRehearsalCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m17_execution_rehearsal',
        artifactId: 'm17_execution_rehearsal',
        command: rehearsal.m17ExecutionRehearsalCommand!,
        nextAction:
            'Run the M17 execution rehearsal from the approved M16 packet.',
      ),
    if (rehearsal.m18ExecutionHandoffCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m18_execution_handoff',
        artifactId: 'm18_execution_handoff',
        command: rehearsal.m18ExecutionHandoffCommand!,
        nextAction:
            'Run the M18 execution handoff before any user-operated runtime step.',
      ),
    if (rehearsal.m20ExecutionResultIntakeCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m20_execution_result_intake',
        artifactId: 'm20_execution_result_intake',
        command: rehearsal.m20ExecutionResultIntakeCommand!,
        nextAction:
            'Run the M20 result intake after the user-operated runtime step.',
        requiresUserOperation: true,
      ),
    if (rehearsal.m22PostActionReviewCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m22_post_action_review',
        artifactId: 'm22_post_action_review',
        command: rehearsal.m22PostActionReviewCommand!,
        nextAction: 'Run the M22 post-action review from ready M20 evidence.',
      ),
    if (rehearsal.m23CycleOutcomeHandoffCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m23_cycle_outcome_handoff',
        artifactId: 'm23_cycle_outcome_handoff',
        command: rehearsal.m23CycleOutcomeHandoffCommand!,
        nextAction:
            'Run the M23 cycle outcome handoff to close or restart the cycle.',
      ),
    if (rehearsal.m25NextCycleSeedHandoffCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m25_next_cycle_seed_handoff',
        artifactId: 'm25_next_cycle_seed_handoff',
        command: rehearsal.m25NextCycleSeedHandoffCommand!,
        nextAction:
            'Run the M25 next-cycle seed handoff before preparing the next observe pass.',
      ),
    if (rehearsal.m26ObserveRestartPacketCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m26_observe_restart_packet',
        artifactId: 'm26_observe_restart_packet',
        command: rehearsal.m26ObserveRestartPacketCommand!,
        nextAction:
            'Run the M26 observe restart packet for the next M14 observe pass.',
      ),
    if (rehearsal.m27ScreenshotRequestHandoffCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m27_screenshot_request_handoff',
        artifactId: 'm27_screenshot_request_handoff',
        command: rehearsal.m27ScreenshotRequestHandoffCommand!,
        nextAction:
            'Run the M27 screenshot request handoff before asking for a manual screenshot.',
      ),
    if (rehearsal.m28ScreenshotEvidenceIntakeCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m28_screenshot_evidence_intake',
        artifactId: 'm28_screenshot_evidence_intake',
        command: rehearsal.m28ScreenshotEvidenceIntakeCommand!,
        nextAction:
            'Run the M28 screenshot evidence intake after the user provides a screenshot.',
        requiresUserOperation: true,
      ),
    if (rehearsal.m29ObserveCanaryRunPacketCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m29_observe_canary_run_packet',
        artifactId: 'm29_observe_canary_run_packet',
        command: rehearsal.m29ObserveCanaryRunPacketCommand!,
        nextAction:
            'Run the M29 observe canary run packet before asking the user to run M14.',
      ),
    if (rehearsal.m30ObserveResultIntakeCommand != null)
      _NextStepCommandCandidate(
        priority: 'run_m30_observe_result_intake',
        artifactId: 'm30_observe_result_intake',
        command: rehearsal.m30ObserveResultIntakeCommand!,
        nextAction:
            'Run the M30 observe result intake after the user-produced M14 summary is ready.',
        requiresUserOperation: true,
      ),
  ];
}

String? _requiredEvidenceCommand(String artifactId, Directory reportRoot) {
  switch (artifactId) {
    case 'release_artifact':
      return 'bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-safe-inputs';
    case 'canary_history':
      return 'bash tool/run_macos_computer_use_live_canary.sh --ci';
    case 'manual_tcc':
      return MacosComputerUseMvpGuidance.manualTccCommand;
    case 'desktop_action_canary':
      return MacosComputerUseMvpGuidance.desktopActionCanaryCommand;
    case 'llm_canary':
      return MacosComputerUseMvpGuidance.llmCanaryCommand;
    default:
      return _mvpReadinessPreflightCommand(reportRoot);
  }
}

String _m39BetaSignoffCommand(Directory reportRoot) {
  return '${MacosComputerUseMvpGuidance.m39BetaSignoffCommand} '
      '--root ${_shellQuote(reportRoot.path)}';
}

String _m40ProductionLaunchGateCommand(Directory reportRoot) {
  return '${MacosComputerUseMvpGuidance.m40ProductionLaunchGateCommand} '
      '--root ${_shellQuote(reportRoot.path)}';
}

class _NextStepCommandCandidate {
  const _NextStepCommandCandidate({
    required this.priority,
    required this.artifactId,
    required this.command,
    required this.nextAction,
    this.requiresUserOperation = false,
  });

  final String priority;
  final String artifactId;
  final String command;
  final String nextAction;
  final bool requiresUserOperation;
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
  final m30Entry = entriesById['m30_observe_result_intake'];
  if (m30Entry?.status == 'ready') {
    final m30Command = m30Entry?.details['m15ActionProposalHandoffCommand']
        ?.toString();
    if (m30Command != null && m30Command.trim().isNotEmpty) {
      return m30Command;
    }
    final m30M14Summary =
        m30Entry?.details['sourceM14ObserveCanarySummary']?.toString() ?? '';
    if (m30M14Summary.isNotEmpty) {
      return <String>[
        'bash',
        'tool/run_macos_computer_use_m15_action_proposal_handoff.sh',
        '--root',
        reportRoot.path,
        '--m14-summary',
        m30M14Summary,
      ].map(_shellQuote).join(' ');
    }
  }
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

String? _m28ScreenshotEvidenceIntakeCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final m27Entry = entriesById['m27_screenshot_request_handoff'];
  final m27Path = m27Entry?.path ?? '';
  if (m27Path.isEmpty || m27Entry?.status != 'ready') {
    return null;
  }
  if (m27Entry?.details['returnMilestone'] != 'M14') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh',
    '--root',
    reportRoot.path,
    '--m27-handoff',
    m27Path,
    '--screenshot',
    '<user-provided-real-app-screenshot.png>',
  ].map(_shellQuote).join(' ');
}

String? _m29ObserveCanaryRunPacketCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final m28Entry = entriesById['m28_screenshot_evidence_intake'];
  final m28Path = m28Entry?.path ?? '';
  if (m28Path.isEmpty || m28Entry?.status != 'ready') {
    return null;
  }
  if (m28Entry?.details['returnMilestone'] != 'M14') {
    return null;
  }
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m29_observe_canary_run_packet.sh',
    '--root',
    reportRoot.path,
    '--m28-intake',
    m28Path,
  ].map(_shellQuote).join(' ');
}

String? _m30ObserveResultIntakeCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  final m29Entry = entriesById['m29_observe_canary_run_packet'];
  final m29Path = m29Entry?.path ?? '';
  if (m29Path.isEmpty || m29Entry?.status != 'ready') {
    return null;
  }
  if (m29Entry?.details['returnMilestone'] != 'M14') {
    return null;
  }
  final llmEntry = entriesById['llm_canary'];
  final m14Path = llmEntry?.path ?? '';
  final hasM14ObserveSummary =
      m14Path.isNotEmpty &&
      _basename(
        File(m14Path).parent.path,
      ).startsWith('macos_computer_use_real_app_observe_canary_');
  final m14Json = hasM14ObserveSummary ? _readJsonObject(File(m14Path)) : null;
  final m14Gate = m14Json?['m14EvidenceGate'];
  final m14Ready =
      m14Json?['ready'] == true &&
      m14Gate is Map &&
      m14Gate['status'] == 'ready';
  return <String>[
    'bash',
    'tool/run_macos_computer_use_m30_observe_result_intake.sh',
    '--root',
    reportRoot.path,
    '--m29-packet',
    m29Path,
    '--m14-summary',
    hasM14ObserveSummary && m14Ready
        ? m14Path
        : '<user-produced-m14-canary-summary.json>',
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

String? _m28ScreenshotEvidenceIntakeStatus(Map<String, dynamic> json) {
  final gate = json['m28ScreenshotEvidenceIntakeGate'];
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

String? _m28ScreenshotEvidenceIntakeNextAction(Map<String, dynamic> json) {
  final gate = json['m28ScreenshotEvidenceIntakeGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m28ScreenshotEvidenceIntakeStatus(json);
  if (status == 'ready') {
    return 'Run the M14 observe-only canary with the user-provided screenshot, then continue the approval-bound observe/action cycle.';
  }
  if (status == 'blocked') {
    return 'Resolve M28 screenshot evidence intake blockers before running the M14 observe-only canary.';
  }
  return null;
}

Map<String, Object?> _m28ScreenshotEvidenceIntakeDetails(
  Map<String, dynamic> json,
) {
  final gate = json['m28ScreenshotEvidenceIntakeGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final evidence = json['screenshotEvidence'];
  final evidenceMap = evidence is Map<String, dynamic> ? evidence : null;
  final nextObserveInput = json['nextObserveInput'];
  final nextObserveInputMap = nextObserveInput is Map<String, dynamic>
      ? nextObserveInput
      : null;
  final commands = json['commands'];
  final commandsMap = commands is Map<String, dynamic> ? commands : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM27ScreenshotRequestHandoff':
        json['sourceM27ScreenshotRequestHandoff']?.toString(),
    'targetApp': json['targetApp']?.toString(),
    'targetIntent': json['targetIntent']?.toString(),
    if (evidenceMap != null) ...<String, Object?>{
      'screenshotPath': evidenceMap['path']?.toString(),
      'screenshotExists': evidenceMap['exists'],
      'screenshotSizeBytes': evidenceMap['sizeBytes'],
      'screenshotExtension': evidenceMap['extension']?.toString(),
    },
    if (nextObserveInputMap != null) ...<String, Object?>{
      'returnMilestone': nextObserveInputMap['returnMilestone']?.toString(),
      'observeBoundary': nextObserveInputMap['boundary']?.toString(),
      'screenshotProvided': nextObserveInputMap['provided'],
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

String? _m29ObserveCanaryRunPacketStatus(Map<String, dynamic> json) {
  final gate = json['m29ObserveCanaryRunPacketGate'];
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

String? _m29ObserveCanaryRunPacketNextAction(Map<String, dynamic> json) {
  final gate = json['m29ObserveCanaryRunPacketGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m29ObserveCanaryRunPacketStatus(json);
  if (status == 'ready') {
    return 'Ask the user to run the M14 observe-only canary command with the recorded screenshot, then review the new M14 evidence.';
  }
  if (status == 'blocked') {
    return 'Resolve M29 observe canary run packet blockers before asking the user to run M14.';
  }
  return null;
}

Map<String, Object?> _m29ObserveCanaryRunPacketDetails(
  Map<String, dynamic> json,
) {
  final gate = json['m29ObserveCanaryRunPacketGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final evidence = json['screenshotEvidence'];
  final evidenceMap = evidence is Map<String, dynamic> ? evidence : null;
  final runPacket = json['m14ObserveRunPacket'];
  final runPacketMap = runPacket is Map<String, dynamic> ? runPacket : null;
  final commands = json['commands'];
  final commandsMap = commands is Map<String, dynamic> ? commands : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM28ScreenshotEvidenceIntake':
        json['sourceM28ScreenshotEvidenceIntake']?.toString(),
    'targetApp': json['targetApp']?.toString(),
    'targetIntent': json['targetIntent']?.toString(),
    if (evidenceMap != null) ...<String, Object?>{
      'screenshotPath': evidenceMap['path']?.toString(),
      'screenshotExists': evidenceMap['exists'],
      'screenshotSizeBytes': evidenceMap['sizeBytes'],
      'screenshotExtension': evidenceMap['extension']?.toString(),
    },
    if (runPacketMap != null) ...<String, Object?>{
      'returnMilestone': runPacketMap['returnMilestone']?.toString(),
      'observeBoundary': runPacketMap['boundary']?.toString(),
      'readyForUserOperation': runPacketMap['readyForUserOperation'],
      'userOperated': runPacketMap['userOperated'],
      'runPacketCommand': runPacketMap['command']?.toString(),
    },
    if (commandsMap != null) ...<String, Object?>{
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

String? _m30ObserveResultIntakeStatus(Map<String, dynamic> json) {
  final gate = json['m30ObserveResultIntakeGate'];
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

String? _m30ObserveResultIntakeNextAction(Map<String, dynamic> json) {
  final gate = json['m30ObserveResultIntakeGate'];
  if (gate is Map<String, dynamic>) {
    final nextAction = gate['nextAction'];
    if (nextAction is String && nextAction.trim().isNotEmpty) {
      return nextAction;
    }
  }
  final status = _m30ObserveResultIntakeStatus(json);
  if (status == 'ready') {
    return 'Return to M15 action proposal handoff using the ready M14 observe evidence from this intake.';
  }
  if (status == 'blocked') {
    return 'Resolve M30 observe result intake blockers before returning to M15.';
  }
  return null;
}

Map<String, Object?> _m30ObserveResultIntakeDetails(Map<String, dynamic> json) {
  final gate = json['m30ObserveResultIntakeGate'];
  final gateMap = gate is Map<String, dynamic> ? gate : null;
  final sourceAlignment = json['sourceAlignment'];
  final sourceAlignmentMap = sourceAlignment is Map<String, dynamic>
      ? sourceAlignment
      : null;
  final m14Evidence = json['m14ObserveEvidence'];
  final m14EvidenceMap = m14Evidence is Map<String, dynamic>
      ? m14Evidence
      : null;
  final nextHandoff = json['nextHandoff'];
  final nextHandoffMap = nextHandoff is Map<String, dynamic>
      ? nextHandoff
      : null;
  final commands = json['commands'];
  final commandsMap = commands is Map<String, dynamic> ? commands : null;
  return <String, Object?>{
    'executionBoundary': json['executionBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'llmBoundary': json['llmBoundary']?.toString(),
    'sourceM29ObserveCanaryRunPacket': json['sourceM29ObserveCanaryRunPacket']
        ?.toString(),
    'sourceM14ObserveCanarySummary': json['sourceM14ObserveCanarySummary']
        ?.toString(),
    'returnToMilestone': json['returnToMilestone']?.toString(),
    'targetApp': json['targetApp']?.toString(),
    'targetIntent': json['targetIntent']?.toString(),
    'screenshotPath': json['screenshotPath']?.toString(),
    if (sourceAlignmentMap != null) ...<String, Object?>{
      'targetAppMatches': sourceAlignmentMap['targetAppMatches'],
      'targetIntentMatches': sourceAlignmentMap['targetIntentMatches'],
      'screenshotPathMatches': sourceAlignmentMap['screenshotPathMatches'],
    },
    if (m14EvidenceMap != null) ...<String, Object?>{
      'm14EvidenceGateStatus': m14EvidenceMap['gateStatus']?.toString(),
      'candidateTargetCount': m14EvidenceMap['candidateTargetCount'],
      'textEntryTargetCount': m14EvidenceMap['textEntryTargetCount'],
      'publicActionTargetCount': m14EvidenceMap['publicActionTargetCount'],
      'confirmationRequirementCount':
          m14EvidenceMap['confirmationRequirementCount'],
      'observationOnly': m14EvidenceMap['observationOnly'],
    },
    if (nextHandoffMap != null) ...<String, Object?>{
      'nextHandoffReturnMilestone': nextHandoffMap['returnMilestone']
          ?.toString(),
      'nextHandoffBoundary': nextHandoffMap['boundary']?.toString(),
      'nextHandoffCommand': nextHandoffMap['command']?.toString(),
    },
    if (commandsMap != null) ...<String, Object?>{
      'm15ActionProposalHandoffCommand': commandsMap['m15ActionProposalHandoff']
          ?.toString(),
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

String? _m39BetaSignoffStatus(Map<String, dynamic> json) {
  final review = json['betaReviewSummary'];
  if (review is Map<String, dynamic>) {
    final reviewStatus = review['status']?.toString();
    if (reviewStatus == 'ready_for_internal_beta') {
      return 'ready';
    }
    if (reviewStatus != null && reviewStatus.isNotEmpty) {
      return 'blocked';
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  final status = json['status']?.toString();
  if (status != null && status.isNotEmpty) {
    return status;
  }
  return null;
}

String? _m39BetaSignoffNextAction(Map<String, dynamic> json) {
  final status = _m39BetaSignoffStatus(json);
  if (status == 'ready') {
    return 'Use M39 beta evidence as an input to the M40 production launch gate.';
  }
  if (status == 'blocked') {
    return 'Resolve M39 beta sign-off blockers before preparing the production launch gate.';
  }
  return null;
}

Map<String, Object?> _m39BetaSignoffDetails(Map<String, dynamic> json) {
  final review = json['betaReviewSummary'];
  final reviewMap = review is Map<String, dynamic> ? review : null;
  final gates = _jsonList(json['gates']);
  return <String, Object?>{
    'milestone': json['milestone']?.toString(),
    'automationBoundary': json['automationBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'readyGateIds': _jsonStringList(json['readyGateIds']),
    'blockedGateIds': _jsonStringList(json['blockedGateIds']),
    'userOperatedGateIds': _jsonStringList(json['userOperatedGateIds']),
    'gateCount': gates.length,
    if (reviewMap != null) ...<String, Object?>{
      'reviewStatus': reviewMap['status']?.toString(),
      'reviewReadyGateIds': _jsonStringList(reviewMap['readyGateIds']),
      'reviewBlockedGateIds': _jsonStringList(reviewMap['blockedGateIds']),
      'blockedUserOperatedGateIds': _jsonStringList(
        reviewMap['blockedUserOperatedGateIds'],
      ),
      'blockedAutomationSafeGateIds': _jsonStringList(
        reviewMap['blockedAutomationSafeGateIds'],
      ),
      'operationBoundarySummary': reviewMap['operationBoundarySummary']
          ?.toString(),
    },
  };
}

String? _m40ProductionLaunchGateStatus(Map<String, dynamic> json) {
  final review = json['launchReviewSummary'];
  if (review is Map<String, dynamic>) {
    final reviewStatus = review['status']?.toString();
    if (reviewStatus == 'ready_for_production_launch') {
      return 'ready';
    }
    if (reviewStatus != null && reviewStatus.isNotEmpty) {
      return 'blocked';
    }
  }
  final ready = json['ready'];
  if (ready is bool) {
    return ready ? 'ready' : 'blocked';
  }
  final status = json['status']?.toString();
  if (status != null && status.isNotEmpty) {
    return status;
  }
  return null;
}

String? _m40ProductionLaunchGateNextAction(Map<String, dynamic> json) {
  final status = _m40ProductionLaunchGateStatus(json);
  if (status == 'ready') {
    return 'Archive M40 launch evidence as the production Computer Use release gate.';
  }
  if (status == 'blocked') {
    return 'Resolve M40 production launch blockers before release sign-off.';
  }
  return null;
}

Map<String, Object?> _m40ProductionLaunchGateDetails(
  Map<String, dynamic> json,
) {
  final review = json['launchReviewSummary'];
  final reviewMap = review is Map<String, dynamic> ? review : null;
  final gates = _jsonList(json['gates']);
  return <String, Object?>{
    'milestone': json['milestone']?.toString(),
    'automationBoundary': json['automationBoundary']?.toString(),
    'tccBoundary': json['tccBoundary']?.toString(),
    'desktopActionBoundary': json['desktopActionBoundary']?.toString(),
    'readyGateIds': _jsonStringList(json['readyGateIds']),
    'blockedGateIds': _jsonStringList(json['blockedGateIds']),
    'userOperatedGateIds': _jsonStringList(json['userOperatedGateIds']),
    'gateCount': gates.length,
    if (reviewMap != null) ...<String, Object?>{
      'reviewStatus': reviewMap['status']?.toString(),
      'reviewReadyGateIds': _jsonStringList(reviewMap['readyGateIds']),
      'reviewBlockedGateIds': _jsonStringList(reviewMap['blockedGateIds']),
      'blockedUserOperatedGateIds': _jsonStringList(
        reviewMap['blockedUserOperatedGateIds'],
      ),
      'blockedAutomationSafeGateIds': _jsonStringList(
        reviewMap['blockedAutomationSafeGateIds'],
      ),
      'operationBoundarySummary': reviewMap['operationBoundarySummary']
          ?.toString(),
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
