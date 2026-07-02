import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _settingsKey = 'app_settings';
  static const _llmSessionLogsDefaultOnMigrationKey =
      'migration.enable_llm_session_logs_default_on.v1';

  AppSettings load() {
    final json = _prefs.getString(_settingsKey);
    if (json == null) {
      return AppSettings.defaults();
    }
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final settings = AppSettings.fromJson(decoded);
      if (_shouldEnableSessionLogsForDefaultOnMigration(decoded)) {
        final migrated = settings.copyWith(enableLlmSessionLogs: true);
        _persistMigratedSessionLogDefault(migrated);
        return migrated;
      }
      return settings;
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings settings) async {
    await _prefs.setBool(_llmSessionLogsDefaultOnMigrationKey, true);
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> reset() async {
    await _prefs.remove(_settingsKey);
  }

  bool _shouldEnableSessionLogsForDefaultOnMigration(
    Map<String, dynamic> settingsJson,
  ) {
    if (_prefs.getBool(_llmSessionLogsDefaultOnMigrationKey) == true) {
      return false;
    }
    return settingsJson['enableLlmSessionLogs'] == false;
  }

  void _persistMigratedSessionLogDefault(AppSettings settings) {
    unawaited(_prefs.setBool(_llmSessionLogsDefaultOnMigrationKey, true));
    unawaited(_prefs.setString(_settingsKey, jsonEncode(settings.toJson())));
  }
}
