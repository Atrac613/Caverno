import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/conversation_workflow.dart';
import 'blocking_assumption_items.dart';
import 'contract_item_list_section.dart';
import 'plan_open_question_section.dart';

/// The two things that wait on a user, on a surface that is actually mounted.
///
/// **Both answering surfaces existed and neither rendered.** Measured
/// 2026-09-20: `_buildWorkflowPanel` had one reference in the repository, its
/// own declaration — the call site was deleted on 2026-04-18 and the part-file
/// split silenced the analyzer with an `// ignore: unused_element` a month
/// later. Everything below it is called exactly once, from inside it, so
/// [PlanOpenQuestionSection] and the confirmation route added to
/// [ContractItemListSection] were both unreachable, and `AwaitingYouPanelSection`
/// pointed at `PlanReviewSheet`, which renders a markdown preview and three
/// buttons and no questions at all.
///
/// This sheet is the destination that section always described. It is a new
/// mount rather than a re-mount of the panel: the panel also carried proposal
/// cards, a tasks section and a compact summary that the companion pane has
/// since grown its own versions of, so reviving it would restore duplicates
/// alongside the two surfaces actually wanted.
///
/// Deliberately *only* the waiting items. The plan document, the task list and
/// the run controls each already have a live surface, and this one answers one
/// question: what is stopping work that only the user can clear.
class AwaitingYouSheet extends StatelessWidget {
  const AwaitingYouSheet({
    super.key,
    required this.currentConversation,
    required this.onStatusSelected,
    required this.onAnswerPressed,
    required this.onConfirmAssumption,
  });

  final Conversation currentConversation;
  final void Function(String question, ConversationOpenQuestionStatus status)
  onStatusSelected;
  final void Function(String question, String? existingNote) onAnswerPressed;
  final void Function(ConversationWorkflowSpec confirmedSpec)
  onConfirmAssumption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = currentConversation.effectiveWorkflowSpec;
    final questions = spec.openQuestions
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    final blockingConstraints = blockingAssumptionItems(
      spec: spec,
      kind: ConversationContractItemKind.constraint,
      items: spec.constraints,
    );
    final blockingAcceptance = blockingAssumptionItems(
      spec: spec,
      kind: ConversationContractItemKind.acceptanceCriterion,
      items: spec.acceptanceCriteria,
    );
    final hasAssumptions =
        blockingConstraints.isNotEmpty || blockingAcceptance.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 20,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'chat.awaiting_you_title'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'chat.awaiting_you_subtitle'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (questions.isNotEmpty)
                      PlanOpenQuestionSection(
                        currentConversation: currentConversation,
                        onStatusSelected: onStatusSelected,
                        onAnswerPressed: onAnswerPressed,
                      ),
                    if (hasAssumptions) ...[
                      const SizedBox(height: 16),
                      Text(
                        'chat.awaiting_you_assumptions_title'.tr(),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // Only the blocking items, so the sheet stays an answer
                      // to "what is stopping work" rather than a second copy
                      // of the contract.
                      ContractItemListSection(
                        label: 'chat.workflow_constraints'.tr(),
                        items: blockingConstraints,
                        spec: spec,
                        kind: ConversationContractItemKind.constraint,
                        onConfirmAssumption: onConfirmAssumption,
                      ),
                      ContractItemListSection(
                        label: 'chat.workflow_acceptance'.tr(),
                        items: blockingAcceptance,
                        spec: spec,
                        kind: ConversationContractItemKind.acceptanceCriterion,
                        onConfirmAssumption: onConfirmAssumption,
                      ),
                    ],
                    if (questions.isEmpty && !hasAssumptions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'chat.awaiting_you_empty'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presents [AwaitingYouSheet] over the current conversation.
///
/// Lives beside the sheet rather than on the page for the reason
/// `CompanionTaskRow` did: the page owns the three actions and nothing else
/// here, and the chat_page library had no room for the presentation.
///
/// Watches the conversation instead of closing over the one passed in, so
/// answering a question or confirming an assumption updates the list under the
/// user rather than leaving a stale row to be tapped twice.
Future<void> showAwaitingYouSheet(
  BuildContext context, {
  required Conversation currentConversation,
  required void Function(String question, ConversationOpenQuestionStatus status)
  onStatusSelected,
  required void Function(String question, String? existingNote) onAnswerPressed,
  required void Function(
    Conversation conversation,
    ConversationWorkflowSpec confirmedSpec,
  )
  onConfirmAssumption,
  required Conversation? Function(WidgetRef ref) watchConversation,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => Consumer(
    builder: (consumerContext, ref, _) {
      final latest = watchConversation(ref) ?? currentConversation;
      return AwaitingYouSheet(
        currentConversation: latest,
        onStatusSelected: onStatusSelected,
        onAnswerPressed: onAnswerPressed,
        onConfirmAssumption: (confirmedSpec) =>
            onConfirmAssumption(latest, confirmedSpec),
      );
    },
  ),
);
