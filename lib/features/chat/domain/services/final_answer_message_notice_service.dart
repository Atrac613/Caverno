import '../entities/message.dart';
import '../entities/tool_call_info.dart';
import 'final_answer_claim_detector.dart';
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

  FinalAnswerMessageMutation? appendUnexecutedToolRequest(
    List<Message> messages,
  ) => _mutate(messages, (content) {
    const policy = UnexecutedFinalAnswerToolRequestPolicy();
    if (content.contains(UnexecutedFinalAnswerToolRequestPolicy.notice) ||
        !policy.looksLikeUnexecutedToolRequest(content)) {
      return content;
    }
    return _append(content, UnexecutedFinalAnswerToolRequestPolicy.notice);
  }, transformId: UnexecutedFinalAnswerToolRequestPolicy.transformId);

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
    final notice = ranSomething
        ? FinalAnswerClaimDetector.unexecutedNextStepNotice
        : FinalAnswerClaimDetector.unexecutedCommandActionNotice;
    return _mutate(
          messages,
          (content) => _claims.messageContentWithUnexecutedCommandActionNotice(
            content,
            notice: notice,
          ),
          transformId: ranSomething
              ? 'unexecuted_next_step_notice'
              : 'unexecuted_command_action_notice',
        ) ??
        FinalAnswerMessageMutation(
          messages,
          transformId: ranSomething
              ? 'unexecuted_next_step_notice'
              : 'unexecuted_command_action_notice',
        );
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
          _executionPolicy.toolResultTimedOut(result)) {
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

  static String _append(String content, String notice) =>
      '${content.trimRight()}\n\n$notice';
}
