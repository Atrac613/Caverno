import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/macos_update_service.dart';
import '../providers/settings_notifier.dart';
import 'computer_use_debug_page.dart';
import 'live_llm_diagnostic_page.dart';

class DebugSettingsPage extends ConsumerWidget {
  const DebugSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final updateService = ref.watch(macosUpdateServiceProvider);

    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_debug'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'settings.debug_section'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text('settings.show_memory_updates'.tr()),
                  subtitle: Text('settings.show_memory_updates_desc'.tr()),
                  value: settings.showMemoryUpdates,
                  onChanged: notifier.updateShowMemoryUpdates,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text('settings.enable_llm_session_logs'.tr()),
                  subtitle: Text('settings.enable_llm_session_logs_desc'.tr()),
                  value: settings.enableLlmSessionLogs,
                  onChanged: notifier.updateEnableLlmSessionLogs,
                ),
                const Divider(height: 1),
                _MacosUpdateTile(service: updateService),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: Text('settings.live_llm_diagnostics'.tr()),
                  subtitle: Text('settings.live_llm_diagnostics_desc'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveLlmDiagnosticPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.desktop_mac_outlined),
                  title: const Text('Computer Use Smoke Sequence'),
                  subtitle: const Text(
                    'Run direct macOS permission, screenshot, window, input, and audio checks.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ComputerUseDebugPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacosUpdateTile extends StatefulWidget {
  const _MacosUpdateTile({required this.service});

  final MacosUpdateService service;

  @override
  State<_MacosUpdateTile> createState() => _MacosUpdateTileState();
}

class _MacosUpdateTileState extends State<_MacosUpdateTile> {
  late Future<MacosUpdateStatus> _statusFuture;
  bool _checking = false;
  String? _lastMessage;

  @override
  void initState() {
    super.initState();
    _statusFuture = widget.service.getStatus();
  }

  @override
  void didUpdateWidget(_MacosUpdateTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _statusFuture = widget.service.getStatus();
      _lastMessage = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MacosUpdateStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final title = Text('settings.macos_updates_title'.tr());
        final subtitle = Text(_subtitleFor(status, snapshot.hasError));
        return ListTile(
          leading: const Icon(Icons.system_update_alt_outlined),
          title: title,
          subtitle: subtitle,
          trailing: TextButton(
            onPressed: status != null && status.configured && !_checking
                ? _checkForUpdates
                : null,
            child: _checking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('settings.macos_updates_check'.tr()),
          ),
        );
      },
    );
  }

  String _subtitleFor(MacosUpdateStatus? status, bool hasError) {
    if (hasError) {
      return 'settings.macos_updates_status_failed'.tr();
    }
    if (status == null) {
      return 'settings.macos_updates_status_loading'.tr();
    }
    if (!status.available) {
      return status.nextAction ??
          'settings.macos_updates_status_unavailable'.tr();
    }
    if (!status.configured) {
      return status.nextAction ??
          'settings.macos_updates_status_unconfigured'.tr();
    }
    final version = status.displayVersion.isEmpty
        ? 'unknown'
        : status.displayVersion;
    final message = _lastMessage;
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return 'settings.macos_updates_status_configured'.tr(
      namedArgs: {
        'version': version,
        'interval': status.updateCheckIntervalSeconds.round().toString(),
      },
    );
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _lastMessage = null;
    });

    try {
      final status = await widget.service.checkForUpdates();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusFuture = Future<MacosUpdateStatus>.value(status);
        _lastMessage = 'settings.macos_updates_check_started'.tr();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastMessage = 'settings.macos_updates_check_failed'.tr(
          namedArgs: {'error': error.toString()},
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }
}
