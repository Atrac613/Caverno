import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/entities/turn_diff.dart';
import '../../chat/presentation/slash_commands/slash_command_prompt_template.dart';

/// Runs the user-started task through implementation and the dedicated review
/// route. Each stage must produce an explicit result before the next begins.
final class ProjectTaskReviewWorkflow {
  ProjectTaskReviewWorkflow({
    required this.conversationId,
    required this.readConversation,
    required this.isSelected,
    required this.isWaitingForUser,
    required this.send,
  });

  final String conversationId;
  final Conversation? Function() readConversation;
  final bool Function() isSelected;
  final bool Function() isWaitingForUser;
  final Future<bool> Function(String prompt, {required bool codeReview}) send;

  static const maxRepairRounds = 2;
  static const _ready = 'PROJECT_TASK_READY_FOR_REVIEW';
  static const _clean = 'PROJECT_TASK_REVIEW_CLEAN';
  static const _findings = 'PROJECT_TASK_REVIEW_FINDINGS';

  Future<ProjectTaskReviewResult> run() async {
    final task = readConversation();
    if (task == null || !isSelected() || task.messages.isNotEmpty) {
      return ProjectTaskReviewResult.stopped;
    }
    final objective = task.goal?.normalizedObjective;
    if (objective == null) return ProjectTaskReviewResult.stopped;

    var implementation =
        '''Implement this roadmap task in the current coding project:

$objective

Read the cited roadmap and relevant code, make the smallest complete change, and run relevant verification. Respect all approval and user-input gates. Do not commit, push, or publish. When implementation and verification are finished, end your final response with the exact line $_ready. If anything remains incomplete, explain it and omit that line.''';

    for (var repairRound = 0; repairRound <= maxRepairRounds; repairRound++) {
      final before = readConversation();
      if (!_canContinue(before)) return ProjectTaskReviewResult.stopped;
      final previousMessageCount = before!.messages.length;
      final previousDiffCount = before.turnDiffs.length;
      if (!await send(implementation, codeReview: false)) {
        return ProjectTaskReviewResult.stopped;
      }
      final after = readConversation();
      if (!_canContinue(after)) return ProjectTaskReviewResult.stopped;
      final response = _lastAssistant(after!, previousMessageCount);
      if (response == null || !_endsWithMarker(response.content, _ready)) {
        return ProjectTaskReviewResult.stopped;
      }
      if (after.turnDiffs.length <= previousDiffCount) {
        return ProjectTaskReviewResult.stopped;
      }

      final patch = _reviewPatch(after);
      if (patch == null) return ProjectTaskReviewResult.stopped;
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
        return ProjectTaskReviewResult.stopped;
      }
      final reviewed = readConversation();
      if (!_canContinue(reviewed)) return ProjectTaskReviewResult.stopped;
      final review = _lastAssistant(reviewed!, beforeReviewCount);
      if (review == null) return ProjectTaskReviewResult.stopped;
      if (_endsWithMarker(review.content, _clean)) {
        return ProjectTaskReviewResult.clean;
      }
      if (!_endsWithMarker(review.content, _findings)) {
        return ProjectTaskReviewResult.stopped;
      }
      if (repairRound == maxRepairRounds) {
        return ProjectTaskReviewResult.findingsRemain;
      }
      implementation =
          '''Fix the actionable findings from the dedicated code review below. Inspect the cited code, make only task-related repairs, and rerun relevant verification. Respect approval and user-input gates. Do not commit, push, or publish. End with the exact line $_ready only when the fixes and verification are complete; otherwise explain what remains and omit the line.

${review.content}''';
    }
    return ProjectTaskReviewResult.stopped;
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

enum ProjectTaskReviewResult { clean, findingsRemain, stopped }
