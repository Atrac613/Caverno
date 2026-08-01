import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';

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

  bool shouldSkipCompletedToolResultFinalAnswerRecovery(
    TurnFinalizationRecoveryInput input,
  ) {
    final candidate = input.candidateResponse.trim();
    final streamedFinalAnswer = input.streamedFinalAnswer?.trim();
    if (streamedFinalAnswer != null &&
        streamedFinalAnswer.isNotEmpty &&
        candidate != streamedFinalAnswer) {
      return false;
    }
    return shouldSkipCompletedToolResultCodingContinuationRecovery(input);
  }

  bool shouldSkipCompletedToolResultCodingContinuationRecovery(
    TurnFinalizationRecoveryInput input,
  ) {
    final candidate = input.candidateResponse.trim();
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
  ) {
    return input.hasSuccessfulFileMutationEvidence ||
        input.hasSuccessfulCommandExecutionEvidence;
  }

  bool looksLikeCompletedCodingFinalAnswer(String content) {
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

  bool looksLikeCodingFutureAction(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return _containsAny(normalized, const [
          'i will inspect',
          'i will check',
          'i will read',
          'i will port',
          'i will implement',
          'i will update',
          'i will edit',
          'i will modify',
          'i will write',
          'i will create',
          "i'll inspect",
          "i'll check",
          "i'll read",
          "i'll port",
          "i'll implement",
          "i'll update",
          "i'll edit",
          "i'll modify",
          "i'll write",
          "i'll create",
          'i am going to inspect',
          'i am going to check',
          'i am going to read',
          'i am going to port',
          'i am going to implement',
          'i am going to update',
          'i am going to edit',
          'i am going to modify',
          'i am going to write',
          'i am going to create',
          'next i will',
          'now i will',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059],
          [0x8abf, 0x67fb, 0x3057, 0x307e, 0x3059],
          [0x8aad, 0x307f, 0x307e, 0x3059],
          [
            0x30dd,
            0x30fc,
            0x30c6,
            0x30a3,
            0x30f3,
            0x30b0,
            0x3057,
            0x307e,
            0x3059,
          ],
          [0x79fb, 0x690d, 0x3057, 0x307e, 0x3059],
          [0x5b9f, 0x88c5, 0x3057, 0x307e, 0x3059],
          [0x66f4, 0x65b0, 0x3057, 0x307e, 0x3059],
          [0x7de8, 0x96c6, 0x3057, 0x307e, 0x3059],
          [0x4f5c, 0x6210, 0x3057, 0x307e, 0x3059],
          [0x66f8, 0x304d, 0x307e, 0x3059],
        ]);
  }

  String turnFinalizationCandidateText({
    required String content,
    required String? streamedFinalAnswer,
  }) {
    final streamedCandidate = streamedFinalAnswer?.trim();
    if (streamedCandidate != null && streamedCandidate.isNotEmpty) {
      return streamedCandidate;
    }
    return ContentParser.stripToolArtifacts(content).trim();
  }

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

  bool _containsAny(String value, List<String> markers) {
    return markers.any(value.contains);
  }

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) {
    return sequences.any(
      (sequence) => _containsCodeUnitSequence(text, sequence),
    );
  }

  bool _containsCodeUnitSequence(String text, List<int> sequence) {
    if (sequence.isEmpty || text.length < sequence.length) {
      return false;
    }
    final units = text.codeUnits;
    for (var index = 0; index <= units.length - sequence.length; index++) {
      var matched = true;
      for (var offset = 0; offset < sequence.length; offset++) {
        if (units[index + offset] != sequence[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return true;
      }
    }
    return false;
  }
}
