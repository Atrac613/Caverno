import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _settingsKey = 'app_settings';

  AppSettings load() {
    final json = _prefs.getString(_settingsKey);
    if (json == null) {
      return AppSettings.defaults();
    }
    try {
      return AppSettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> reset() async {
    await _prefs.remove(_settingsKey);
  }
}
