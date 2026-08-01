import 'dart:convert';

import '../entities/chat_turn_owner.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';
import 'narrated_transcript_claim_guard.dart';

// ChatNotifier decomposition collaborator: narrated-transcript-repair-planner

/// Immutable owner-scoped evidence used to plan transcript repair.
final class NarratedTranscriptRepairInput {
  NarratedTranscriptRepairInput({
    required this.owner,
    required this.verificationEnabled,
    required this.isCodingWorkspaceOrMode,
    required this.isPlanning,
    required this.candidateResponse,
    required List<ToolResultInfo> ownerToolResults,
    required List<String> ownerExecutedCommands,
    required Set<String> attemptedSignatures,
    required this.maximumAttempts,
    required this.feedbackId,
  }) : ownerToolResults = List<ToolResultInfo>.unmodifiable(
         ownerToolResults.map(_freezeToolResult),
       ),
       ownerExecutedCommands = List<String>.unmodifiable(ownerExecutedCommands),
       attemptedSignatures = Set<String>.unmodifiable(attemptedSignatures);

  final ChatTurnOwner owner;
  final bool verificationEnabled;
  final bool isCodingWorkspaceOrMode;
  final bool isPlanning;
  final String candidateResponse;
  final List<ToolResultInfo> ownerToolResults;
  final List<String> ownerExecutedCommands;
  final Set<String> attemptedSignatures;
  final int maximumAttempts;
  final String feedbackId;

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) {
    return ToolResultInfo(
      id: result.id,
      name: result.name,
      arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
      result: result.result,
    );
  }
}

/// A deterministic repair request that the notifier may apply to its owner.
final class NarratedTranscriptRepairPlan {
  const NarratedTranscriptRepairPlan._({
    required this.owner,
    required this.signature,
    required this.assessment,
    required this.feedback,
  });

  final ChatTurnOwner owner;
  final String signature;
  final NarratedTranscriptClaimAssessment assessment;
  final ToolResultInfo feedback;
}

enum NarratedTranscriptRepairNoPlanReason {
  verificationDisabled,
  nonCodingWorkspace,
  planning,
  noUnexecutedCommands,
  attemptLimitReached,
  repeatedSignature,
}

/// A typed planning outcome that preserves why no repair was requested.
final class NarratedTranscriptRepairDisposition {
  const NarratedTranscriptRepairDisposition.planned(
    NarratedTranscriptRepairPlan value,
  ) : plan = value,
      noPlanReason = null;

  const NarratedTranscriptRepairDisposition.noPlan(
    NarratedTranscriptRepairNoPlanReason reason,
  ) : plan = null,
      noPlanReason = reason;

  final NarratedTranscriptRepairPlan? plan;
  final NarratedTranscriptRepairNoPlanReason? noPlanReason;
}

/// Plans narrated transcript repair without mutating turn state.
final class NarratedTranscriptRepairPlanner {
  const NarratedTranscriptRepairPlanner();

  static const _claimGuard = NarratedTranscriptClaimGuard();

  NarratedTranscriptRepairPlan? plan(NarratedTranscriptRepairInput input) {
    return evaluate(input).plan;
  }

  NarratedTranscriptRepairDisposition evaluate(
    NarratedTranscriptRepairInput input,
  ) {
    if (!input.verificationEnabled) {
      return const NarratedTranscriptRepairDisposition.noPlan(
        NarratedTranscriptRepairNoPlanReason.verificationDisabled,
      );
    }
    if (!input.isCodingWorkspaceOrMode) {
      return const NarratedTranscriptRepairDisposition.noPlan(
        NarratedTranscriptRepairNoPlanReason.nonCodingWorkspace,
      );
    }
    if (input.isPlanning) {
      return const NarratedTranscriptRepairDisposition.noPlan(
        NarratedTranscriptRepairNoPlanReason.planning,
      );
    }

    final assessment = _claimGuard.assess(
      candidateResponse: input.candidateResponse,
      toolResults: input.ownerToolResults,
      additionalExecutedCommands: input.ownerExecutedCommands,
    );
    if (!assessment.hasUnexecutedCommands) {
      return const NarratedTranscriptRepairDisposition.noPlan(
        NarratedTranscriptRepairNoPlanReason.noUnexecutedCommands,
      );
    }
    if (input.attemptedSignatures.length >= input.maximumAttempts) {
      return const NarratedTranscriptRepairDisposition.noPlan(
        NarratedTranscriptRepairNoPlanReason.attemptLimitReached,
      );
    }

    final signature = jsonEncode(assessment.unexecutedCommands);
    if (input.attemptedSignatures.contains(signature)) {
      return const NarratedTranscriptRepairDisposition.noPlan(
        NarratedTranscriptRepairNoPlanReason.repeatedSignature,
      );
    }

    final unexecutedCommands = List<String>.unmodifiable(
      assessment.unexecutedCommands,
    );
    final immutableAssessment = NarratedTranscriptClaimAssessment(
      unexecutedCommands: unexecutedCommands,
    );
    final feedback = ToolResultInfo(
      id: input.feedbackId,
      name: 'narrated_transcript_check',
      arguments: Map<String, dynamic>.unmodifiable({
        'trigger': 'narratedTranscript',
        'unexecuted_commands': unexecutedCommands,
      }),
      result: jsonEncode({
        'schema': 'caverno_narrated_transcript_check',
        'ok': false,
        'code': 'narrated_transcript_commands_not_executed',
        'unexecuted_commands': unexecutedCommands,
        'error':
            'The answer presents a terminal transcript, but these commands '
            'have no execution record in this turn, so the output shown for '
            'them is not a real observation.',
        'required_action':
            'Execute the narrated commands now with local_execute_command '
            'and base the answer on their real output, or rewrite the answer '
            'to state plainly that these checks were not run.',
      }),
    );
    return NarratedTranscriptRepairDisposition.planned(
      NarratedTranscriptRepairPlan._(
        owner: input.owner,
        signature: signature,
        assessment: immutableAssessment,
        feedback: feedback,
      ),
    );
  }
}
