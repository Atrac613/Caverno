import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../entities/tool_call_info.dart';
import 'coding/coding_future_action_detector.dart';
import 'immutable_json_snapshot.dart';
import 'tool_terminal_success_policy.dart';

// ChatNotifier decomposition collaborator: turn-finalization-recovery-policy

final class TurnFinalizationRecoveryInput {
  TurnFinalizationRecoveryInput({
    required this.candidateResponse,
    required this.streamedFinalAnswer,
    required List<ToolResultInfo> toolResults,
    required this.hasTimedOutCommandResult,
    required this.hasFailedCommandValidation,
    required this.hasUnexecutedCommandActionResult,
    required this.hasUnexecutedFileSideEffectResult,
    required this.hasSuccessfulCurrentSavedValidation,
    required this.hasSuccessfulFileMutationEvidence,
    required this.hasSuccessfulCommandExecutionEvidence,
  }) : toolResults = List<ToolResultInfo>.unmodifiable(
         toolResults.map(_freezeToolResult),
       );

  final String candidateResponse;
  final String? streamedFinalAnswer;
  final List<ToolResultInfo> toolResults;
  final bool hasTimedOutCommandResult;
  final bool hasFailedCommandValidation;
  final bool hasUnexecutedCommandActionResult;
  final bool hasUnexecutedFileSideEffectResult;
  final bool hasSuccessfulCurrentSavedValidation;
  final bool hasSuccessfulFileMutationEvidence;
  final bool hasSuccessfulCommandExecutionEvidence;

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) {
    return ToolResultInfo(
      id: result.id,
      name: result.name,
      arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
      result: result.result,
    );
  }
}

final class TurnFinalizationRecoveryPolicy {
  const TurnFinalizationRecoveryPolicy();

  bool hasTerminalGoalSuccess(
    List<ToolResultInfo> results, {
    required bool hasSavedValidation,
    required bool hasGitLifecycle,
  }) {
    const terminalPolicy = ToolTerminalSuccessPolicy();
    return results.isNotEmpty &&
        (results.any(
              (result) => terminalPolicy.terminalMessage(result.result) != null,
            ) ||
            hasSavedValidation ||
            hasGitLifecycle);
  }

  bool shouldSkipCompletedToolResultFinalAnswerRecovery(
    TurnFinalizationRecoveryInput input,
  ) {
    final candidate = ContentParser.stripModelHistoryArtifacts(
      input.candidateResponse,
    );
    final streamedFinalAnswer = ContentParser.stripModelHistoryArtifacts(
      input.streamedFinalAnswer ?? '',
    );
    if (streamedFinalAnswer.isNotEmpty && candidate != streamedFinalAnswer) {
      return false;
    }
    return shouldSkipCompletedToolResultCodingContinuationRecovery(input);
  }

  bool shouldSkipCompletedToolResultCodingContinuationRecovery(
    TurnFinalizationRecoveryInput input,
  ) {
    final candidate = ContentParser.stripModelHistoryArtifacts(
      input.candidateResponse,
    );
    if (candidate.isEmpty) {
      return false;
    }
    if (input.hasTimedOutCommandResult ||
        input.hasFailedCommandValidation ||
        input.hasUnexecutedCommandActionResult ||
        input.hasUnexecutedFileSideEffectResult) {
      return false;
    }
    if (input.hasSuccessfulCurrentSavedValidation) {
      return true;
    }
    if (!hasSuccessfulFinalAnswerToolEvidence(input)) {
      return false;
    }
    return looksLikeCompletedCodingFinalAnswer(candidate) &&
        !looksLikeCodingFutureAction(candidate);
  }

  bool hasSuccessfulFinalAnswerToolEvidence(
    TurnFinalizationRecoveryInput input,
  ) =>
      input.hasSuccessfulFileMutationEvidence ||
      input.hasSuccessfulCommandExecutionEvidence;

  bool looksLikeCompletedCodingFinalAnswer(String content) {
    content = ContentParser.stripModelHistoryArtifacts(content);
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty || normalized.length > 1600) {
      return false;
    }
    final hasTarget =
        _containsAny(normalized, const [
          'code',
          'source',
          'file',
          'project',
          'dart',
          'python',
          'script',
          'logic',
          'entrypoint',
          'implementation',
          'pubspec',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x30b3, 0x30fc, 0x30c9],
          [0x30bd, 0x30fc, 0x30b9],
          [0x30d5, 0x30a1, 0x30a4, 0x30eb],
          [0x30d7, 0x30ed, 0x30b8, 0x30a7, 0x30af, 0x30c8],
          [0x30b9, 0x30af, 0x30ea, 0x30d7, 0x30c8],
          [0x30ed, 0x30b8, 0x30c3, 0x30af],
          [0x65e2, 0x5b58],
        ]);
    if (!hasTarget) {
      return false;
    }
    return _containsAny(normalized, const [
          'completed',
          'complete',
          'created',
          'implemented',
          'updated',
          'modified',
          'wrote',
          'written',
          'saved',
          'verified',
          'confirmed',
          'checked',
          'tested',
          'ran',
          'executed',
          'successfully',
          'passed',
          'passes',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x3057, 0x307e, 0x3057, 0x305f],
          [0x5b8c, 0x4e86],
          [0x6210, 0x529f],
          [0x6e08, 0x307f],
        ]);
  }

  bool looksLikeCodingFutureAction(String content) =>
      const CodingFutureActionDetector().matches(content);

  String turnFinalizationCandidateText({
    required String content,
    required String? streamedFinalAnswer,
  }) => ContentParser.stripModelHistoryArtifacts(
    (streamedFinalAnswer?.trim().isNotEmpty ?? false)
        ? streamedFinalAnswer!
        : content,
  );

  String contentBeforeFinalizationCandidate({
    required String currentContent,
    required String candidateResponse,
  }) {
    final candidate = candidateResponse.trim();
    if (candidate.isEmpty) {
      return currentContent.trimRight();
    }
    final index = currentContent.lastIndexOf(candidate);
    if (index < 0) {
      return '';
    }
    return currentContent.substring(0, index).trimRight();
  }

  bool _containsAny(String value, List<String> markers) =>
      markers.any(value.contains);

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) =>
      sequences.any(
        (units) =>
            units.isNotEmpty && text.contains(String.fromCharCodes(units)),
      );
}
