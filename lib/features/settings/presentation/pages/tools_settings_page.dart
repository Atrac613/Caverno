import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/built_in_tool_info.dart';
import '../providers/settings_notifier.dart';
import 'built_in_tools_settings_page.dart';
import 'mcp_servers_settings_page.dart';

class ToolsSettingsPage extends ConsumerWidget {
  const ToolsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_tools'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: Text('settings.mcp_enable'.tr()),
            subtitle: Text('settings.mcp_enable_desc'.tr()),
            value: settings.mcpEnabled,
            onChanged: notifier.updateMcpEnabled,
          ),
          const Divider(),
          _buildBuiltInToolsTile(context, settings),
          _buildMcpServersTile(context, settings),
        ],
      ),
    );
  }

  Widget _buildBuiltInToolsTile(BuildContext context, AppSettings settings) {
    final total = BuiltInToolRegistry.tools.length;
    final enabled = total - settings.disabledBuiltInTools.length;

    return ListTile(
      leading: const Icon(Icons.build_outlined),
      title: Text('settings.built_in_tools'.tr()),
      subtitle: Text(
        'settings.built_in_tools_desc'.tr(
          namedArgs: {'enabled': '$enabled', 'total': '$total'},
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BuiltInToolsSettingsPage()),
      ),
    );
  }

  Widget _buildMcpServersTile(BuildContext context, AppSettings settings) {
    final serverCount = settings.enabledMcpServers.length;

    return ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: Text('settings.mcp_servers'.tr()),
      subtitle: Text(
        'settings.mcp_servers_desc'.tr(
          namedArgs: {'count': '$serverCount'},
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const McpServersSettingsPage()),
      ),
    );
  }
}
