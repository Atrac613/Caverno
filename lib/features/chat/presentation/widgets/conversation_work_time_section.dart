import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/background_process_tools.dart';
import '../../domain/entities/conversation_work_time.dart';
import '../providers/conversation_work_time_providers.dart';
import '../providers/mcp_tool_provider.dart';

/// Formats a work-time total: `850ms`, `45s`, `2m 21s`, `1h 03m`.
String formatWorkDuration(int ms) {
  if (ms <= 0) return '0s';
  if (ms < 1000) return '${ms}ms';
  final seconds = ms ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// Companion-sidebar breakdown of where a conversation's time went: model
/// inference, tool calls and background jobs on this machine, and approvals.
class ConversationWorkTimeSection extends ConsumerWidget {
  const ConversationWorkTimeSection({super.key, required this.conversationId});

  final String conversationId;

  /// Detail buckets listed under a row; the rest fold into the total.
  static const int _maxDetails = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recorded =
        ref.watch(conversationWorkTimeSummaryProvider(conversationId)).value ??
        ConversationWorkTimeSummary.empty;
    // Running jobs are not recorded until they exit, so add them from the
    // registry. Read, not watched: the polling view provider would keep a
    // one-second timer alive for as long as the companion is on screen. This
    // re-reads whenever the summary changes, which an active turn does after
    // every request and tool call -- close enough to live for a glance.
    final running = ref
        .read(backgroundProcessToolsProvider)
        .conversationJobs(conversationId, tailChars: 0)
        .where((job) => job.isRunning)
        .toList();
    final summary = recorded.withLive(
      ConversationWorkKind.backgroundProcess,
      extraMs: running.fold(0, (total, job) => total + (job.elapsedMs ?? 0)),
      extraCount: running.length,
    );

    final rows = [
      (ConversationWorkKind.llmInference, 'chat.work_time_llm', Icons.memory),
      (ConversationWorkKind.toolExecution, 'chat.work_time_tools', Icons.build),
      (
        ConversationWorkKind.backgroundProcess,
        'chat.work_time_background',
        Icons.terminal,
      ),
      (
        ConversationWorkKind.approvalWait,
        'chat.work_time_approval',
        Icons.front_hand_outlined,
      ),
    ];
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      key: const ValueKey('conversation-work-time'),
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.work_time_title'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (summary.isEmpty)
            Text('chat.work_time_empty'.tr(), style: muted)
          else ...[
            for (final (kind, labelKey, icon) in rows)
              if (summary.countOf(kind) > 0)
                _WorkTimeRow(
                  key: ValueKey('work-time-${kind.name}'),
                  icon: icon,
                  label: labelKey.tr(),
                  summary: summary,
                  kind: kind,
                  runningCount: kind == ConversationWorkKind.backgroundProcess
                      ? running.length
                      : 0,
                ),
            Text('chat.work_time_overlap_note'.tr(), style: muted),
          ],
        ],
      ),
    );
  }
}

class _WorkTimeRow extends StatelessWidget {
  const _WorkTimeRow({
    super.key,
    required this.icon,
    required this.label,
    required this.summary,
    required this.kind,
    required this.runningCount,
  });

  final IconData icon;
  final String label;
  final ConversationWorkTimeSummary summary;
  final ConversationWorkKind kind;
  final int runningCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final details = summary
        .breakdownOf(kind)
        .where((entry) => entry.detail.isNotEmpty && entry.detail != 'running')
        .take(ConversationWorkTimeSection._maxDetails)
        .map(
          (entry) => '${entry.detail} ${formatWorkDuration(entry.durationMs)}',
        )
        .join(' · ');
    final countText = runningCount > 0
        ? '×${summary.countOf(kind) - runningCount} · '
              '${'chat.work_time_running'.tr(namedArgs: {'count': '$runningCount'})}'
        : '×${summary.countOf(kind)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyMedium),
                    ),
                    Text(
                      formatWorkDuration(summary.durationMsOf(kind)),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                Text(countText, style: muted),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: muted,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
