import 'package:caverno/features/maintenance/presentation/providers/idle_maintenance_config_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> buildContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('maps default settings to the gating config', () async {
    final container = await buildContainer();
    final config = container.read(idleMaintenanceConfigProvider);

    expect(config.enabled, isFalse);
    expect(config.windowStartMinutes, 120);
    expect(config.windowEndMinutes, 360);
    expect(config.minIdle, const Duration(minutes: 10));
    expect(config.requireAcPower, isTrue);
  });

  test('reflects updated settings', () async {
    final container = await buildContainer();
    await container
        .read(settingsNotifierProvider.notifier)
        .updateIdleMaintenance(
          enabled: true,
          windowStartMinutes: 23 * 60,
          windowEndMinutes: 6 * 60,
          minIdleMinutes: 20,
          requireAcPower: false,
        );

    final config = container.read(idleMaintenanceConfigProvider);
    expect(config.enabled, isTrue);
    expect(config.windowStartMinutes, 23 * 60);
    expect(config.windowEndMinutes, 6 * 60);
    expect(config.minIdle, const Duration(minutes: 20));
    expect(config.requireAcPower, isFalse);
  });

  test('persists across container reloads', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    await first
        .read(settingsNotifierProvider.notifier)
        .updateIdleMaintenance(enabled: true, minIdleMinutes: 15);
    first.dispose();

    // A fresh container backed by the same SharedPreferences reloads the saved
    // values.
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);
    final config = second.read(idleMaintenanceConfigProvider);
    expect(config.enabled, isTrue);
    expect(config.minIdle, const Duration(minutes: 15));
  });
}
