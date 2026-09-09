import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/log_file_cleanup_service.dart';
import '../providers/settings_notifier.dart';

/// Per-system file logging controls.
///
/// Each card maps to one local file sink — LLM session logs, the automated
/// approval audit trail, and the app log file — pairing its controls with a
/// manual delete for what it has already written. The Debug settings page no
/// longer owns any of these; everything user-controllable about file output
/// lives here.
///
/// The approval audit trail deliberately has no switch. It records only the
/// high-risk approvals the user never saw individually, one redacted line
/// each, and never leaves the machine — so unlike session logs there is no
/// exposure to opt out of, and deleting it after the fact serves the same
/// need without blinding the trail while an agent is running.
///
/// Deletion is manual by design. None of the sinks prunes on a timer, and two
/// of them prune only while writing, so turning a switch off freezes whatever
/// is already on disk instead of clearing it.
class LoggingSettingsPage extends ConsumerWidget {
  const LoggingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text('settings.logging_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LogSystemCard(
            target: LogFileTarget.llmSessionLogs,
            title: 'settings.enable_llm_session_logs'.tr(),
            description: 'settings.enable_llm_session_logs_desc'.tr(),
            value: settings.enableLlmSessionLogs,
            onChanged: notifier.updateEnableLlmSessionLogs,
            deleteKey: 'logging-delete-llm-session-logs',
          ),
          const SizedBox(height: 12),
          _LogSystemCard(
            target: LogFileTarget.approvalAudit,
            title: 'settings.approval_audit_log'.tr(),
            description: 'settings.approval_audit_log_desc'.tr(),
            deleteKey: 'logging-delete-approval-audit',
          ),
          const SizedBox(height: 12),
          _LogSystemCard(
            target: LogFileTarget.appLogFile,
            title: 'settings.enable_app_log_file'.tr(),
            description: 'settings.enable_app_log_file_desc'.tr(),
            value: settings.enableAppLogFile,
            onChanged: notifier.updateEnableAppLogFile,
            deleteKey: 'logging-delete-app-log-file',
          ),
        ],
      ),
    );
  }
}

/// One sink: its switch, plus a delete row reporting what is on disk now.
class _LogSystemCard extends ConsumerStatefulWidget {
  const _LogSystemCard({
    required this.target,
    required this.title,
    required this.description,
    required this.deleteKey,
    this.value,
    this.onChanged,
  });

  final LogFileTarget target;
  final String title;
  final String description;

  /// Null for a sink with no opt-out; the card then shows a plain header.
  final bool? value;
  final Future<void> Function(bool)? onChanged;
  final String deleteKey;

  @override
  ConsumerState<_LogSystemCard> createState() => _LogSystemCardState();
}

class _LogSystemCardState extends ConsumerState<_LogSystemCard> {
  LogDirectoryUsage? _usage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshUsage());
  }

  Future<void> _refreshUsage() async {
    final usage = await ref
        .read(logFileCleanupServiceProvider)
        .usage(widget.target);
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('settings.logging_delete_confirm_title'.tr()),
        content: Text(
          'settings.logging_delete_confirm_body'.tr(
            namedArgs: {'name': widget.title},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('settings.logging_delete_confirm_action'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final deleted = await ref
        .read(logFileCleanupServiceProvider)
        .deleteAll(widget.target);
    if (!mounted) return;
    setState(() => _busy = false);
    await _refreshUsage();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'settings.logging_delete_done'.tr(
            namedArgs: {'count': deleted.toString()},
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    final isEmpty = usage == null || usage.isEmpty;
    return Card(
      child: Column(
        children: [
          _header(),
          const Divider(height: 1),
          ListTile(
            key: ValueKey(widget.deleteKey),
            leading: const Icon(Icons.delete_outline),
            title: Text('settings.logging_delete_files'.tr()),
            subtitle: Text(_usageLabel(usage)),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            enabled: !_busy && !isEmpty,
            onTap: _busy || isEmpty ? null : () => unawaited(_confirmAndDelete()),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final value = widget.value;
    final onChanged = widget.onChanged;
    if (value == null || onChanged == null) {
      return ListTile(
        title: Text(widget.title),
        subtitle: Text(widget.description),
      );
    }
    return SwitchListTile(
      title: Text(widget.title),
      subtitle: Text(widget.description),
      value: value,
      onChanged: _busy ? null : (next) => unawaited(onChanged(next)),
    );
  }

  String _usageLabel(LogDirectoryUsage? usage) {
    if (usage == null) return 'settings.logging_usage_loading'.tr();
    if (usage.isEmpty) return 'settings.logging_usage_empty'.tr();
    return 'settings.logging_usage'.tr(
      namedArgs: {
        'count': usage.fileCount.toString(),
        'size': _formatBytes(usage.totalBytes),
      },
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
