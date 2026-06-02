import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/macos_computer_use_service.dart';
import '../widgets/settings_actions_menu.dart';
import 'advanced_settings_page.dart';
import 'computer_use_settings_page.dart';
import 'general_settings_page.dart';
import 'chat_settings_page.dart';
import 'slash_command_settings_page.dart';
import 'voice_settings_page.dart';
import 'tools_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
        actions: const [SettingsActionsMenu()],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text('settings.menu_general'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GeneralSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: Text('settings.menu_chat'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('settings-menu-slash-commands'),
            leading: const Icon(Icons.terminal_outlined),
            title: Text('settings.menu_slash_commands'.tr()),
            subtitle: Text('settings.menu_slash_commands_desc'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SlashCommandSettingsPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.mic_outlined),
            title: Text('settings.menu_voice'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VoiceSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.build_outlined),
            title: Text('settings.menu_tools'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ToolsSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('settings-menu-advanced'),
            leading: const Icon(Icons.tune_outlined),
            title: Text('settings.menu_advanced'.tr()),
            subtitle: const _AdvancedSettingsSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdvancedSettingsPage(
                    computerUseBuilder: (_) => const ComputerUseSettingsPage(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdvancedSettingsSubtitle extends ConsumerWidget {
  const _AdvancedSettingsSubtitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final computerUseAvailable = ref.watch(
      macosComputerUseServiceProvider.select((service) => service.isAvailable),
    );
    final key = computerUseAvailable
        ? 'settings.menu_advanced_desc_computer_use_available'
        : 'settings.menu_advanced_desc_computer_use_unavailable';
    return Text(key.tr());
  }
}
