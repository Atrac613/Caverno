import 'package:flutter/material.dart';

/// Which pair of strings describes the plan's current execution state.
///
/// Keys rather than text: the caller translates, so this stays a choice about
/// which description applies rather than a place where copy lives.
class PlanExecutionOverview {
  const PlanExecutionOverview({
    required this.titleKey,
    required this.descriptionKey,
  });

  /// Which description the counts call for, in priority order.
  ///
  /// Blocked first because a blocker is the fact that stops everything else from
  /// mattering, then active, then ready. "Complete" requires every task to be
  /// complete, so a plan with nothing in it reads as empty rather than done.
  factory PlanExecutionOverview.forCounts({
    required int totalCount,
    required int completedCount,
    required int inProgressCount,
    required int blockedCount,
    required int pendingCount,
  }) {
    if (blockedCount > 0) {
      return const PlanExecutionOverview(
        titleKey: 'chat.plan_document_hydrated_state_blocked_title',
        descriptionKey: 'chat.plan_document_hydrated_state_blocked_description',
      );
    }
    if (inProgressCount > 0) {
      return const PlanExecutionOverview(
        titleKey: 'chat.plan_document_hydrated_state_active_title',
        descriptionKey: 'chat.plan_document_hydrated_state_active_description',
      );
    }
    if (pendingCount > 0) {
      return const PlanExecutionOverview(
        titleKey: 'chat.plan_document_hydrated_state_ready_title',
        descriptionKey: 'chat.plan_document_hydrated_state_ready_description',
      );
    }
    if (totalCount > 0 && completedCount == totalCount) {
      return const PlanExecutionOverview(
        titleKey: 'chat.plan_document_hydrated_state_complete_title',
        descriptionKey:
            'chat.plan_document_hydrated_state_complete_description',
      );
    }
    return const PlanExecutionOverview(
      titleKey: 'chat.plan_document_hydrated_state_empty_title',
      descriptionKey: 'chat.plan_document_hydrated_state_empty_description',
    );
  }

  final String titleKey;
  final String descriptionKey;
}

/// The plan's execution state at a glance: what it is doing, and how many tasks
/// sit in each state.
///
/// Left the chat_page library because nothing here needs the page: every input
/// is a string or a count, and the library was at its size ceiling with two
/// tracks queued behind it.
class PlanExecutionOverviewCard extends StatelessWidget {
  const PlanExecutionOverviewCard({
    super.key,
    required this.title,
    required this.description,
    required this.completedLabel,
    required this.pendingLabel,
    required this.pendingCount,
    required this.inProgressLabel,
    required this.inProgressCount,
    required this.blockedLabel,
    required this.blockedCount,
  });

  final String title;
  final String description;
  final String completedLabel;
  final String pendingLabel;
  final int pendingCount;
  final String inProgressLabel;
  final int inProgressCount;
  final String blockedLabel;
  final int blockedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            PlanExecutionCountChip(label: completedLabel),
            PlanExecutionCountChip(label: '$inProgressLabel: $inProgressCount'),
            PlanExecutionCountChip(label: '$blockedLabel: $blockedCount'),
            PlanExecutionCountChip(label: '$pendingLabel: $pendingCount'),
          ],
        ),
      ],
    );
  }
}

/// One count, styled as a quiet chip.
class PlanExecutionCountChip extends StatelessWidget {
  const PlanExecutionCountChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
