import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/tool_call_info.dart';
import 'blocked_mutation_notice.dart';
import 'coding_verification_claim_guard.dart';
import 'immutable_json_snapshot.dart';
import 'narrated_transcript_claim_guard.dart';
import 'unwritten_file_claim_guard.dart';

// ChatNotifier decomposition collaborator: final-answer-claim-notice-applicator

/// Immutable owner-scoped evidence used to annotate one final answer.
final class FinalAnswerClaimNoticeInput {
  FinalAnswerClaimNoticeInput({
    required this.isCodingWorkspaceOrMode,
    required this.candidateContent,
    required List<ToolResultInfo> toolResults,
    required List<String> executedCommands,
    required String? projectRoot,
    required this.offersCommandExecution,
  }) : toolResults = List<ToolResultInfo>.unmodifiable(
         toolResults.map(_freezeToolResult),
       ),
       executedCommands = List<String>.unmodifiable(executedCommands),
       projectRoot = projectRoot?.trim();

  final bool isCodingWorkspaceOrMode;
  final String candidateContent;
  final List<ToolResultInfo> toolResults;
  final List<String> executedCommands;
  final String? projectRoot;
  final bool offersCommandExecution;

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) {
    return ToolResultInfo(
      id: result.id,
      name: result.name,
      arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
      result: result.result,
      outcome: _freezeOutcome(result.outcome),
    );
  }

  /// Carries the structured outcome across the freeze.
  ///
  /// Dropping it here left every claim check inside this applicator reading
  /// prose even where `ToolOutcome` already held the answer, and the loss was
  /// invisible because each consumer has a text fallback: the typed mutation
  /// path in `UnwrittenFileClaimGuard`, its no-op-mutation check (so a
  /// byte-identical write counted as a change), and the whole structured
  /// test-count path in `CodingVerificationClaimGuard`, which returns early on
  /// a null outcome and therefore never ran here at all.
  ///
  /// `ToolOutcome` and the value classes it holds are immutable apart from the
  /// mutation list's own identity, so only that needs wrapping to keep the
  /// freeze contract.
  static ToolOutcome? _freezeOutcome(ToolOutcome? outcome) {
    if (outcome == null) return null;
    return ToolOutcome(
      exitCode: outcome.exitCode,
      processState: outcome.processState,
      fileMutations: List<ToolFileMutation>.unmodifiable(
        outcome.fileMutations,
      ),
      readOutcome: outcome.readOutcome,
      testOutcome: outcome.testOutcome,
      fileChanged: outcome.fileChanged,
      contentHash: outcome.contentHash,
      diagnosticCount: outcome.diagnosticCount,
      diagnosticErrorCount: outcome.diagnosticErrorCount,
      diagnosticWarningCount: outcome.diagnosticWarningCount,
      testPassedCount: outcome.testPassedCount,
      testFailedCount: outcome.testFailedCount,
      testSkippedCount: outcome.testSkippedCount,
    );
  }
}

/// Final content and owner-scoped transform IDs produced by the applicator.
final class FinalAnswerClaimNoticeResult {
  FinalAnswerClaimNoticeResult({
    required this.content,
    required List<String> transformIds,
  }) : transformIds = List<String>.unmodifiable(transformIds);

  final String content;
  final List<String> transformIds;
}

/// Applies final-answer claim notices using only supplied owner evidence.
final class FinalAnswerClaimNoticeApplicator {
  const FinalAnswerClaimNoticeApplicator({
    BlockedMutationNotice blockedMutationNotice = const BlockedMutationNotice(),
    CodingVerificationClaimGuard verificationClaimGuard =
        const CodingVerificationClaimGuard(),
    NarratedTranscriptClaimGuard narratedTranscriptClaimGuard =
        const NarratedTranscriptClaimGuard(),
    UnwrittenFileClaimGuard unwrittenFileClaimGuard =
        const UnwrittenFileClaimGuard(),
  }) : _blockedMutationNotice = blockedMutationNotice,
       _verificationClaimGuard = verificationClaimGuard,
       _narratedTranscriptClaimGuard = narratedTranscriptClaimGuard,
       _unwrittenFileClaimGuard = unwrittenFileClaimGuard;

  static const blockedMutationTransformId = 'blocked_mutation_notice';
  static const unwrittenFileTransformId = 'unwritten_file_claim_notice';
  static const narratedTranscriptTransformId =
      'narrated_transcript_claim_notice';
  static const verificationTransformId = 'verification_claim_notice';

  final BlockedMutationNotice _blockedMutationNotice;
  final CodingVerificationClaimGuard _verificationClaimGuard;
  final NarratedTranscriptClaimGuard _narratedTranscriptClaimGuard;
  final UnwrittenFileClaimGuard _unwrittenFileClaimGuard;

  FinalAnswerClaimNoticeResult apply(FinalAnswerClaimNoticeInput input) {
    if (!input.isCodingWorkspaceOrMode) {
      return FinalAnswerClaimNoticeResult(
        content: input.candidateContent,
        transformIds: const [],
      );
    }

    var content = input.candidateContent;
    final transformIds = <String>[];

    // Stated first, and from tool results alone: what the turn did to files is
    // the ground the claim notices below are measured against, so it is the
    // one line that must not depend on reading the answer.
    final blockedMutations = _blockedMutationNotice.assess(input.toolResults);
    if (blockedMutations.hasBlockedMutations) {
      final notice = blockedMutations.buildNotice();
      if (!content.contains(notice)) {
        content = _appendNotice(content, notice);
        transformIds.add(blockedMutationTransformId);
      }
    }

    final projectRoot = input.projectRoot;
    if (projectRoot != null && projectRoot.isNotEmpty) {
      final assessment = _unwrittenFileClaimGuard.assess(
        candidateResponse: content,
        toolResults: input.toolResults,
        projectRoot: projectRoot,
      );
      if (assessment.hasClaims) {
        final notice = assessment.buildNotice();
        if (!content.contains(notice)) {
          content = _appendNotice(content, notice);
          transformIds.add(unwrittenFileTransformId);
        }
      }
    }

    if (input.offersCommandExecution) {
      final assessment = _narratedTranscriptClaimGuard.assess(
        candidateResponse: content,
        toolResults: input.toolResults,
        additionalExecutedCommands: input.executedCommands,
      );
      if (assessment.hasUnexecutedCommands) {
        final notice = assessment.buildNotice();
        if (!content.contains(notice)) {
          content = _appendNotice(content, notice);
          transformIds.add(narratedTranscriptTransformId);
        }
      }
    }

    final verificationAssessment = _verificationClaimGuard.assess(
      candidateResponse: content,
      toolResults: input.toolResults,
    );
    if (verificationAssessment.hasMismatch) {
      final notice = verificationAssessment.buildNotice();
      if (!content.contains(notice)) {
        content = _appendNotice(content, notice);
        transformIds.add(verificationTransformId);
      }
    }

    return FinalAnswerClaimNoticeResult(
      content: content,
      transformIds: transformIds,
    );
  }

  String _appendNotice(String content, String notice) {
    return '${content.trimRight()}\n\n$notice';
  }
}
