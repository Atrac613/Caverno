import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import 'idle_maintenance_debug_page.dart';

/// LL18: lets the user configure the idle/overnight maintenance gate (enable,
/// maintenance window, minimum idle, require AC power). The orchestrator and
/// its scheduler (later slices) read these via `idleMaintenanceConfigProvider`.
class IdleMaintenanceSettingsPage extends ConsumerWidget {
  const IdleMaintenanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final enabled = settings.idleMaintenanceEnabled;

    return Scaffold(
      appBar: AppBar(title: Text('settings.idle_maintenance_title'.tr())),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'settings.idle_maintenance_intro'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SwitchListTile(
            key: const ValueKey('idle-maintenance-enabled'),
            title: Text('settings.idle_maintenance_enable'.tr()),
            subtitle: Text('settings.idle_maintenance_enable_desc'.tr()),
            value: enabled,
            onChanged: (value) =>
                notifier.updateIdleMaintenance(enabled: value),
          ),
          const Divider(height: 1),
          ListTile(
            enabled: enabled,
            title: Text('settings.idle_maintenance_window_start'.tr()),
            trailing: Text(
              _formatMinutes(settings.idleMaintenanceWindowStartMinutes),
            ),
            onTap: enabled
                ? () => _pickTime(
                    context,
                    settings.idleMaintenanceWindowStartMinutes,
                    (minutes) => notifier.updateIdleMaintenance(
                      windowStartMinutes: minutes,
                    ),
                  )
                : null,
          ),
          ListTile(
            enabled: enabled,
            title: Text('settings.idle_maintenance_window_end'.tr()),
            trailing: Text(
              _formatMinutes(settings.idleMaintenanceWindowEndMinutes),
            ),
            onTap: enabled
                ? () => _pickTime(
                    context,
                    settings.idleMaintenanceWindowEndMinutes,
                    (minutes) => notifier.updateIdleMaintenance(
                      windowEndMinutes: minutes,
                    ),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'settings.idle_maintenance_window_hint'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            enabled: enabled,
            title: Text('settings.idle_maintenance_min_idle'.tr()),
            trailing: Text(
              'settings.idle_maintenance_minutes'.tr(
                args: ['${settings.idleMaintenanceMinIdleMinutes}'],
              ),
            ),
          ),
          Slider(
            key: const ValueKey('idle-maintenance-min-idle'),
            min: 1,
            max: 60,
            divisions: 59,
            value: settings.idleMaintenanceMinIdleMinutes.toDouble().clamp(
              1,
              60,
            ),
            label: '${settings.idleMaintenanceMinIdleMinutes}',
            onChanged: enabled
                ? (value) => notifier.updateIdleMaintenance(
                    minIdleMinutes: value.round(),
                  )
                : null,
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const ValueKey('idle-maintenance-require-ac'),
            title: Text('settings.idle_maintenance_require_ac'.tr()),
            subtitle: Text('settings.idle_maintenance_require_ac_desc'.tr()),
            value: settings.idleMaintenanceRequireAcPower,
            onChanged: enabled
                ? (value) =>
                      notifier.updateIdleMaintenance(requireAcPower: value)
                : null,
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('idle-maintenance-debug-run-now'),
            leading: const Icon(Icons.science_outlined),
            title: Text('settings.idle_maintenance_debug_menu'.tr()),
            subtitle: Text('settings.idle_maintenance_debug_menu_desc'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const IdleMaintenanceDebugPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    int currentMinutes,
    void Function(int minutes) onPicked,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      ),
    );
    if (picked != null) {
      onPicked(picked.hour * 60 + picked.minute);
    }
  }

  static String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
