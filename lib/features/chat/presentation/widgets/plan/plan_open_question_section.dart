import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/conversation_workflow.dart';

/// What is waiting on the user, in the panel that is always on screen.
///
/// **§15's third question was the only one with no persistent surface.** Open
/// questions live in the plan review sheet and a material assumption arrives as
/// an interrupt, so a user who dismissed one had nothing that remembered --
/// which is the half that makes the workspace somewhere to intervene rather
/// than only to observe.
///
/// Deliberately a summary with one way in, not a second answering surface. The
/// sheet already owns answering, with a status menu and a note editor per
/// question; duplicating that here would give the same decision two places to
/// be made and two places to drift.
///
/// It counts through [Conversation.unresolvedOpenQuestions], so an untriaged
/// question counts -- the count that walked progress rows reported zero until a
/// human opened the sheet, which is exactly the user this section is for.
class AwaitingYouPanelSection extends StatelessWidget {
  const AwaitingYouPanelSection({
    super.key,
    required this.currentConversation,
    required this.onOpen,
  });

  final Conversation currentConversation;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final questions = currentConversation.unresolvedOpenQuestions;
    if (questions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final visible = questions.take(3).toList(growable: false);
    final remaining = questions.length - visible.length;

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
                          namedArgs: {'count': '${questions.length}'},
                        ),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final question in visible) ...[
                  Text(
                    question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (question != visible.last) const SizedBox(height: 6),
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
