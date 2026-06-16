import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../maintenance/presentation/pages/idle_maintenance_settings_page.dart';
import '../../../personal_eval/presentation/pages/personal_eval_cases_page.dart';
import 'debug_settings_page.dart';
import 'model_harness_config_settings_page.dart';
import 'model_routing_settings_page.dart';

class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key, required this.computerUseBuilder});

  final WidgetBuilder computerUseBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_advanced'.tr())),
      body: ListView(
        children: [
          ListTile(
            key: const ValueKey('settings-menu-computer-use'),
            leading: const Icon(Icons.desktop_windows_outlined),
            title: Text('settings.menu_computer_use'.tr()),
            subtitle: Text('settings.menu_computer_use_desc'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: computerUseBuilder),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('settings-menu-model-routing'),
            leading: const Icon(Icons.alt_route_outlined),
            title: Text('settings.model_routing_title'.tr()),
            subtitle: Text('settings.model_routing_menu_desc'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ModelRoutingSettingsPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('settings-menu-harness-config'),
            leading: const Icon(Icons.tune_outlined),
            title: Text('settings.harness_config_title'.tr()),
            subtitle: Text('settings.harness_config_menu_desc'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ModelHarnessConfigSettingsPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('settings-menu-personal-eval-cases'),
            leading: const Icon(Icons.fact_check_outlined),
            title: Text('settings.personal_eval_cases_title'.tr()),
            subtitle: Text('settings.personal_eval_cases_menu_desc'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PersonalEvalCasesPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('settings-menu-idle-maintenance'),
            leading: const Icon(Icons.nightlight_outlined),
            title: Text('settings.idle_maintenance_title'.tr()),
            subtitle: Text('settings.idle_maintenance_menu_desc'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const IdleMaintenanceSettingsPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('settings-menu-debug'),
            leading: const Icon(Icons.bug_report_outlined),
            title: Text('settings.menu_debug'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebugSettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
