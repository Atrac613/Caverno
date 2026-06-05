import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/browser_session_service.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/built_in_tool_info.dart';
import '../providers/settings_notifier.dart';
import '../../../remote_coding/presentation/remote_coding_settings_page.dart';
import 'built_in_tools_settings_page.dart';
import 'local_command_permission_rules_page.dart';
import 'mcp_servers_settings_page.dart';
import 'routine_computer_use_allowlist_page.dart';
import 'skills_settings_page.dart';

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
          if (BrowserSessionService.isPlatformSupported)
            SwitchListTile(
              secondary: const Icon(Icons.travel_explore),
              title: Text('settings.browser_tools_title'.tr()),
              subtitle: Text('settings.browser_tools_desc'.tr()),
              value: settings.browserToolsEnabled,
              onChanged: notifier.updateBrowserToolsEnabled,
            ),
          const SizedBox(height: 8),
          Text(
            'settings.coding_approval_section'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<ToolApprovalMode>(
              groupValue: settings.codingApprovalMode,
              onChanged: (value) {
                if (value == null) return;
                notifier.updateCodingApprovalMode(value);
              },
              child: Column(
                children: [
                  for (final mode in ToolApprovalMode.values) ...[
                    RadioListTile<ToolApprovalMode>(
                      title: Text(_codingApprovalModeLabel(mode)),
                      subtitle: Text(_codingApprovalModeDescription(mode)),
                      value: mode,
                    ),
                    if (mode != ToolApprovalMode.values.last)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text('settings.coding_agents_md_title'.tr()),
            subtitle: Text('settings.coding_agents_md_desc'.tr()),
            value: settings.enableAgentsMd,
            onChanged: notifier.updateEnableAgentsMd,
          ),
          SwitchListTile(
            title: Text('settings.coding_verification_feedback_title'.tr()),
            subtitle: Text('settings.coding_verification_feedback_desc'.tr()),
            value: settings.enableCodingVerificationFeedback,
            onChanged: notifier.updateEnableCodingVerificationFeedback,
          ),
          if (settings.enableCodingVerificationFeedback)
            _buildCodingVerificationPolicyCard(settings, notifier),
          if (settings.exposesGatedChatTools)
            _buildChatApprovalModeCard(context, settings, notifier),
          const Divider(),
          _buildSkillsTile(context),
          _buildBuiltInToolsTile(context, settings),
          _buildLocalCommandPermissionRulesTile(context, settings),
          _buildRoutineComputerUseAllowlistTile(context, settings),
          _buildRemoteCodingTile(context),
          _buildMcpServersTile(context, settings),
        ],
      ),
    );
  }

  Widget _buildSkillsTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: const Text('Skills'),
      subtitle: const Text('Reusable markdown instructions for repeated work'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SkillsSettingsPage()),
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

  Widget _buildCodingVerificationPolicyCard(
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    final timeoutSeconds = settings.effectiveCodingVerificationTimeoutSeconds
        .toDouble();
    final maxFailures = settings.effectiveCodingVerificationMaxFailures
        .toDouble();

    return Card(
      child: Column(
        children: [
          RadioGroup<CodingVerificationTriggerPolicy>(
            groupValue: settings.codingVerificationTriggerPolicy,
            onChanged: (value) {
              if (value == null) return;
              notifier.updateCodingVerificationTriggerPolicy(value);
            },
            child: Column(
              children: [
                for (final policy in CodingVerificationTriggerPolicy.values)
                  RadioListTile<CodingVerificationTriggerPolicy>(
                    title: Text(_codingVerificationTriggerPolicyLabel(policy)),
                    subtitle: Text(
                      _codingVerificationTriggerPolicyDescription(policy),
                    ),
                    value: policy,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(
              'settings.coding_verification_timeout_title'.tr(
                namedArgs: {'seconds': '${timeoutSeconds.round()}'},
              ),
            ),
            subtitle: Slider(
              value: timeoutSeconds,
              min: AppSettings.minCodingVerificationTimeoutSeconds.toDouble(),
              max: AppSettings.maxCodingVerificationTimeoutSeconds.toDouble(),
              divisions:
                  (AppSettings.maxCodingVerificationTimeoutSeconds -
                      AppSettings.minCodingVerificationTimeoutSeconds) ~/
                  10,
              label: '${timeoutSeconds.round()}s',
              onChanged: (value) {
                notifier.updateCodingVerificationTimeoutSeconds(value.round());
              },
            ),
          ),
          ListTile(
            title: Text(
              'settings.coding_verification_max_failures_title'.tr(
                namedArgs: {'count': '${maxFailures.round()}'},
              ),
            ),
            subtitle: Slider(
              value: maxFailures,
              min: AppSettings.minCodingVerificationMaxFailures.toDouble(),
              max: AppSettings.maxCodingVerificationMaxFailures.toDouble(),
              divisions:
                  AppSettings.maxCodingVerificationMaxFailures -
                  AppSettings.minCodingVerificationMaxFailures,
              label: '${maxFailures.round()}',
              onChanged: (value) {
                notifier.updateCodingVerificationMaxFailures(value.round());
              },
            ),
          ),
        ],
      ),
    );
  }

  String _codingVerificationTriggerPolicyLabel(
    CodingVerificationTriggerPolicy policy,
  ) {
    return switch (policy) {
      CodingVerificationTriggerPolicy.onCompletionClaim =>
        'settings.coding_verification_trigger_completion'.tr(),
      CodingVerificationTriggerPolicy.onRequestOnly =>
        'settings.coding_verification_trigger_request_only'.tr(),
      CodingVerificationTriggerPolicy.off =>
        'settings.coding_verification_trigger_off'.tr(),
    };
  }

  String _codingVerificationTriggerPolicyDescription(
    CodingVerificationTriggerPolicy policy,
  ) {
    return switch (policy) {
      CodingVerificationTriggerPolicy.onCompletionClaim =>
        'settings.coding_verification_trigger_completion_desc'.tr(),
      CodingVerificationTriggerPolicy.onRequestOnly =>
        'settings.coding_verification_trigger_request_only_desc'.tr(),
      CodingVerificationTriggerPolicy.off =>
        'settings.coding_verification_trigger_off_desc'.tr(),
    };
  }

  Widget _buildChatApprovalModeCard(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'settings.chat_approval_section'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: RadioGroup<ToolApprovalMode>(
              groupValue: settings.chatApprovalMode,
              onChanged: (value) {
                if (value == null) return;
                notifier.updateChatApprovalMode(value);
              },
              child: Column(
                children: [
                  for (final mode in ToolApprovalMode.values) ...[
                    RadioListTile<ToolApprovalMode>(
                      secondary: const Icon(Icons.shield_outlined),
                      title: Text(_chatApprovalModeLabel(mode)),
                      subtitle: Text(_chatApprovalModeDescription(mode)),
                      value: mode,
                    ),
                    if (mode != ToolApprovalMode.values.last)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _chatApprovalModeLabel(ToolApprovalMode mode) {
    return switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.chat_approval_default'.tr(),
      ToolApprovalMode.autoReview => 'settings.chat_approval_auto_review'.tr(),
      ToolApprovalMode.fullAccess =>
        'settings.chat_approval_full_access'.tr(),
    };
  }

  String _chatApprovalModeDescription(ToolApprovalMode mode) {
    return switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.chat_approval_default_desc'.tr(),
      ToolApprovalMode.autoReview =>
        'settings.chat_approval_auto_review_desc'.tr(),
      ToolApprovalMode.fullAccess =>
        'settings.chat_approval_full_access_desc'.tr(),
    };
  }

  String _codingApprovalModeLabel(ToolApprovalMode mode) {
    return switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.coding_approval_default'.tr(),
      ToolApprovalMode.autoReview =>
        'settings.coding_approval_auto_review'.tr(),
      ToolApprovalMode.fullAccess =>
        'settings.coding_approval_full_access'.tr(),
    };
  }

  String _codingApprovalModeDescription(ToolApprovalMode mode) {
    return switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.coding_approval_default_desc'.tr(),
      ToolApprovalMode.autoReview =>
        'settings.coding_approval_auto_review_desc'.tr(),
      ToolApprovalMode.fullAccess =>
        'settings.coding_approval_full_access_desc'.tr(),
    };
  }
}
