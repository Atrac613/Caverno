import '../../entities/conversation_workflow.dart';
import '../short_prompt_contract_builder.dart';

// ChatNotifier decomposition collaborator: saved-task-authored-request-text

/// The request text a claim guard should judge, on a turn the plan executor
/// started rather than the user.
///
/// An executor-driven turn's latest user message is not a user message. It is
/// a template `ConversationPlanExecutionCoordinator` writes around the saved
/// task -- "Saved task ID: ...", "Work only on this saved task", "After the
/// saved validation step succeeds" -- and a guard that scans it for intent is
/// reading the harness's own prose back to itself.
///
/// That is not hypothetical. `FinalAnswerClaimDetector.looksLikeFileSideEffectRequest`
/// matches the bare substring `save`, and the template contains it eight times
/// plus 保存 from 「保存されたタスク」, none of them from the user. The gate is
/// therefore open on every executor-driven coding turn, so whether a fabricated
/// `unexecuted_file_save` result appears rests entirely on the response-side
/// heuristic. Session 16e9d5a3 lost that coin flip on an inspection-only task:
/// the harness injected a write_file failure for a write nobody requested, the
/// extraction step is required to raise an open loop for any
/// `code=unexecuted_file_save`, and the turn wrote "File save for version
/// update was not executed; needs to be retried" into persistent memory.
///
/// The saved task carries the text that *was* authored -- its title, notes,
/// validation command and target files all come from the plan, not the
/// template -- so the guard reads that instead and the template goes unread.
final class SavedTaskAuthoredRequestText {
  const SavedTaskAuthoredRequestText();

  /// [latestUserContent] when the user typed it, the saved task's own fields
  /// when the plan executor wrote it.
  ///
  /// Falls back to [latestUserContent] when the task carries no authored text,
  /// because an empty string would disarm every guard that reads this rather
  /// than narrowing one.
  ///
  /// `ShortPromptContractBuilder` wraps a bare user request in a single task
  /// whose title is a fixed placeholder and whose fields are otherwise empty --
  /// the request itself lives in the spec's goal, not on the task. Reading that
  /// placeholder as the authored request would disarm the guard on a turn
  /// whose user text was never examined at all, so the wrapper falls through.
  String resolve({
    required String latestUserContent,
    required ConversationWorkflowTask? savedTask,
  }) {
    if (savedTask == null || _isSyntheticRequestWrapper(savedTask)) {
      return latestUserContent;
    }
    final authored = <String>[
      savedTask.title.trim(),
      savedTask.notes.trim(),
      savedTask.validationCommand.trim(),
      ...savedTask.targetFiles.map((targetFile) => targetFile.trim()),
    ].where((line) => line.isNotEmpty).join('\n');
    return authored.isEmpty ? latestUserContent : authored;
  }

  bool _isSyntheticRequestWrapper(ConversationWorkflowTask task) =>
      task.id.startsWith('request-') &&
      task.title.trim() == ShortPromptContractBuilder.syntheticRequestTaskTitle;
}
