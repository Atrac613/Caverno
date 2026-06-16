import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/maintenance_pipeline.dart';
import '../providers/manual_maintenance_run_notifier.dart';

/// LL18 debug aid: lets the user trigger the maintenance pipeline on demand
/// (bypassing the idle/power/window gate) and watch each stage as it runs.
class IdleMaintenanceDebugPage extends ConsumerWidget {
  const IdleMaintenanceDebugPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualMaintenanceRunNotifierProvider);
    final notifier = ref.read(manualMaintenanceRunNotifierProvider.notifier);
    final formatted = state.formatted;

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.idle_maintenance_debug_title'.tr()),
        actions: [
          if (formatted != null)
            IconButton(
              tooltip: 'settings.idle_maintenance_debug_copy'.tr(),
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => _copyReport(context, formatted.body),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'settings.idle_maintenance_debug_intro'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _RunButton(
            isRunning: state.isRunning,
            onRun: notifier.runNow,
            onCancel: notifier.cancel,
          ),
          if (state.error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(error: state.error!),
          ],
          if (state.stageResults.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'settings.idle_maintenance_debug_stages'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final result in state.stageResults)
              _StageResultTile(result: result),
          ],
          if (formatted != null) ...[
            const SizedBox(height: 16),
            Text(
              formatted.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  formatted.body,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyReport(BuildContext context, String body) async {
    await Clipboard.setData(ClipboardData(text: body));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('settings.idle_maintenance_debug_copied'.tr())),
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.isRunning,
    required this.onRun,
    required this.onCancel,
  });

  final bool isRunning;
  final VoidCallback onRun;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (isRunning) {
      return Row(
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('settings.idle_maintenance_debug_running'.tr()),
          ),
          TextButton(
            key: const ValueKey('idle-maintenance-debug-cancel'),
            onPressed: onCancel,
            child: Text('settings.idle_maintenance_debug_cancel'.tr()),
          ),
        ],
      );
    }
    return FilledButton.icon(
      key: const ValueKey('idle-maintenance-debug-run'),
      onPressed: onRun,
      icon: const Icon(Icons.play_arrow_outlined),
      label: Text('settings.idle_maintenance_debug_run'.tr()),
    );
  }
}

class _StageResultTile extends StatelessWidget {
  const _StageResultTile({required this.result});

  final MaintenanceStageResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = result.detail?.trim() ?? '';
    return Card(
      child: ListTile(
        leading: Icon(
          _statusIcon(result.status),
          color: _statusColor(context, result.status),
        ),
        title: Text(result.name),
        subtitle: detail.isEmpty ? null : Text(detail),
        trailing: Text(
          _formatDuration(result.duration),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(MaintenanceStageStatus status) {
    return switch (status) {
      MaintenanceStageStatus.completed => Icons.check_circle_outline,
      MaintenanceStageStatus.skipped => Icons.remove_circle_outline,
      MaintenanceStageStatus.failed => Icons.error_outline,
      MaintenanceStageStatus.cancelled => Icons.cancel_outlined,
    };
  }

  Color _statusColor(BuildContext context, MaintenanceStageStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      MaintenanceStageStatus.completed => scheme.primary,
      MaintenanceStageStatus.skipped => scheme.onSurfaceVariant,
      MaintenanceStageStatus.failed => scheme.error,
      MaintenanceStageStatus.cancelled => scheme.onSurfaceVariant,
    };
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final seconds = duration.inMilliseconds / 1000;
  return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)}s';
}
