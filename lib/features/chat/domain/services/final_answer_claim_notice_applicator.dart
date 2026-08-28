import 'blocked_mutation_notice.dart';
import 'coding_verification_claim_guard.dart';
import 'final_answer_claim_notice_input.dart';
import 'narrated_transcript_claim_guard.dart';
import 'unwritten_file_claim_guard.dart';

export 'final_answer_claim_notice_input.dart';

// ChatNotifier decomposition collaborator: final-answer-claim-notice-applicator

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
