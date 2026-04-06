import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/debouncer.dart';
import '../../../../core/utils/logger.dart';
import '../../../chat/data/datasources/mcp_tool_service.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/presentation/providers/mcp_tool_provider.dart';
import '../providers/settings_notifier.dart';

class ToolsSettingsPage extends ConsumerStatefulWidget {
  const ToolsSettingsPage({super.key});

  @override
  ConsumerState<ToolsSettingsPage> createState() => _ToolsSettingsPageState();
}

class _ToolsSettingsPageState extends ConsumerState<ToolsSettingsPage> {
  late TextEditingController _mcpUrlController;
  final _mcpUrlDebouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    _mcpUrlController = TextEditingController(text: settings.mcpUrl);
  }

  @override
  void dispose() {
    _mcpUrlDebouncer.dispose();
    _mcpUrlController.dispose();
    super.dispose();
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

  Widget _buildMcpToolsSection() {
    final mcpToolService = ref.watch(mcpToolServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connection test button
        OutlinedButton.icon(
          onPressed: () async {
            if (mcpToolService == null) {
              appLog('[Settings] MCP connection test: mcpToolService is null');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('settings.mcp_service_null'.tr())),
              );
              return;
            }

            final testUrl = _mcpUrlController.text.trim();
            appLog('[Settings] MCP connection test started: URL=$testUrl');

            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('settings.mcp_testing'.tr())));

            await mcpToolService.connect(overrideUrl: testUrl);

            if (!mounted) return;

            final status = mcpToolService.status;
            final tools = mcpToolService.tools;

            appLog(
              '[Settings] MCP connection test result: status=$status, tools=${tools.length}, lastError=${mcpToolService.lastError}',
            );

            if (status == McpConnectionStatus.connected) {
              appLog(
                '[Settings] Connection succeeded: tools=${tools.map((t) => t.name).toList()}',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'settings.mcp_success'.tr(namedArgs: {'count': '${tools.length}'}),
                  ),
                ),
              );
              setState(() {}); // Refresh the tool list.
            } else {
              appLog('[Settings] Connection failed: ${mcpToolService.lastError}');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'settings.mcp_failed'.tr(namedArgs: {
                      'error': mcpToolService.lastError ?? 'common.unknown_error'.tr(),
                    }),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          },
          icon: const Icon(Icons.refresh),
          label: Text('settings.mcp_test_button'.tr()),
        ),
        const SizedBox(height: 12),
        // Tool list
        _buildToolsList(mcpToolService),
      ],
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
        'settings.mcp_error'.tr(namedArgs: {
          'error': mcpToolService.lastError ?? 'common.unknown'.tr(),
        }),
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
          'settings.mcp_available_tools'.tr(namedArgs: {'count': '${tools.length}'}),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        ...tools.map(
          (tool) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.build_outlined),
              title: Text(tool.name),
              subtitle: Text(
                tool.description,
                maxLines: 2,
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

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.menu_tools'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // MCP settings section
          _buildSectionHeader('settings.mcp_section'.tr()),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text('settings.mcp_enable'.tr()),
            subtitle: Text('settings.mcp_enable_desc'.tr()),
            value: settings.mcpEnabled,
            onChanged: (value) => notifier.updateMcpEnabled(value),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _mcpUrlController,
            enabled: settings.mcpEnabled,
            decoration: InputDecoration(
              labelText: 'MCP Server URL',
              hintText: 'http://localhost:8081',
              border: const OutlineInputBorder(),
              helperText: 'settings.mcp_url_helper'.tr(),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) {
              _mcpUrlDebouncer.run(() {
                notifier.updateMcpUrl(_mcpUrlController.text.trim());
              });
            },
          ),
          const SizedBox(height: 16),
          // Connection test button and tool list
          if (settings.mcpEnabled) _buildMcpToolsSection(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
