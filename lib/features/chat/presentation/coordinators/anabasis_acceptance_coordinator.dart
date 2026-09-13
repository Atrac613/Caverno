// Reaches ChatNotifier.ref the way the other coordinators in this directory do;
// see workflow_task_run_coordinator.dart for the rationale.
// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/worktree_agent_task.dart';
import '../../domain/services/anabasis_acceptance_elicitation.dart';
import '../../domain/services/anabasis_turn_roles.dart';
import '../providers/chat_notifier.dart';
import '../providers/conversations_notifier.dart';
import '../providers/hidden_prompt_launch_options.dart';
import '../providers/subagent_task_notifier.dart';
import '../providers/worktree_agent_task_registry_notifier.dart';

/// Runs the acceptance elicitation at a settled parent turn.
///
/// **Outside the notifier library on purpose.** `chat_notifier.dart` and its
/// parts sit at their aggregate ratchet, and this is a turn-boundary policy with
/// two collaborators and no notifier state of its own — which is what the
/// ratchet's "extract an independent service" is asking for.
///
/// It also owns the two pieces of memory the elicitation needs and nothing else
/// does: which generations were the parent's after their turn has been torn
/// down, and which results have already been put to the parent.
final class AnabasisAcceptanceCoordinator {
  AnabasisAcceptanceCoordinator({
    required ChatNotifier chatNotifier,
    required Ref ref,
    required AnabasisTurnRoles roles,
  }) : _chatNotifier = chatNotifier,
       _ref = ref,
       _roles = roles;

  final ChatNotifier _chatNotifier;
  final Ref _ref;
  final AnabasisTurnRoles _roles;
  final _ledger = AnabasisAcceptanceElicitationLedger();

  /// The parent generations whose turns have already been released.
  ///
  /// A turn's teardown runs before anything gets to ask what kind of turn it
  /// was: `_completeRuntimeTurn` releases the role, and the elicitation is
  /// decided after it. Without this every settled parent turn would read as an
  /// ordinary one. Bounded because nothing ever asks about a generation more
  /// than one turn old.
  final List<int> _settledParentGenerations = <int>[];
  static const _settledMemory = 8;

  /// Records whether the turn at [generation] was addressed to the parent.
  ///
  /// The single entry point for both send paths. Hidden turns used to skip the
  /// marking entirely — `markAddressed` was only ever called on the visible
  /// path — so a harness-written turn could never be the parent's, and
  /// `accept_task` refuses every turn that is not. A harness-written
  /// `@anabasis` is an address like any other: the handle names who is being
  /// spoken to.
  void markAddressed(int generation, String content) {
    _roles.markAddressed(generation: generation, content: content);
    if (!_roles.isParentTurn(generation)) return;
    _settledParentGenerations.add(generation);
    while (_settledParentGenerations.length > _settledMemory) {
      _settledParentGenerations.removeAt(0);
    }
  }

  /// The worktree registry, or nothing if it cannot be read.
  ///
  /// Defensive because of where this is called from: a throw inside a tool
  /// handler leaves the call unexecuted and ends the turn, and that one runs at
  /// the end of work expensive enough that losing it is the worse outcome.
  /// Without a readable registry the audit falls back to subagent children,
  /// which is exactly the behaviour that preceded worktree delegation.
  List<WorktreeAgentTask> worktreeChildrenOrNone() {
    try {
      return _ref.read(worktreeAgentTaskRegistryNotifierProvider).tasks;
    } catch (error) {
      appLog('[Anabasis] Worktree registry unavailable for acceptance: $error');
      return const <WorktreeAgentTask>[];
    }
  }

  /// Spends one hidden turn asking the parent to settle a result it has already
  /// verified, and reports whether it did.
  ///
  /// Restricted to `accept_task` so the turn cannot start new work, and
  /// addressed to the parent because the tool refuses any other turn. A `true`
  /// return tells the caller to leave goal auto-continue to the next boundary
  /// rather than dispatching over this turn.
  Future<bool> maybeElicit(ChatTurnOwner owner, String languageCode) async {
    final conversation = _conversationForId(owner.conversationId);
    if (conversation == null) return false;
    final plan = const AnabasisAcceptanceElicitation().decide(
      isParentTurn: _settledParentGenerations.contains(
        owner.interactionGeneration,
      ),
      worktreeChildren: worktreeChildrenOrNone(),
      children: _ref
          .read(subagentTaskNotifierProvider)
          .tasksForConversation(owner.conversationId),
      acceptedTaskIds: conversation.taskAcceptances
          .map((acceptance) => acceptance.taskId)
          .toSet(),
      alreadyElicitedTaskIds: _ledger.elicitedFor(owner.conversationId),
    );
    if (plan.eligibility != AcceptanceElicitationEligibility.eligible) {
      return false;
    }
    // Recorded before the dispatch, not after: the turn it starts ends in this
    // same funnel, and a ledger written afterwards would still be empty when
    // eligibility is decided again.
    _ledger.recordElicited(
      conversationId: owner.conversationId,
      workflowTaskIds: plan.candidates.map(
        (candidate) => candidate.workflowTaskId,
      ),
    );
    appLog(
      '[Anabasis] eliciting a judgement for '
      '${plan.candidates.length} delegated result(s)',
    );
    try {
      await _chatNotifier.sendHiddenPrompt(
        AnabasisAcceptanceElicitationPrompt.build(
          languageCode: languageCode,
          candidates: plan.candidates,
        ),
        options: HiddenPromptLaunchOptions(
          targetConversationId: owner.conversationId,
        ),
        languageCode: languageCode,
        persistAssistantResponse: true,
        allowedToolNames: const <String>{'accept_task'},
      );
    } on Object catch (error) {
      appLog('[Anabasis] acceptance elicitation failed: $error');
    }
    return true;
  }

  Conversation? _conversationForId(String conversationId) => _ref
      .read(conversationsNotifierProvider)
      .conversations
      .where((conversation) => conversation.id == conversationId)
      .firstOrNull;
}
