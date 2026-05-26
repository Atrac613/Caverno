import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/built_in_tool_info.dart';
import '../providers/settings_notifier.dart';
import '../../../remote_coding/presentation/remote_coding_settings_page.dart';
import 'built_in_tools_settings_page.dart';
import 'local_command_permission_rules_page.dart';
import 'mcp_servers_settings_page.dart';
import 'routine_computer_use_allowlist_page.dart';

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
          const SizedBox(height: 8),
          Text(
            'settings.coding_approval_section'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<CodingApprovalMode>(
              groupValue: settings.codingApprovalMode,
              onChanged: (value) {
                if (value == null) return;
                notifier.updateCodingApprovalMode(value);
              },
              child: Column(
                children: [
                  for (final mode in CodingApprovalMode.values) ...[
                    RadioListTile<CodingApprovalMode>(
                      title: Text(_codingApprovalModeLabel(mode)),
                      subtitle: Text(_codingApprovalModeDescription(mode)),
                      value: mode,
                    ),
                    if (mode != CodingApprovalMode.values.last)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
          const Divider(),
          _buildBuiltInToolsTile(context, settings),
          _buildLocalCommandPermissionRulesTile(context, settings),
          _buildRoutineComputerUseAllowlistTile(context, settings),
          _buildRemoteCodingTile(context),
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

  Widget _buildLocalCommandPermissionRulesTile(
    BuildContext context,
    AppSettings settings,
  ) {
    final enabledCount = settings.enabledLocalCommandPermissionRules.length;
    final totalCount = settings.localCommandPermissionRules.length;

    return ListTile(
      leading: const Icon(Icons.verified_user_outlined),
      title: const Text('Local Command Rules'),
      subtitle: Text('$enabledCount of $totalCount saved rule(s) enabled'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LocalCommandPermissionRulesPage(),
        ),
      ),
    );
  }

  Widget _buildRoutineComputerUseAllowlistTile(
    BuildContext context,
    AppSettings settings,
  ) {
    final enabledCount =
        settings.enabledRoutineComputerUseActionAllowlist.length;
    final totalCount = settings.routineComputerUseActionAllowlist.length;

    return ListTile(
      leading: const Icon(Icons.playlist_add_check_outlined),
      title: Text('settings.routine_computer_use_allowlist'.tr()),
      subtitle: Text(
        'settings.routine_computer_use_allowlist_desc'.tr(
          namedArgs: {'enabled': '$enabledCount', 'total': '$totalCount'},
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const RoutineComputerUseAllowlistPage(),
        ),
      ),
    );
  }

  Widget _buildMcpServersTile(BuildContext context, AppSettings settings) {
    final serverCount = settings.enabledMcpServers.length;

    return ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: Text('settings.mcp_servers'.tr()),
      subtitle: Text(
        'settings.mcp_servers_desc'.tr(namedArgs: {'count': '$serverCount'}),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const McpServersSettingsPage()),
      ),
    );
  }

  Widget _buildRemoteCodingTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.phonelink),
      title: const Text('Remote Coding Host'),
      subtitle: const Text('Pair mobile devices for LAN coding control'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RemoteCodingSettingsPage()),
      ),
    );
  }

  String _codingApprovalModeLabel(CodingApprovalMode mode) {
    return switch (mode) {
      CodingApprovalMode.defaultPermissions =>
        'settings.coding_approval_default'.tr(),
      CodingApprovalMode.autoReview =>
        'settings.coding_approval_auto_review'.tr(),
      CodingApprovalMode.fullAccess =>
        'settings.coding_approval_full_access'.tr(),
    };
  }

  String _codingApprovalModeDescription(CodingApprovalMode mode) {
    return switch (mode) {
      CodingApprovalMode.defaultPermissions =>
        'settings.coding_approval_default_desc'.tr(),
      CodingApprovalMode.autoReview =>
        'settings.coding_approval_auto_review_desc'.tr(),
      CodingApprovalMode.fullAccess =>
        'settings.coding_approval_full_access_desc'.tr(),
    };
  }
}
