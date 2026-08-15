import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/flutter_run_issue.dart';
import '../providers/flutter_run_provider.dart';

/// Issues found in the run output.
///
/// Each row is one problem, however many times it occurred. The evidence is
/// one tap away because the analysis above it can be wrong, and the block is
/// what settles it.
class FlutterRunIssueList extends ConsumerWidget {
  const FlutterRunIssueList({
    super.key,
    required this.projectRoot,
    required this.onSendToChat,
  });

  final String projectRoot;

  /// Hands the issue to the conversation as a prefilled prompt.
  final void Function(FlutterRunIssue issue) onSendToChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final collector = ref.watch(flutterRunIssueCollectorProvider(projectRoot));
    final issues =
        ref.watch(flutterRunIssuesProvider(projectRoot)).value ??
        collector.issues;

    if (issues.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'chat.flutter_run_no_issues'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: issues.length + (collector.budgetExhausted ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        if (index == issues.length) {
          return _BudgetNotice(onResume: () => collector.analyseNow());
        }
        return _IssueRow(
          issue: issues[index],
          onSendToChat: () => onSendToChat(issues[index]),
        );
      },
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.onSendToChat});

  final FlutterRunIssue issue;
  final VoidCallback onSendToChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (issue.severity) {
      FlutterRunIssueSeverity.error => theme.colorScheme.error,
      FlutterRunIssueSeverity.warning => theme.colorScheme.tertiary,
      FlutterRunIssueSeverity.info => theme.colorScheme.onSurfaceVariant,
    };

    return Card(
      key: ValueKey('flutter-run-issue-${issue.signature}'),
      child: ExpansionTile(
        dense: true,
        leading: Icon(Icons.error_outline, size: 20, color: color),
        title: Text(
          issue.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            ?issue.location,
            if (issue.occurrences > 1)
              'chat.flutter_run_issue_occurrences'.tr(
                args: ['${issue.occurrences}'],
              ),
            // Says so rather than presenting the segmenter's own headline as
            // a verdict the model reached.
            if (!issue.analysed) 'chat.flutter_run_issue_unanalysed'.tr(),
          ].join(' • '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (issue.cause.isNotEmpty) ...[
            Text(issue.cause, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              issue.evidence,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: ValueKey('flutter-run-issue-ask-${issue.signature}'),
              onPressed: onSendToChat,
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: Text('chat.flutter_run_issue_ask'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetNotice extends StatelessWidget {
  const _BudgetNotice({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'chat.flutter_run_analysis_paused'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          key: const ValueKey('flutter-run-analysis-resume'),
          onPressed: onResume,
          child: Text('chat.flutter_run_analysis_resume'.tr()),
        ),
      ],
    );
  }
}

/// The prompt an issue becomes when it is handed to the conversation.
///
/// Carries the block verbatim: the model in the chat should read what the
/// toolchain printed, not a summary of a summary.
String flutterRunIssuePrompt(FlutterRunIssue issue) {
  return [
    'This came out of running the app:',
    '',
    issue.title,
    if (issue.location case final location?) 'Reported at: $location',
    if (issue.cause.isNotEmpty) issue.cause,
    '',
    '```',
    issue.evidence,
    '```',
    '',
    'Find the cause and propose a fix.',
  ].join('\n');
}
