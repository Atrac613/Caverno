import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/background_process_monitor_snapshot.dart';
import '../../data/datasources/background_process_tools.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../providers/background_process_view_provider.dart';
import '../providers/mcp_tool_provider.dart';

/// Formats a job's run time the way a glance wants it: `45s`, `2m 21s`,
/// `1h 03m`.
String formatBackgroundProcessElapsed(int? elapsedMs) {
  final seconds = ((elapsedMs ?? 0) / 1000).floor();
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// Sidebar body listing the current conversation's background jobs.
class BackgroundProcessPanel extends ConsumerWidget {
  const BackgroundProcessPanel({super.key, required this.conversationId});

  /// The panel for [conversationId], or null where no local shell can run a
  /// background job and the tab would only ever be empty.
  static BackgroundProcessPanel? of(String conversationId) =>
      LocalShellTools.isDesktopPlatform
      ? BackgroundProcessPanel(conversationId: conversationId)
      : null;

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final jobs =
        ref
            .watch(conversationBackgroundProcessesProvider(conversationId))
            .value ??
        const <BackgroundProcessMonitorSnapshot>[];
    if (jobs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'chat.background_processes_empty'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final running = jobs.where((job) => job.isRunning).toList();
    final finished = jobs.where((job) => !job.isRunning).toList();
    void stop(String jobId) {
      ref
          .read(backgroundProcessToolsProvider)
          .stopConversationJob(conversationId, jobId);
      ref.invalidate(conversationBackgroundProcessesProvider(conversationId));
    }

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return ListView(
      key: const ValueKey('background-process-panel'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: [
        if (running.isNotEmpty) ...[
          header(
            'chat.background_processes_running'.tr(
              namedArgs: {'count': '${running.length}'},
            ),
          ),
          for (final job in running)
            BackgroundProcessCard(
              key: ValueKey('background-process-${job.jobId}'),
              job: job,
              onStop: () => stop(job.jobId),
            ),
        ],
        if (finished.isNotEmpty) ...[
          header(
            'chat.background_processes_finished'.tr(
              namedArgs: {'count': '${finished.length}'},
            ),
          ),
          for (final job in finished)
            BackgroundProcessCard(
              key: ValueKey('background-process-${job.jobId}'),
              job: job,
            ),
        ],
      ],
    );
  }
}

/// One job: a header row that toggles the command and its output tail.
class BackgroundProcessCard extends StatefulWidget {
  const BackgroundProcessCard({super.key, required this.job, this.onStop});

  final BackgroundProcessMonitorSnapshot job;
  final VoidCallback? onStop;

  @override
  State<BackgroundProcessCard> createState() => _BackgroundProcessCardState();
}

class _BackgroundProcessCardState extends State<BackgroundProcessCard> {
  // Running jobs open by default: their output is the reason to look.
  late bool _expanded = widget.job.isRunning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final job = widget.job;
    final label = job.label?.trim();
    final title = label == null || label.isEmpty ? job.command : label;
    final meta = [
      formatBackgroundProcessElapsed(job.elapsedMs),
      if (job.exitCode != null)
        'chat.background_processes_exit_code'.tr(
          namedArgs: {'code': '${job.exitCode}'},
        ),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  _BackgroundProcessStatusIcon(job: job),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          meta,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onStop != null)
                    IconButton(
                      key: ValueKey('background-process-stop-${job.jobId}'),
                      onPressed: widget.onStop,
                      icon: const Icon(Icons.stop_circle_outlined, size: 20),
                      tooltip: 'chat.background_processes_stop'.tr(),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded) _BackgroundProcessDetails(job: job),
        ],
      ),
    );
  }
}

class _BackgroundProcessStatusIcon extends StatelessWidget {
  const _BackgroundProcessStatusIcon({required this.job});

  final BackgroundProcessMonitorSnapshot job;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (job.isRunning) {
      return const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final failed = job.hasFailedExit || !job.ok;
    return Icon(
      failed ? Icons.error_outline : Icons.check_circle_outline,
      size: 18,
      color: failed ? colors.error : colors.primary,
    );
  }
}

class _BackgroundProcessDetails extends StatelessWidget {
  const _BackgroundProcessDetails({required this.job});

  final BackgroundProcessMonitorSnapshot job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      height: 1.35,
    );
    final stdout = job.stdoutTail.trimRight();
    final stderr = job.stderrTail.trimRight();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SelectableText('\$ ${job.command}', style: mono)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: job.command)),
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'chat.background_processes_copy_command'.tr(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.dividerColor),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: stdout.isEmpty && stderr.isEmpty
                  ? Text(
                      'chat.background_processes_no_output'.tr(),
                      style: mono?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : SelectableText.rich(
                      TextSpan(
                        style: mono,
                        children: [
                          if (stdout.isNotEmpty) TextSpan(text: stdout),
                          if (stdout.isNotEmpty && stderr.isNotEmpty)
                            const TextSpan(text: '\n'),
                          if (stderr.isNotEmpty)
                            TextSpan(
                              text: stderr,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
