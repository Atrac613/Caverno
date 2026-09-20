import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/conversation_workflow.dart';
import 'blocking_assumption_items.dart';

/// What is waiting on the user, in the panel that is always on screen.
///
/// **§15's third question was the only one with no persistent surface.** Open
/// questions live in the plan review sheet and a material assumption arrives as
/// an interrupt, so a user who dismissed one had nothing that remembered --
/// which is the half that makes the workspace somewhere to intervene rather
/// than only to observe.
///
/// Deliberately a summary with one way in, not a second answering surface.
/// `AwaitingYouSheet` owns answering, with a status menu and a note editor per
/// question and a confirmation per assumption; duplicating that here would give
/// the same decision two places to be made and two places to drift.
///
/// **The `onOpen` this comment described did not exist until 2026-09-20.** It
/// went to `PlanReviewSheet`, which renders a markdown preview and three
/// buttons, because the surfaces that do own answering hung off
/// `_buildWorkflowPanel` -- unmounted since 2026-04-18 behind an
/// `// ignore: unused_element`. Both kinds now reach `AwaitingYouSheet`.
///
/// It counts the union of two kinds. [Conversation.unresolvedOpenQuestions], so
/// an untriaged question counts -- the count that walked progress rows reported
/// zero until a human opened the sheet, which is exactly the user this section
/// is for -- and the blocking material assumptions, which stop work outright
/// and, before this, could only be answered by the interrupt raised mid-turn.
class AwaitingYouPanelSection extends StatelessWidget {
  const AwaitingYouPanelSection({
    super.key,
    required this.currentConversation,
    required this.onOpen,
  });

  final Conversation currentConversation;
  final VoidCallback onOpen;

  /// Everything waiting on the user, questions first.
  ///
  /// Questions lead because they are the cheaper answer; an assumption stops
  /// work and is worth seeing even at the bottom of a truncated preview, which
  /// is what the trailing count is for.
  static List<({String text, bool blocks})> waitingItems(
    Conversation conversation,
  ) {
    final spec = conversation.effectiveWorkflowSpec;
    return [
      for (final question in conversation.unresolvedOpenQuestions)
        (text: question, blocks: false),
      for (final item in blockingAssumptionItems(
        spec: spec,
        kind: ConversationContractItemKind.constraint,
        items: spec.constraints,
      ))
        (text: item, blocks: true),
      for (final item in blockingAssumptionItems(
        spec: spec,
        kind: ConversationContractItemKind.acceptanceCriterion,
        items: spec.acceptanceCriteria,
      ))
        (text: item, blocks: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = waitingItems(currentConversation);
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final visible = items.take(3).toList(growable: false);
    final remaining = items.length - visible.length;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.help_outline,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'chat.companion_awaiting_you'.tr(
                          namedArgs: {'count': '${items.length}'},
                        ),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final item in visible) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // A blocking assumption reads like a statement, not a
                      // question, so without the mark the two kinds are
                      // indistinguishable in one list.
                      if (item.blocks) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.pause_circle_outline,
                            size: 13,
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          item.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (item != visible.last) const SizedBox(height: 6),
                ],
                if (remaining > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'chat.companion_more_items'.tr(
                      namedArgs: {'count': '$remaining'},
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlanOpenQuestionSection extends StatelessWidget {
  const PlanOpenQuestionSection({
    super.key,
    required this.currentConversation,
    required this.onStatusSelected,
    required this.onAnswerPressed,
  });

  final Conversation currentConversation;
  final void Function(String question, ConversationOpenQuestionStatus status)
  onStatusSelected;
  final void Function(String question, String? existingNote) onAnswerPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openQuestions = currentConversation
        .effectiveWorkflowSpec
        .openQuestions
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.plan_document_open_questions_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'chat.plan_document_open_questions_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final question in openQuestions) ...[
            _PlanOpenQuestionRow(
              question: question,
              progress: currentConversation.openQuestionProgressForQuestion(
                question,
              ),
              onStatusSelected: onStatusSelected,
              onAnswerPressed: onAnswerPressed,
            ),
            if (question != openQuestions.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PlanOpenQuestionRow extends StatelessWidget {
  const _PlanOpenQuestionRow({
    required this.question,
    required this.progress,
    required this.onStatusSelected,
    required this.onAnswerPressed,
  });

  final String question;
  final ConversationOpenQuestionProgress? progress;
  final void Function(String question, ConversationOpenQuestionStatus status)
  onStatusSelected;
  final void Function(String question, String? existingNote) onAnswerPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status =
        progress?.status ?? ConversationOpenQuestionStatus.unresolved;
    final note = progress?.normalizedNote;
    final needsAnswerFlow =
        status == ConversationOpenQuestionStatus.unresolved ||
        status == ConversationOpenQuestionStatus.needsUserInput;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  question.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(_openQuestionStatusLabel(status).tr()),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
                backgroundColor: _openQuestionStatusColor(
                  context,
                  status,
                ).withValues(alpha: 0.16),
                labelStyle: theme.textTheme.labelSmall?.copyWith(
                  color: _openQuestionStatusColor(context, status),
                  fontWeight: FontWeight.w700,
                ),
              ),
              PopupMenuButton<ConversationOpenQuestionStatus>(
                onSelected: (nextStatus) =>
                    onStatusSelected(question, nextStatus),
                itemBuilder: (popupContext) => ConversationOpenQuestionStatus
                    .values
                    .map(
                      (candidate) => PopupMenuItem(
                        value: candidate,
                        child: Text(
                          _openQuestionStatusMenuLabel(candidate).tr(),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => onAnswerPressed(question, note),
                icon: Icon(
                  needsAnswerFlow
                      ? Icons.question_answer_outlined
                      : Icons.edit_note_outlined,
                  size: 18,
                ),
                label: Text(
                  needsAnswerFlow
                      ? 'chat.open_question_answer'.tr()
                      : 'chat.open_question_edit_answer'.tr(),
                ),
              ),
              if (status != ConversationOpenQuestionStatus.needsUserInput)
                OutlinedButton.icon(
                  onPressed: () => onStatusSelected(
                    question,
                    ConversationOpenQuestionStatus.needsUserInput,
                  ),
                  icon: const Icon(Icons.contact_support_outlined, size: 18),
                  label: Text('chat.open_question_mark_needs_user_input'.tr()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _openQuestionStatusLabel(ConversationOpenQuestionStatus status) {
    return switch (status) {
      ConversationOpenQuestionStatus.unresolved =>
        'chat.open_question_status_unresolved',
      ConversationOpenQuestionStatus.needsUserInput =>
        'chat.open_question_status_needs_user_input',
      ConversationOpenQuestionStatus.resolved =>
        'chat.open_question_status_resolved',
      ConversationOpenQuestionStatus.deferred =>
        'chat.open_question_status_deferred',
    };
  }

  String _openQuestionStatusMenuLabel(ConversationOpenQuestionStatus status) {
    return switch (status) {
      ConversationOpenQuestionStatus.unresolved =>
        'chat.open_question_menu_mark_unresolved',
      ConversationOpenQuestionStatus.needsUserInput =>
        'chat.open_question_menu_mark_needs_user_input',
      ConversationOpenQuestionStatus.resolved =>
        'chat.open_question_menu_mark_resolved',
      ConversationOpenQuestionStatus.deferred =>
        'chat.open_question_menu_mark_deferred',
    };
  }

  Color _openQuestionStatusColor(
    BuildContext context,
    ConversationOpenQuestionStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      ConversationOpenQuestionStatus.unresolved => scheme.secondary,
      ConversationOpenQuestionStatus.needsUserInput => scheme.tertiary,
      ConversationOpenQuestionStatus.resolved => Colors.green.shade700,
      ConversationOpenQuestionStatus.deferred => scheme.onSurfaceVariant,
    };
  }
}
