import '../entities/tool_call_info.dart';
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
    CodingVerificationClaimGuard verificationClaimGuard =
        const CodingVerificationClaimGuard(),
    NarratedTranscriptClaimGuard narratedTranscriptClaimGuard =
        const NarratedTranscriptClaimGuard(),
    UnwrittenFileClaimGuard unwrittenFileClaimGuard =
        const UnwrittenFileClaimGuard(),
  }) : _verificationClaimGuard = verificationClaimGuard,
       _narratedTranscriptClaimGuard = narratedTranscriptClaimGuard,
       _unwrittenFileClaimGuard = unwrittenFileClaimGuard;

  static const unwrittenFileTransformId = 'unwritten_file_claim_notice';
  static const narratedTranscriptTransformId =
      'narrated_transcript_claim_notice';
  static const verificationTransformId = 'verification_claim_notice';

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
