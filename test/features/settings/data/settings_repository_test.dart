import 'dart:convert';

import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const settingsKey = 'app_settings';
  const llmSessionLogsDefaultOnMigrationKey =
      'migration.enable_llm_session_logs_default_on.v1';

  test('migrates legacy saved session log default to enabled', () async {
    final legacySettings = AppSettings.defaults()
        .copyWith(enableLlmSessionLogs: false)
        .toJson();
    SharedPreferences.setMockInitialValues(<String, Object>{
      settingsKey: jsonEncode(legacySettings),
    });

    final prefs = await SharedPreferences.getInstance();
    final loaded = SettingsRepository(prefs).load();

    expect(loaded.enableLlmSessionLogs, isTrue);

    await Future<void>.delayed(Duration.zero);
    final persistedJson =
        jsonDecode(prefs.getString(settingsKey)!) as Map<String, dynamic>;
    expect(persistedJson['enableLlmSessionLogs'], isTrue);
    expect(prefs.getBool(llmSessionLogsDefaultOnMigrationKey), isTrue);
  });

  test('preserves a session log opt-out after migration', () async {
    final optedOutSettings = AppSettings.defaults()
        .copyWith(enableLlmSessionLogs: false)
        .toJson();
    SharedPreferences.setMockInitialValues(<String, Object>{
      settingsKey: jsonEncode(optedOutSettings),
      llmSessionLogsDefaultOnMigrationKey: true,
    });

    final prefs = await SharedPreferences.getInstance();
    final loaded = SettingsRepository(prefs).load();

    expect(loaded.enableLlmSessionLogs, isFalse);
  });

  test('supports a read-only load without persisting migrations', () async {
    final legacySettings = AppSettings.defaults()
        .copyWith(enableLlmSessionLogs: false)
        .toJson();
    SharedPreferences.setMockInitialValues(<String, Object>{
      settingsKey: jsonEncode(legacySettings),
    });

    final prefs = await SharedPreferences.getInstance();
    final loaded = SettingsRepository(prefs).loadReadOnly();

    expect(loaded.enableLlmSessionLogs, isTrue);
    await Future<void>.delayed(Duration.zero);
    final persistedJson =
        jsonDecode(prefs.getString(settingsKey)!) as Map<String, dynamic>;
    expect(persistedJson['enableLlmSessionLogs'], isFalse);
    expect(prefs.getBool(llmSessionLogsDefaultOnMigrationKey), isNull);
  });

  test('marks the migration complete when saving settings', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final prefs = await SharedPreferences.getInstance();
    await SettingsRepository(
      prefs,
    ).save(AppSettings.defaults().copyWith(enableLlmSessionLogs: false));

    expect(prefs.getBool(llmSessionLogsDefaultOnMigrationKey), isTrue);
    expect(SettingsRepository(prefs).load().enableLlmSessionLogs, isFalse);
  });
}
