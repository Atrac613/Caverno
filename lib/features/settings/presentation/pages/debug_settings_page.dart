import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_notifier.dart';
import 'computer_use_debug_page.dart';

class DebugSettingsPage extends ConsumerWidget {
  const DebugSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);

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
