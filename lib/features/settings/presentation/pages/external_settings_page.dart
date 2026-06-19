import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/external_settings_service.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/settings_notifier.dart';

class ExternalSettingsPage extends ConsumerStatefulWidget {
  const ExternalSettingsPage({super.key});

  @override
  ConsumerState<ExternalSettingsPage> createState() =>
      _ExternalSettingsPageState();
}

class _ExternalSettingsPageState extends ConsumerState<ExternalSettingsPage> {
  late final TextEditingController _pathController;
  late final FocusNode _pathFocusNode;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
    _pathFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _pathFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final enabledHooks = settings.externalToolHooks
        .where((hook) => hook.enabled && hook.isUsable)
        .length;
    final managedServers = settings.configuredMcpServers
        .where((server) => server.sourceId.isNotEmpty)
        .toList(growable: false);

    if (!_pathFocusNode.hasFocus &&
        _pathController.text != settings.externalSettingsPath) {
      _pathController.text = settings.externalSettingsPath;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('External Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _pathController,
            focusNode: _pathFocusNode,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Caverno config path',
              prefixIcon: const Icon(Icons.description_outlined),
              suffixIcon: IconButton(
                tooltip: 'Save path',
                icon: const Icon(Icons.save_outlined),
                onPressed: () => _savePath(notifier),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _savePath(notifier),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            secondary: const Icon(Icons.sync_outlined),
            title: const Text('Sync external config'),
            subtitle: Text(settings.normalizedExternalSettingsPath),
            value: settings.externalSettingsSyncEnabled,
            onChanged: notifier.updateExternalSettingsSyncEnabled,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bolt_outlined),
            title: const Text('Run external hooks'),
            subtitle: Text('$enabledHooks hook(s) configured'),
            value: settings.externalToolHooksEnabled,
            onChanged: notifier.updateExternalToolHooksEnabled,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('Apply agent-kb preset'),
                  onPressed: () async {
                    await notifier.applyAgentKbIntegrationPreset();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('agent-kb integration enabled.'),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Sync now'),
                onPressed: settings.externalSettingsSyncEnabled
                    ? () async {
                        await _savePath(notifier, showSnackBar: false);
                        final changed = await notifier.syncExternalSettings();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              changed
                                  ? 'External config synced.'
                                  : 'External config is already current.',
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Managed MCP Servers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < managedServers.length; index++) ...[
                  ListTile(
                    leading: Icon(
                      managedServers[index].type == McpServerType.http
                          ? Icons.link_outlined
                          : Icons.terminal_outlined,
                    ),
                    title: Text(managedServers[index].displayLabel),
                    subtitle: Text(
                      _sourceLabel(managedServers[index].sourceId),
                    ),
                  ),
                  if (index != managedServers.length - 1)
                    const Divider(height: 1),
                ],
                if (managedServers.isEmpty)
                  const ListTile(title: Text('No managed MCP servers')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePath(
    SettingsNotifier notifier, {
    bool showSnackBar = true,
  }) async {
    final path = _pathController.text.trim();
    await notifier.updateExternalSettingsPath(path);
    if (!mounted || !showSnackBar) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('External config path saved.')),
    );
  }

  String _sourceLabel(String sourceId) {
    return switch (sourceId) {
      ExternalSettingsService.cavernoConfigSourceId => 'Caverno config',
      ExternalSettingsService.agentKbPresetSourceId => 'agent-kb preset',
      _ => sourceId,
    };
  }
}
