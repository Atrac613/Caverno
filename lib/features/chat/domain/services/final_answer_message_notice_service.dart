import '../../../../core/utils/logger.dart';
import '../entities/message.dart';
import '../entities/tool_call_info.dart';
import 'final_answer_claim_detector.dart';
import 'harness_notice_visibility.dart';
import 'tool_call_execution_policy.dart';
import 'unexecuted_final_answer_tool_request_policy.dart';

final class FinalAnswerMessageMutation {
  const FinalAnswerMessageMutation(this.messages, {this.transformId});

  final List<Message> messages;
  final String? transformId;
}

/// Applies evidence-backed notices to the last assistant message.
final class FinalAnswerMessageNoticeService {
  const FinalAnswerMessageNoticeService();

  static const unexecutedFileSideEffectTransformId =
      'unexecuted_file_side_effect_notice';
  static const timedOutCommandClaimTransformId =
      'timed_out_command_claim_notice';
  static const failedCommandClaimTransformId = 'failed_command_claim_notice';

  static const _claims = FinalAnswerClaimDetector();
  static const _executionPolicy = ToolCallExecutionPolicy();
  static const _visibility = HarnessNoticeVisibility();

  FinalAnswerMessageMutation? appendUnexecutedToolRequest(
    List<Message> messages,
  ) {
    if (messages.isEmpty || messages.last.role != MessageRole.assistant) {
      return null;
    }
    const policy = UnexecutedFinalAnswerToolRequestPolicy();
    if (!policy.looksLikeUnexecutedToolRequest(messages.last.content)) {
      return null;
    }
    return _logOnly(
      messages,
      UnexecutedFinalAnswerToolRequestPolicy.notice,
      transformId: UnexecutedFinalAnswerToolRequestPolicy.transformId,
    );
  }

  FinalAnswerMessageMutation? appendUnexecutedFileSideEffect(
    List<Message> messages,
    List<ToolResultInfo> toolResults,
  ) => _mutate(messages, (content) {
    const notice =
        'The requested file save was not executed because no successful file-operation tool result is available. '
        'Treat any save, create, or download claim above as unverified.';
    if (content.contains(notice) ||
        !_claims.looksLikeUnsupportedFileSideEffectClaim(
          content,
          toolResults: toolResults,
        )) {
      return content;
    }
    return _append(content, notice);
  }, transformId: unexecutedFileSideEffectTransformId);

  FinalAnswerMessageMutation? appendUnexecutedCommandAction(
    List<Message> messages,
    List<ToolResultInfo> toolResults,
  ) {
    if (!_claims.hasUnexecutedCommandActionResult(toolResults)) return null;
    final ranSomething = _claims.hasSuccessfulCommandExecutionResult(
      toolResults,
    );
    if (ranSomething) {
      const nextStep = FinalAnswerClaimDetector.unexecutedNextStepNotice;
      const nextStepTransformId =
          HarnessNoticeVisibility.unexecutedNextStepTransformId;
      // Only the asserted shape is a statement the tool results contradict, so
      // only that one is worth putting in front of the reader -- it replaces
      // the sentence it corrects. A future-tense next step asserts nothing
      // false, which leaves the notice as plumbing the log can hold.
      if (!_assertsCommandExecution(messages)) {
        return _logOnly(messages, nextStep, transformId: nextStepTransformId);
      }
      return _mutate(
            messages,
            (content) =>
                _claims.messageContentWithUnexecutedCommandActionNotice(
                  content,
                  notice: nextStep,
                ),
            transformId: nextStepTransformId,
          ) ??
          FinalAnswerMessageMutation(
            messages,
            transformId: nextStepTransformId,
          );
    }
    const transformId = 'unexecuted_command_action_notice';
    return _mutate(
          messages,
          (content) => _claims.messageContentWithUnexecutedCommandActionNotice(
            content,
            notice: FinalAnswerClaimDetector.unexecutedCommandActionNotice,
          ),
          transformId: transformId,
        ) ??
        FinalAnswerMessageMutation(messages, transformId: transformId);
  }

  FinalAnswerMessageMutation? appendUnverifiedReadOnlyInspection(
    List<Message> messages,
    List<ToolResultInfo> toolResults,
  ) {
    if (!_claims.hasUnverifiedReadOnlyInspectionClaimResult(toolResults)) {
      return null;
    }
    const notice =
        'The local file or project state claim above is unverified because no successful read-only inspection tool result is available for that claim. '
        'Treat any file existence, file content, directory listing, or path verification claim above as unverified.';
    return _mutate(
          messages,
          (content) =>
              _claims.messageContentWithUnverifiedReadOnlyInspectionNotice(
                content,
                notice: notice,
              ),
          transformId: 'unverified_read_only_inspection_notice',
        ) ??
        FinalAnswerMessageMutation(
          messages,
          transformId: 'unverified_read_only_inspection_notice',
        );
  }

  FinalAnswerMessageMutation? replaceTimedOutCommandClaim(
    List<Message> messages,
    List<ToolResultInfo> toolResults,
  ) {
    if (!hasTimedOutCommandResult(toolResults)) return null;
    const notice =
        'A command timed out, so any success, pass, or completion claim is unverified. '
        'Treat the command result as incomplete until a successful command-execution tool result is available.';
    return _prependClaimCorrection(
      messages,
      notice,
      transformId: timedOutCommandClaimTransformId,
    );
  }

  FinalAnswerMessageMutation? replaceFailedCommandClaim(
    List<Message> messages,
    List<ToolResultInfo> toolResults,
  ) {
    final exitCode = firstFailedCommandExitCode(toolResults);
    if (exitCode == null) return null;
    final notice =
        'A command exited with non-zero exit code $exitCode, so any '
        'success, upload, release, pass, or completion claim is unverified. '
        'Treat the command as failed until a later command-execution tool '
        'result exits successfully.';
    return _prependClaimCorrection(
      messages,
      notice,
      transformId: failedCommandClaimTransformId,
    );
  }

  bool hasTimedOutCommandResult(List<ToolResultInfo> toolResults) =>
      toolResults.any(_executionPolicy.toolResultTimedOut);

  int? firstFailedCommandExitCode(List<ToolResultInfo> toolResults) {
    int? unrecoveredExitCode;
    for (final result in toolResults) {
      if (!_executionPolicy.isCommandExecutionTool(result.name)) continue;
      final name = result.name.trim().toLowerCase();
      if (const {
            'process_start',
            'process_status',
            'process_wait',
          }.contains(name) ||
          _executionPolicy.toolResultTimedOut(result) ||
          // A refused argument never reached a shell, so it neither fails the
          // turn's claims nor clears an earlier failure.
          _executionPolicy.toolResultRejectedBeforeExecution(result)) {
        continue;
      }
      final exitCode = _executionPolicy.toolResultExitCode(result).exitCode;
      if (exitCode != null && exitCode != 0) {
        unrecoveredExitCode ??= exitCode;
      } else if (exitCode == 0) {
        unrecoveredExitCode = null;
      }
    }
    return unrecoveredExitCode;
  }

  FinalAnswerMessageMutation? _prependClaimCorrection(
    List<Message> messages,
    String notice, {
    required String transformId,
  }) => _mutate(messages, (content) {
    if (!_claims.looksLikeCommandSuccessClaim(content)) return content;
    return _claims.messageContentWithPrependedClaimCorrectionNotice(
      content,
      notice,
    );
  }, transformId: transformId);

  FinalAnswerMessageMutation? _mutate(
    List<Message> messages,
    String Function(String content) transform, {
    String? transformId,
  }) {
    if (messages.isEmpty || messages.last.role != MessageRole.assistant) {
      return null;
    }
    final content = transform(messages.last.content);
    if (content == messages.last.content) return null;
    final updated = [...messages];
    updated[updated.length - 1] = messages.last.copyWith(content: content);
    return FinalAnswerMessageMutation(updated, transformId: transformId);
  }

  bool _assertsCommandExecution(List<Message> messages) {
    if (messages.isEmpty || messages.last.role != MessageRole.assistant) {
      return false;
    }
    return _claims.looksLikeAssertedCommandExecution(
      messages.last.content.trim(),
    );
  }

  /// Records that [notice] fired without putting it in front of the reader.
  ///
  /// The messages come back untouched, so the firing survives as the transform
  /// ID on the turn exit and as this log line.
  FinalAnswerMessageMutation _logOnly(
    List<Message> messages,
    String notice, {
    required String transformId,
  }) {
    assert(_visibility.isLogOnly(transformId));
    appLog('[$transformId] $notice');
    return FinalAnswerMessageMutation(messages, transformId: transformId);
  }

  static String _append(String content, String notice) =>
      '${content.trimRight()}\n\n$notice';
}
