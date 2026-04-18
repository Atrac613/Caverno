import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/conversation_workflow.dart';

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
    final openQuestions = currentConversation.effectiveWorkflowSpec.openQuestions
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
                onSelected: (nextStatus) => onStatusSelected(question, nextStatus),
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
                  label: Text(
                    'chat.open_question_mark_needs_user_input'.tr(),
                  ),
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
