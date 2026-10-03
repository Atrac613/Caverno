import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../core/utils/logger.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_workflow.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/entities/turn_diff.dart';
import '../../chat/domain/services/project_task_implementation_instructions.dart';
import '../../chat/presentation/slash_commands/slash_command_prompt_template.dart';
import '../domain/entities/project_task_git_state.dart';
import '../domain/project_task_progress.dart';

/// Runs the user-started task through decomposition, implementation one
/// subtask per turn, the dedicated review route, and a commit of the reviewed
/// work. Each stage must produce an explicit result before the next begins,
/// and every stage change is reported through [onProgress].
final class ProjectTaskReviewWorkflow {
  ProjectTaskReviewWorkflow({
    required this.conversationId,
    required this.readConversation,
    required this.isSelected,
    required this.isWaitingForUser,
    required this.send,
    required this.commit,
    required this.readGitState,
    this.decompose,
    this.sendStep,
    this.markSubtaskDone,
    this.onProgress,
    this.inheritedFiles = const [],
    this.recordPriorChanges,
    this.readTaskPatch,
  });

  final String conversationId;
  final Conversation? Function() readConversation;
  final bool Function() isSelected;
  final bool Function() isWaitingForUser;
  final Future<bool> Function(String prompt, {required bool codeReview}) send;

  /// Sends the commit turn. The commit itself is a model tool call, so it
  /// passes through the same approval gate as any other git write.
  final Future<bool> Function(String prompt) commit;

  /// Reads HEAD and the status of [paths]; null when git cannot be read.
  final Future<ProjectTaskGitState?> Function(List<String> paths) readGitState;

  /// Splits the objective into ordered subtasks and saves them as the
  /// thread's execution tasks. An empty result runs the task as one step.
  final Future<List<ConversationWorkflowTask>> Function(String objective)?
  decompose;

  /// Sends a subtask turn before the last one. These turns are judged by
  /// their marker, not by goal completion, which only the last turn records.
  final Future<bool> Function(String prompt)? sendStep;

  /// Records a subtask as completed in the thread's execution progress.
  final Future<void> Function(String taskId)? markSubtaskDone;
  final void Function(ProjectTaskProgress progress)? onProgress;

  /// Changes an earlier run of this task captured with its file tools and
  /// left uncommitted. They are reviewed and committed as this task's own:
  /// in session b2971ae0 the re-run found the work done, had no change of
  /// its own to show, and could only stop.
  final List<TurnDiffFile> inheritedFiles;

  /// Records the files this task changed before the coming turn, so the
  /// completion gate counts them. Its file-change check is per turn: in
  /// session 6f3ea3cf the edits were made in two subtask turns and the last
  /// subtask only verified them, so completion was refused and the workflow
  /// stopped with every subtask done.
  final Future<void> Function(List<String> paths)? recordPriorChanges;

  /// The net change of the task's files against HEAD, one entry per file, or
  /// null when git cannot be read and the captured patches are reviewed.
  ///
  /// Captured patches are per turn and stack. In session be9dbba9, eight
  /// earlier runs had left 29 of them for 7 files, 44,502 characters, and the
  /// workflow stopped before review. The net change is also exactly what the
  /// commit stage commits.
  final Future<List<TurnDiffFile>?> Function(List<String> paths)? readTaskPatch;

  static const maxRepairRounds = 2;
  static const maxMissingDiffRetries = 1;
  static const _ready = 'PROJECT_TASK_READY_FOR_REVIEW';
  static const _subtaskDone = 'PROJECT_TASK_SUBTASK_DONE';
  static const _clean = 'PROJECT_TASK_REVIEW_CLEAN';
  static const _findings = 'PROJECT_TASK_REVIEW_FINDINGS';

  Future<ProjectTaskReviewResult> run() async {
    stopReason = null;
    _report(const ProjectTaskProgress(phase: ProjectTaskPhase.decompose));
    final task = readConversation();
    if (task == null || !isSelected() || task.messages.isNotEmpty) {
      return _stop('the task thread is not a new, selected thread');
    }
    final objective = task.goal?.normalizedObjective;
    if (objective == null) return _stop('the task has no goal objective');

    final decomposed = await decompose?.call(objective) ?? const [];
    if (!_canContinue(readConversation())) return _stop(_notContinuable);
    final subtasks = sendStep == null
        ? const <ConversationWorkflowTask>[]
        : decomposed;
    final subtaskCount = decomposed.isEmpty ? 1 : decomposed.length;
    // Earlier subtask turns may hold the task's only file changes, so the
    // first round's change check counts from before the first subtask.
    final diffBaseline = readConversation()!.turnDiffs.length;
    for (var index = 0; index < subtasks.length - 1; index++) {
      _report(
        ProjectTaskProgress(
          phase: ProjectTaskPhase.implement,
          subtaskIndex: index,
          subtaskCount: subtaskCount,
        ),
      );
      final stopped = await _runSubtask(objective, subtasks, index);
      if (stopped != null) return stopped;
    }
    _report(
      ProjectTaskProgress(
        phase: ProjectTaskPhase.implement,
        subtaskIndex: subtaskCount - 1,
        subtaskCount: subtaskCount,
      ),
    );

    var implementation = subtasks.length > 1
        ? _subtaskPrompt(objective, subtasks, subtasks.length - 1)
        : '''Implement this roadmap task in the current coding project:

$objective

Read the cited roadmap and relevant code, make the smallest complete change, and run relevant verification.$_inheritedNote ${ProjectTaskImplementationInstructions.completionScope} Respect all approval and user-input gates. Do not commit, push, or publish, and leave the roadmap item's status unchanged: both happen in a separate step after review. When implementation and verification are finished, end your final response with the exact line $_ready. If anything remains incomplete, explain it and omit that line.''';

    for (var repairRound = 0; repairRound <= maxRepairRounds; repairRound++) {
      if (repairRound > 0) {
        _report(
          _progress.copyWith(
            phase: ProjectTaskPhase.repair,
            repairRound: repairRound,
          ),
        );
      }
      Conversation? after;
      for (var retry = 0; retry <= maxMissingDiffRetries; retry++) {
        final before = readConversation();
        if (!_canContinue(before)) return _stop(_notContinuable);
        final previousMessageCount = before!.messages.length;
        final previousDiffCount = repairRound == 0
            ? diffBaseline
            : before.turnDiffs.length;
        final priorPaths = _taskPaths(before);
        if (priorPaths.isNotEmpty) await recordPriorChanges?.call(priorPaths);
        if (!await send(implementation, codeReview: false)) {
          return _stop(
            'the implementation turn ended without a recorded goal '
            'completion (goal: ${readConversation()?.goal?.status.name})',
          );
        }
        after = readConversation();
        if (!_canContinue(after)) return _stop(_notContinuable);
        final response = _lastAssistant(after!, previousMessageCount);
        if (response == null) {
          return _stop('the implementation turn saved no assistant response');
        }
        if (after.turnDiffs.length > previousDiffCount ||
            (repairRound == 0 && inheritedFiles.isNotEmpty)) {
          if (!_endsWithMarker(response.content, _ready)) {
            return _stop(
              'the implementation response does not end with $_ready '
              '(last line: "${_lastLine(response.content)}")',
            );
          }
          if (repairRound == 0 && decomposed.isNotEmpty) {
            final failed = _failedVerification(
              after,
              decomposed.last,
              number: subtaskCount,
            );
            if (failed != null) return _stop(failed);
            await markSubtaskDone?.call(decomposed.last.id);
          }
          break;
        }
        if (retry == maxMissingDiffRetries) {
          return _stop('the implementation captured no reviewable file change');
        }
        implementation =
            '''The previous implementation turn captured no reviewable file change. Any claimed edits or test results without tool evidence are unverified. Inspect the current files, then perform the remaining implementation with file tools and run relevant verification. ${ProjectTaskImplementationInstructions.completionScope} Do not repeat the same whole-file reads. Respect approval and user-input gates. If the task is blocked or already complete, explain the evidence and omit $_ready. End with exactly $_ready only after the work and verification are actually complete.''';
      }

      final patch = await _reviewPatch(after!);
      if (patch == null) {
        return _stop(
          'the task patch is empty, binary, truncated, or too large',
        );
      }
      final template = builtInSlashCommandPromptTemplates.firstWhere(
        (candidate) => candidate.id == 'review',
      );
      final reviewPrompt =
          '''${template.expand(args: 'Only the task changes in the patch below', commandName: 'review')}

The patch below is this task's change to the files its file tools edited${inheritedFiles.isEmpty ? '' : ', including changes an earlier run of this task left uncommitted'}. Review these changes and relevant surrounding code. Begin this review turn by calling read_file on the relevant changed files; wait for successful results and reconcile the patch with their current contents before giving findings or reporting a clean review. Do not answer directly from the supplied patch or conversation history. Reads from earlier implementation or repair turns are historical evidence, not current review inspections. Do not review unrelated pre-existing changes in the working tree. If the patch cannot be reconciled with the working tree, explain the limit and do not report a clean review.

```diff
$patch
```

After your findings and verification limits, end with exactly one of these lines:
$_clean — only when there are no actionable findings and the patch was reviewable
$_findings — when there are actionable findings
If review is incomplete, omit both markers.

Start by calling read_file for these task files, then wait for results before producing review prose:
${_taskPaths(after).map((path) => '- $path').join('\n')}''';
      _report(_progress.copyWith(phase: ProjectTaskPhase.review));
      final beforeReviewCount = after.messages.length;
      if (!await send(reviewPrompt, codeReview: true)) {
        return _stop('the review turn did not complete');
      }
      final reviewed = readConversation();
      if (!_canContinue(reviewed)) return _stop(_notContinuable);
      final review = _lastAssistant(reviewed!, beforeReviewCount);
      if (review == null) return _stop('the review turn saved no response');
      if (_endsWithMarker(review.content, _clean)) {
        return _commit(reviewed, objective);
      }
      if (!_endsWithMarker(review.content, _findings)) {
        return _stop(
          'the review ended without $_clean or $_findings '
          '(last line: "${_lastLine(review.content)}")',
        );
      }
      if (repairRound == maxRepairRounds) {
        _report(_progress.copyWith(outcome: ProjectTaskOutcome.findingsRemain));
        return ProjectTaskReviewResult.findingsRemain;
      }
      // Each repair used to fix only the cited instance, and the next review
      // of the whole patch flagged its neighbour: in session 40851e45 a
      // cleanup restored a logger's level and propagate but not its
      // handlers, three rounds running, so the task ended uncommitted.
      implementation =
          '''Fix the actionable findings from the dedicated code review below. Inspect the cited code and fix the underlying defect behind each finding, not only the cited line: where the same reasoning applies to closely related state, cases, or code paths in this task's changes, fix those too, because the next review reads the whole patch again. Keep repairs task-related, and rerun relevant verification. ${ProjectTaskImplementationInstructions.completionScope} Respect approval and user-input gates. Do not commit, push, or publish. End with the exact line $_ready only when the fixes and verification are complete; otherwise explain what remains and omit the line.

${ContentParser.stripModelHistoryArtifacts(review.content)}''';
    }
    return _stop('the repair rounds ended without a review result');
  }

  /// Marks the roadmap item done and commits the reviewed task files.
  ///
  /// Success is read from git, not from the response: HEAD must move and none
  /// of the task's files may remain uncommitted. Before this stage existed a
  /// clean review ended the workflow with the work uncommitted, and the
  /// dashboard moved on to the next roadmap task over it.
  Future<ProjectTaskReviewResult> _commit(
    Conversation conversation,
    String objective,
  ) async {
    _report(_progress.copyWith(phase: ProjectTaskPhase.commit));
    final paths = _taskPaths(conversation);
    final before = await readGitState(paths);
    if (before == null) {
      return _stop('git state could not be read before the commit');
    }
    if (!_canContinue(readConversation())) return _stop(_notContinuable);
    final prompt =
        '''The dedicated review found no actionable findings. Finish this roadmap task by recording it in the repository:

$objective

1. Open the cited roadmap entry. If it is not already marked done, mark it done following that document's own conventions. Change nothing else in the roadmap.
2. Inspect git status and the diff, then stage only the task files listed below and the roadmap file. Do not stage unrelated pre-existing changes.
3. Commit with a message that follows this repository's commit conventions. Keep the subject to one short line of at most 72 characters and put any details in a second -m paragraph (git_execute_command keeps quoted arguments together), even if earlier commits in the log ran their details into the subject. Do not push, publish, amend, or rewrite history.

Respect all approval gates. If the commit cannot be made, explain why.

Task files:
${paths.map((path) => '- $path').join('\n')}''';
    if (!await commit(prompt)) {
      return _stop('the commit turn did not complete');
    }
    if (!_canContinue(readConversation())) return _stop(_notContinuable);
    final after = await readGitState(paths);
    if (after == null) {
      return _stop('git state could not be read after the commit');
    }
    if (after.head == before.head) {
      return _stop('the commit turn recorded no new commit');
    }
    if (after.dirtyPaths.isNotEmpty) {
      return _stop(
        'task files remain uncommitted: ${after.dirtyPaths.join(', ')}',
      );
    }
    _report(_progress.copyWith(outcome: ProjectTaskOutcome.committed));
    return ProjectTaskReviewResult.committed;
  }

  /// Runs subtask [index] of [subtasks] as one turn. Returns the stop result,
  /// or null when the subtask finished and was recorded.
  Future<ProjectTaskReviewResult?> _runSubtask(
    String objective,
    List<ConversationWorkflowTask> subtasks,
    int index,
  ) async {
    final before = readConversation();
    if (!_canContinue(before)) return _stop(_notContinuable);
    final number = index + 1;
    if (!await sendStep!(_subtaskPrompt(objective, subtasks, index))) {
      return _stop(
        'the turn for subtask $number did not complete '
        '(goal: ${readConversation()?.goal?.status.name})',
      );
    }
    final after = readConversation();
    if (!_canContinue(after)) return _stop(_notContinuable);
    final response = _lastAssistant(after!, before!.messages.length);
    if (response == null) {
      return _stop('the turn for subtask $number saved no assistant response');
    }
    if (!_endsWithMarker(response.content, _subtaskDone)) {
      return _stop(
        'the response for subtask $number does not end with $_subtaskDone '
        '(last line: "${_lastLine(response.content)}")',
      );
    }
    final failed = _failedVerification(after, subtasks[index], number: number);
    if (failed != null) return _stop(failed);
    await markSubtaskDone?.call(subtasks[index].id);
    return null;
  }

  /// Why [subtask] must not be recorded as done, or null when it may be.
  ///
  /// The app's own verification writes this progress when the turn's tests
  /// fail. Recording the subtask as done on the model's marker anyway would
  /// overwrite that verdict with one judged from prose, and the progress bar
  /// would show failed work as finished.
  String? _failedVerification(
    Conversation conversation,
    ConversationWorkflowTask subtask, {
    required int number,
  }) {
    final progress = conversation.executionProgressForTask(subtask.id);
    if (progress == null) return null;
    if (progress.status != ConversationWorkflowTaskStatus.blocked &&
        progress.validationStatus !=
            ConversationExecutionValidationStatus.failed) {
      return null;
    }
    final detail = [progress.lastValidationSummary, progress.blockedReason]
        .map((text) => text.trim())
        .firstWhere(
          (text) => text.isNotEmpty,
          orElse: () => progress.status.name,
        );
    return 'subtask $number ended with failed verification: $detail';
  }

  String _subtaskPrompt(
    String objective,
    List<ConversationWorkflowTask> subtasks,
    int index,
  ) {
    final last = index == subtasks.length - 1;
    final outline = [
      for (final (position, subtask) in subtasks.indexed)
        '${position + 1}. '
            '${position < index
                ? '[done] '
                : position == index
                ? '[now] '
                : ''}'
            '${subtask.title}'
            '${subtask.targetFiles.isEmpty ? '' : ' (likely files: ${subtask.targetFiles.join(', ')})'}',
    ].join('\n');
    final scope = last
        ? 'Do the last subtask now, then confirm the whole task is complete and verified. ${ProjectTaskImplementationInstructions.completionScope} Respect all approval and user-input gates. Do not commit, push, or publish, and leave the roadmap item\'s status unchanged: both happen in a separate step after review. When implementation and verification of the whole task are finished, end your final response with the exact line $_ready. If anything remains incomplete, explain it and omit that line.'
        : 'Do only subtask ${index + 1} now. Make its change with file tools and run verification relevant to it. Respect all approval and user-input gates. Do not start later subtasks, do not mark the goal complete, do not commit, push, or publish, and leave the roadmap item\'s status unchanged. When this subtask is finished, end your final response with the exact line $_subtaskDone. If it cannot be finished, explain why and omit that line.';
    return '''Implement this roadmap task in the current coding project, one subtask at a time:

$objective

Subtasks:
$outline

Read the cited roadmap and relevant code before editing.$_inheritedNote $scope''';
  }

  ProjectTaskProgress _progress = const ProjectTaskProgress(
    phase: ProjectTaskPhase.decompose,
  );

  void _report(ProjectTaskProgress progress) {
    _progress = progress;
    onProgress?.call(progress);
  }

  List<String> _taskPaths(Conversation conversation) =>
      {for (final file in _taskFiles(conversation)) file.filePath}.toList();

  /// This thread's captured files, then each inherited file this thread did
  /// not touch: a path both changed is reviewed through this thread's patch.
  List<TurnDiffFile> _taskFiles(Conversation conversation) {
    final own = conversation.turnDiffs
        .where((diff) => diff.source == TurnDiffSource.tool)
        .expand((diff) => diff.files)
        .toList();
    final ownPaths = {for (final file in own) file.filePath};
    return [
      ...inheritedFiles.where((file) => !ownPaths.contains(file.filePath)),
      ...own,
    ];
  }

  String get _inheritedNote => inheritedFiles.isEmpty
      ? ''
      : '\n\nAn earlier run of this task left these changes uncommitted: '
            '${{for (final file in inheritedFiles) file.filePath}.join(', ')}. Treat '
            'them as this task\'s work so far: inspect them, finish anything '
            'missing, and verify the result with an execution command. If they '
            'already complete the task, do not edit files only to show a '
            'change.';

  /// Why the last [run] returned [ProjectTaskReviewResult.stopped].
  ///
  /// Every stop used to return the same bare result. In session 1d76c878 the
  /// review never started, and nothing recorded whether the goal status, the
  /// marker line, or the patch was the reason.
  String? stopReason;

  static const _notContinuable =
      'the task thread is no longer selected or is waiting for the user';

  ProjectTaskReviewResult _stop(String reason) {
    stopReason = reason;
    _report(
      _progress.copyWith(
        outcome: ProjectTaskOutcome.stopped,
        stopReason: reason,
      ),
    );
    appLog(
      '[ProjectTaskReview] stopped: $reason; conversation=$conversationId',
    );
    return ProjectTaskReviewResult.stopped;
  }

  String _lastLine(String content) {
    final line = ContentParser.stripModelHistoryArtifacts(
      content,
    ).trimRight().split('\n').last.trim();
    return line.length <= 120 ? line : '${line.substring(0, 120)}...';
  }

  bool _canContinue(Conversation? conversation) =>
      conversation?.id == conversationId && isSelected() && !isWaitingForUser();

  Message? _lastAssistant(Conversation conversation, int priorCount) {
    final added = conversation.messages.skip(priorCount);
    for (final message in added.toList().reversed) {
      if (message.role == MessageRole.assistant &&
          !message.isStreaming &&
          message.error == null) {
        return message;
      }
    }
    return null;
  }

  bool _endsWithMarker(String content, String marker) =>
      ContentParser.stripModelHistoryArtifacts(
        content,
      ).trimRight().split('\n').last.trim() ==
      marker;

  Future<String?> _reviewPatch(Conversation conversation) async {
    final files =
        await readTaskPatch?.call(_taskPaths(conversation)) ??
        _taskFiles(conversation);
    if (files.isEmpty ||
        files.any(
          (file) =>
              file.isBinary ||
              file.isLargeFile ||
              file.isTruncated ||
              !file.hasRenderablePatch,
        )) {
      return null;
    }
    final patch = files.map((file) => file.unifiedPatch).join('\n');
    return patch.length <= 30000 ? patch : null;
  }
}

enum ProjectTaskReviewResult { committed, findingsRemain, stopped }
