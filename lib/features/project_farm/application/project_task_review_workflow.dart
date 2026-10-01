import '../../../core/utils/logger.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/entities/turn_diff.dart';
import '../../chat/presentation/slash_commands/slash_command_prompt_template.dart';
import '../domain/entities/project_task_git_state.dart';

/// Runs the user-started task through implementation, the dedicated review
/// route, and a commit of the reviewed work. Each stage must produce an
/// explicit result before the next begins.
final class ProjectTaskReviewWorkflow {
  ProjectTaskReviewWorkflow({
    required this.conversationId,
    required this.readConversation,
    required this.isSelected,
    required this.isWaitingForUser,
    required this.send,
    required this.commit,
    required this.readGitState,
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

  static const maxRepairRounds = 2;
  static const maxMissingDiffRetries = 1;
  static const _ready = 'PROJECT_TASK_READY_FOR_REVIEW';
  static const _clean = 'PROJECT_TASK_REVIEW_CLEAN';
  static const _findings = 'PROJECT_TASK_REVIEW_FINDINGS';

  Future<ProjectTaskReviewResult> run() async {
    stopReason = null;
    final task = readConversation();
    if (task == null || !isSelected() || task.messages.isNotEmpty) {
      return _stop('the task thread is not a new, selected thread');
    }
    final objective = task.goal?.normalizedObjective;
    if (objective == null) return _stop('the task has no goal objective');

    var implementation =
        '''Implement this roadmap task in the current coding project:

$objective

Read the cited roadmap and relevant code, make the smallest complete change, and run relevant verification. Respect all approval and user-input gates. Do not commit, push, or publish, and leave the roadmap item's status unchanged: both happen in a separate step after review. When implementation and verification are finished, end your final response with the exact line $_ready. If anything remains incomplete, explain it and omit that line.''';

    for (var repairRound = 0; repairRound <= maxRepairRounds; repairRound++) {
      Conversation? after;
      for (var retry = 0; retry <= maxMissingDiffRetries; retry++) {
        final before = readConversation();
        if (!_canContinue(before)) return _stop(_notContinuable);
        final previousMessageCount = before!.messages.length;
        final previousDiffCount = before.turnDiffs.length;
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
        if (after.turnDiffs.length > previousDiffCount) {
          if (!_endsWithMarker(response.content, _ready)) {
            return _stop(
              'the implementation response does not end with $_ready '
              '(last line: "${_lastLine(response.content)}")',
            );
          }
          break;
        }
        if (retry == maxMissingDiffRetries) {
          return _stop('the implementation captured no reviewable file change');
        }
        implementation =
            '''The previous implementation turn captured no reviewable file change. Any claimed edits or test results without tool evidence are unverified. Inspect the current files, then perform the remaining implementation with file tools and run relevant verification. Do not repeat the same whole-file reads. Respect approval and user-input gates. If the task is blocked or already complete, explain the evidence and omit $_ready. End with exactly $_ready only after the work and verification are actually complete.''';
      }

      final patch = _reviewPatch(after!);
      if (patch == null) {
        return _stop(
          'the captured patch is empty, binary, truncated, or too large',
        );
      }
      final template = builtInSlashCommandPromptTemplates.firstWhere(
        (candidate) => candidate.id == 'review',
      );
      final reviewPrompt =
          '''${template.expand(args: 'Only the task changes in the patch below', commandName: 'review')}

The patch below is the captured output of this task's file tools. Review these changes and relevant surrounding code. Do not review unrelated pre-existing changes in the working tree. If the patch cannot be reconciled with the working tree, explain the limit and do not report a clean review.

```diff
$patch
```

After your findings and verification limits, end with exactly one of these lines:
$_clean — only when there are no actionable findings and the patch was reviewable
$_findings — when there are actionable findings
If review is incomplete, omit both markers.''';
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
        return ProjectTaskReviewResult.findingsRemain;
      }
      implementation =
          '''Fix the actionable findings from the dedicated code review below. Inspect the cited code, make only task-related repairs, and rerun relevant verification. Respect approval and user-input gates. Do not commit, push, or publish. End with the exact line $_ready only when the fixes and verification are complete; otherwise explain what remains and omit the line.

${review.content}''';
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
3. Commit with a message that follows this repository's commit conventions. Do not push, publish, amend, or rewrite history.

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
    return ProjectTaskReviewResult.committed;
  }

  List<String> _taskPaths(Conversation conversation) => {
    for (final diff in conversation.turnDiffs)
      if (diff.source == TurnDiffSource.tool)
        for (final file in diff.files) file.filePath,
  }.toList();

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
    appLog(
      '[ProjectTaskReview] stopped: $reason; conversation=$conversationId',
    );
    return ProjectTaskReviewResult.stopped;
  }

  String _lastLine(String content) {
    final line = content.trimRight().split('\n').last.trim();
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
      content.trimRight().split('\n').last.trim() == marker;

  String? _reviewPatch(Conversation conversation) {
    final files = conversation.turnDiffs
        .where((diff) => diff.source == TurnDiffSource.tool)
        .expand((diff) => diff.files)
        .toList();
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
