import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../chat/data/datasources/mcp_tool_service.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/presentation/providers/mcp_tool_provider.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/settings_notifier.dart';

class ToolsSettingsPage extends ConsumerStatefulWidget {
  const ToolsSettingsPage({super.key});

  @override
  ConsumerState<ToolsSettingsPage> createState() => _ToolsSettingsPageState();
}

class _ToolsSettingsPageState extends ConsumerState<ToolsSettingsPage> {
  final List<TextEditingController> _mcpServerControllers = [];

  @override
  void initState() {
    super.initState();
    _syncServerControllers(
      ref.read(settingsNotifierProvider).configuredMcpServers,
    );
  }

  @override
  void dispose() {
    for (final controller in _mcpServerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncServerControllers(List<McpServerConfig> servers) {
    while (_mcpServerControllers.length < servers.length) {
      _mcpServerControllers.add(TextEditingController());
    }
    while (_mcpServerControllers.length > servers.length) {
      _mcpServerControllers.removeLast().dispose();
    }

    for (var i = 0; i < servers.length; i++) {
      final controller = _mcpServerControllers[i];
      final text = servers[i].url;
      if (controller.text == text) {
        continue;
      }
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _testConnections({
    required AppSettings settings,
    required McpToolService? mcpToolService,
  }) async {
    if (mcpToolService == null) {
      appLog('[Settings] MCP connection test: mcpToolService is null');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('settings.mcp_service_null'.tr())));
      return;
    }

    if (settings.effectiveMcpUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.mcp_no_enabled_servers'.tr())),
      );
      return;
    }

    appLog(
      '[Settings] MCP connection test started: URLs=${settings.effectiveMcpUrls}',
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('settings.mcp_testing'.tr())));

    await mcpToolService.connect();

    if (!mounted) return;

    setState(() {});

    final status = mcpToolService.status;
    final tools = mcpToolService.tools;
    final serverStates = mcpToolService.serverStates;

    appLog(
      '[Settings] MCP connection test result: status=$status, tools=${tools.length}, servers=${serverStates.length}, lastError=${mcpToolService.lastError}',
    );

    if (status == McpConnectionStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'settings.mcp_success'.tr(namedArgs: {'count': '${tools.length}'}),
          ),
        ),
      );
      return;
    }

    final message = status == McpConnectionStatus.disconnected
        ? 'settings.mcp_no_enabled_servers'.tr()
        : 'settings.mcp_failed'.tr(
            namedArgs: {
              'error': mcpToolService.lastError ?? 'common.unknown_error'.tr(),
            },
          );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Map<String, McpServerConnectionInfo> _serverStatesByUrl(
    McpToolService? mcpToolService,
  ) {
    if (mcpToolService == null) {
      return const {};
    }

    return {for (final state in mcpToolService.serverStates) state.url: state};
  }

  Widget _buildMcpServersSection({
    required AppSettings settings,
    required SettingsNotifier notifier,
    required McpToolService? mcpToolService,
  }) {
    final servers = settings.configuredMcpServers;
    final serverStatesByUrl = _serverStatesByUrl(mcpToolService);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildSectionHeader('settings.mcp_servers'.tr())),
            OutlinedButton.icon(
              onPressed: notifier.addMcpServer,
              icon: const Icon(Icons.add),
              label: Text('settings.mcp_add_server'.tr()),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (servers.isEmpty)
          Text(
            'settings.mcp_no_servers'.tr(),
            style: const TextStyle(color: Colors.grey),
          ),
        ...servers.asMap().entries.map((entry) {
          final index = entry.key;
          final server = entry.value;
          final serverState = server.enabled
              ? serverStatesByUrl[server.normalizedUrl]
              : null;

          return _buildMcpServerCard(
            index: index,
            server: server,
            serverState: serverState,
            notifier: notifier,
            mcpEnabledGlobally: settings.mcpEnabled,
          );
        }),
      ],
    );
  }

  Widget _buildMcpServerCard({
    required int index,
    required McpServerConfig server,
    required McpServerConnectionInfo? serverState,
    required SettingsNotifier notifier,
    required bool mcpEnabledGlobally,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (statusText, statusIcon, statusColor) = _serverStatusPresentation(
      server: server,
      serverState: serverState,
      mcpEnabledGlobally: mcpEnabledGlobally,
      colorScheme: colorScheme,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'settings.mcp_server_title'.tr(
                      namedArgs: {'index': '${index + 1}'},
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: server.enabled,
                  onChanged: (value) =>
                      notifier.updateMcpServerEnabled(index, value),
                ),
                IconButton(
                  onPressed: () => notifier.removeMcpServer(index),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'common.delete'.tr(),
                ),
              ],
            ),
            TextField(
              controller: _mcpServerControllers[index],
              decoration: InputDecoration(
                labelText: 'settings.mcp_server_url_label'.tr(),
                hintText: 'http://localhost:8081',
                border: const OutlineInputBorder(),
                helperText: 'settings.mcp_url_helper'.tr(),
              ),
              keyboardType: TextInputType.url,
              onChanged: (value) => notifier.updateMcpServerUrl(index, value),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, IconData, Color) _serverStatusPresentation({
    required McpServerConfig server,
    required McpServerConnectionInfo? serverState,
    required bool mcpEnabledGlobally,
    required ColorScheme colorScheme,
  }) {
    if (!mcpEnabledGlobally) {
      return (
        'settings.mcp_global_disabled'.tr(),
        Icons.toggle_off_outlined,
        Colors.grey,
      );
    }

    if (!server.enabled) {
      return (
        'settings.mcp_server_disabled'.tr(),
        Icons.pause_circle_outline,
        Colors.grey,
      );
    }

    if (server.normalizedUrl.isEmpty) {
      return (
        'settings.mcp_server_empty'.tr(),
        Icons.edit_outlined,
        colorScheme.primary,
      );
    }

    if (serverState == null) {
      return ('settings.mcp_disconnected'.tr(), Icons.link_off, Colors.grey);
    }

    return switch (serverState.status) {
      McpConnectionStatus.connected => (
        'settings.mcp_server_tools'.tr(
          namedArgs: {'count': '${serverState.toolCount}'},
        ),
        Icons.check_circle_outline,
        Colors.green,
      ),
      McpConnectionStatus.connecting => (
        'settings.mcp_connecting'.tr(),
        Icons.hourglass_empty,
        colorScheme.primary,
      ),
      McpConnectionStatus.error => (
        'settings.mcp_error'.tr(
          namedArgs: {'error': serverState.lastError ?? 'common.unknown'.tr()},
        ),
        Icons.error_outline,
        colorScheme.error,
      ),
      McpConnectionStatus.disconnected => (
        'settings.mcp_disconnected'.tr(),
        Icons.link_off,
        Colors.grey,
      ),
    };
  }

  Widget _buildMcpToolsSection(McpToolService? mcpToolService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const SizedBox(height: 12), _buildToolsList(mcpToolService)],
    );
  }

  Widget _buildToolsList(McpToolService? mcpToolService) {
    if (mcpToolService == null) {
      return Text(
        'settings.mcp_service_null'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    final status = mcpToolService.status;
    final tools = mcpToolService.tools;

    if (status == McpConnectionStatus.disconnected) {
      return Text(
        'settings.mcp_disconnected'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    if (status == McpConnectionStatus.connecting) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('settings.mcp_connecting'.tr()),
        ],
      );
    }

    if (status == McpConnectionStatus.error) {
      return Text(
        'settings.mcp_error'.tr(
          namedArgs: {
            'error': mcpToolService.lastError ?? 'common.unknown'.tr(),
          },
        ),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    if (tools.isEmpty) {
      return Text(
        'settings.mcp_no_tools'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'settings.mcp_available_tools'.tr(
            namedArgs: {'count': '${tools.length}'},
          ),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        ...tools.map(
          (tool) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.build_outlined),
              title: Text(tool.originalName ?? tool.name),
              subtitle: Text(
                [
                  tool.description,
                  if (tool.sourceUrl != null) tool.sourceUrl!,
                ].join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              dense: true,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final mcpToolService = ref.watch(mcpToolServiceProvider);

    _syncServerControllers(settings.configuredMcpServers);

    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_tools'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('settings.mcp_section'.tr()),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text('settings.mcp_enable'.tr()),
            subtitle: Text('settings.mcp_enable_desc'.tr()),
            value: settings.mcpEnabled,
            onChanged: notifier.updateMcpEnabled,
          ),
          const SizedBox(height: 8),
          _buildMcpServersSection(
            settings: settings,
            notifier: notifier,
            mcpToolService: mcpToolService,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: settings.mcpEnabled
                ? () => _testConnections(
                    settings: settings,
                    mcpToolService: mcpToolService,
                  )
                : null,
            icon: const Icon(Icons.refresh),
            label: Text('settings.mcp_test_button'.tr()),
          ),
          if (settings.mcpEnabled) _buildMcpToolsSection(mcpToolService),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
