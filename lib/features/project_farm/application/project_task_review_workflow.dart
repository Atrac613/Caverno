import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../core/utils/logger.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/domain/entities/conversation_workflow.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/entities/turn_diff.dart';
import '../../chat/domain/services/project_task_implementation_instructions.dart';
import '../../chat/domain/services/project_task_review_verdict.dart';
import '../../chat/domain/services/project_task_terminal_status.dart';
import '../../chat/presentation/slash_commands/slash_command_prompt_template.dart';
import '../domain/entities/project_task_commit_scope.dart';
import '../domain/entities/project_task_git_state.dart';
import '../domain/project_task_progress.dart';
import 'project_task_commit_sequence.dart';
import 'project_task_commit_turn_evidence.dart';

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
    this.prepareCommit,
    this.readCommitSnapshot,
    this.readCommitTurnEvidence,
    this.projectRoot,
    required this.readGitState,
    this.decompose,
    this.sendStep,
    this.readSubtaskStatus,
    this.readReviewVerdict,
    this.readVerificationContext,
    this.markSubtaskDone,
    this.onProgress,
    this.onDecision,
    this.inheritedFiles = const [],
    this.recordPriorChanges,
    this.readTaskPatch,
  });

  final void Function(Map<String, Object?> decision)? onDecision;
  final String conversationId;
  final Conversation? Function() readConversation;
  final bool Function() isSelected;
  final bool Function() isWaitingForUser;
  final Future<bool> Function(String prompt, {required bool codeReview}) send;

  /// Sends the commit turn. The commit itself is a model tool call, so it
  /// passes through the same approval gate as any other git write.
  final Future<bool> Function(String prompt, ProjectTaskCommitScope scope)
  commit;
  final Future<bool> Function(String prompt, ProjectTaskCommitScope scope)?
  prepareCommit;
  final Future<ProjectTaskCommitSnapshot?> Function(
    ProjectTaskCommitScope scope,
  )?
  readCommitSnapshot;
  final String? projectRoot;
  final ProjectTaskCommitTurnEvidence? Function()? readCommitTurnEvidence;

  /// Reads HEAD and the status of [paths]; null when git cannot be read.
  final Future<ProjectTaskGitState?> Function(List<String> paths) readGitState;

  /// Splits the objective into ordered subtasks and saves them as the
  /// thread's execution tasks. An empty result runs the task as one step.
  final Future<List<ConversationWorkflowTask>> Function(String objective)?
  decompose;

  /// Sends a subtask turn before the last one. These turns are judged by
  /// their marker, not by goal completion, which only the last turn records.
  final Future<bool> Function(String prompt)? sendStep;
  final ProjectTaskTerminalStatus? Function()? readSubtaskStatus;
  final ProjectTaskReviewVerdict? Function()? readReviewVerdict;
  final String Function()? readVerificationContext;

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

  /// A patch longer than this is listed rather than inlined, and the
  /// reviewer reads each file's diff itself. Stopping instead discarded a
  /// finished five-subtask implementation over a 46 KB patch (d8ffeb92).
  /// A file whose captured patch was cut short (the 400-line/12,000-char
  /// display cap) or omitted as too large is listed the same way (48328742).
  static const maxInlinePatchChars = 30000;
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
        return _stop('the task patch is empty or contains a binary file');
      }
      final inlinePatch = patch.inline;
      if (inlinePatch == null) {
        onDecision?.call({
          'phase': 'review',
          'decision': 'patch_listed',
          'patchChars': patch.chars,
          'fileCount': patch.files.length,
        });
      }
      final patchSection = inlinePatch != null
          ? '```diff\n$inlinePatch\n```'
          : '''The patch is too large to include in full here (${patch.chars} characters captured). Its changed files are:
${_listedFiles(patch.files).join('\n')}
Inspect each listed file's change with git_execute_command `diff HEAD -- <path>`, one file per call, in addition to reading the files. Do not report a clean review unless every listed file's change was inspected.''';
      final template = builtInSlashCommandPromptTemplates.firstWhere(
        (candidate) => candidate.id == 'review',
      );
      final reviewPrompt =
          '''${template.expand(args: 'Only the task changes in the patch below', commandName: 'review')}

The patch below is this task's change to the files its file tools edited${inheritedFiles.isEmpty ? '' : ', including changes an earlier run of this task left uncommitted'}. Review these changes and relevant surrounding code. Begin this review turn by calling read_file on the relevant changed files; wait for successful results and reconcile the patch with their current contents before giving findings or reporting a clean review. Do not answer directly from the supplied patch or conversation history. Reads from earlier implementation or repair turns are historical evidence, not current review inspections. Do not review unrelated pre-existing changes in the working tree. If the patch cannot be reconciled with the working tree, explain the limit and do not report a clean review.

$patchSection

${ProjectTaskReviewVerdict.instructions}

${readVerificationContext?.call() ?? ''}

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
      final verdict = readReviewVerdict?.call();
      if (readReviewVerdict != null) {
        onDecision?.call({
          'phase': 'review',
          'decision': verdict?.disposition.name ?? 'missing',
          'nativeVerdictAvailable': verdict != null,
        });
      }
      if (readReviewVerdict != null &&
          (verdict == null || !verdict.isComplete)) {
        return _stop(
          'the dedicated review has no complete native verdict',
          gapCodes: const ['review_incomplete'],
        );
      }
      final reviewReport = verdict?.response ?? review.content;
      if (_endsWithMarker(reviewReport, _clean)) {
        return _commit(reviewed, objective);
      }
      if (!_endsWithMarker(reviewReport, _findings)) {
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

${ContentParser.stripModelHistoryArtifacts(reviewReport)}''';
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
    final root = projectRoot;
    final scope = root == null
        ? null
        : ProjectTaskCommitScope.fromObjective(
            conversationId: conversationId,
            projectRoot: root,
            objective: objective,
            reviewedPaths: paths,
          );
    final prepare = prepareCommit;
    final inspect = readCommitSnapshot;
    if (scope == null || prepare == null || inspect == null) {
      return _stop(
        'native commit preparation is unavailable or the roadmap source is invalid',
      );
    }
    final baseline = await inspect(scope);
    if (baseline == null || baseline.head != before.head) {
      return _stop('git state could not be captured for commit preparation');
    }
    if (baseline.stagedPaths.difference(scope.paths).isNotEmpty) {
      return _stop(
        'the index includes unrelated staged files before preparation',
      );
    }
    if (!_canContinue(readConversation())) return _stop(_notContinuable);
    final problem = await ProjectTaskCommitSequence(
      onDecision: onDecision,
      prepare: prepare,
      commit: commit,
      inspect: inspect,
      readEvidence: readCommitTurnEvidence ?? () => null,
      canContinue: () => _canContinue(readConversation()),
      canRecover: () {
        final goal = readConversation()?.goal;
        return _canContinue(readConversation()) &&
            goal != null &&
            goal.enabled &&
            goal.status == ConversationGoalStatus.completed &&
            !goal.budgetExceeded;
      },
    ).run(objective, scope, baseline);
    if (problem != null) return _stop(problem);
    if (!_canContinue(readConversation())) return _stop(_notContinuable);
    final committedPaths = {
      ...paths,
      ..._taskPaths(readConversation()!),
    }.toList();
    final after = await readGitState(committedPaths);
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
    final status = readSubtaskStatus?.call();
    if (readSubtaskStatus != null &&
        (status?.isSubtask != true ||
            status?.subtaskId != subtasks[index].id)) {
      return _stop(
        'subtask $number has no matching harness verdict',
        gapCodes: const ['missing_subtask_status'],
      );
    }
    if (status?.isSubtask == true && !status!.completionAccepted) {
      return _stop(
        'subtask $number was rejected by the harness: ${status.gaps.join('; ')}',
        gateReason: 'subtask $number was rejected by the harness',
        gapCodes: status.gapCodes,
      );
    }
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
    onDecision?.call({
      'phase': progress.phase.name,
      'decision': 'progress',
      'outcome': progress.outcome.name,
    });
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

  ProjectTaskReviewResult _stop(
    String reason, {
    String? gateReason,
    List<String> gapCodes = const [],
  }) {
    stopReason = reason;
    onDecision?.call({
      'phase': 'workflow',
      'decision': 'stopped',
      if (gapCodes.isNotEmpty) 'gapCodes': gapCodes,
      'reason':
          gateReason ??
          reason
              .split('(last line:')
              .first
              .split('failed verification:')
              .first
              .trim(),
    });
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

  /// One line per path. Captured per-turn patches can repeat a file, so the
  /// counts are summed; the reviewer reads the net change from git anyway.
  static Iterable<String> _listedFiles(List<TurnDiffFile> files) {
    final counts = <String, (int, int)>{};
    for (final file in files) {
      final (added, removed) = counts[file.filePath] ?? (0, 0);
      counts[file.filePath] = (
        added + file.linesAdded,
        removed + file.linesRemoved,
      );
    }
    return counts.entries.map(
      (entry) => '- ${entry.key} (+${entry.value.$1} -${entry.value.$2})',
    );
  }

  Future<({String? inline, int chars, List<TurnDiffFile> files})?> _reviewPatch(
    Conversation conversation,
  ) async {
    final files =
        await readTaskPatch?.call(_taskPaths(conversation)) ??
        _taskFiles(conversation);
    if (!files.any((file) => file.hasChanges) ||
        files.any((file) => file.isBinary)) {
      return null;
    }
    // A cut-short or omitted file patch is not the change; list the files so
    // the reviewer reads the full diff from git.
    final complete = files.every(
      (file) =>
          !file.isTruncated && !file.isLargeFile && file.hasRenderablePatch,
    );
    final patch = files.map((file) => file.unifiedPatch).join('\n');
    return (
      inline: complete && patch.length <= maxInlinePatchChars ? patch : null,
      chars: patch.length,
      files: files,
    );
  }
}

enum ProjectTaskReviewResult { committed, findingsRemain, stopped }
