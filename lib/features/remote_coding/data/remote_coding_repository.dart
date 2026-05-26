import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/presentation/providers/settings_notifier.dart';
import '../domain/remote_coding_models.dart';

final remoteCodingRepositoryProvider = Provider<RemoteCodingRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return RemoteCodingRepository(prefs);
});

class RemoteCodingRepository {
  RemoteCodingRepository(this._prefs, {FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _serverSettingsKey = 'remote_coding_server_settings';
  static const _mobileHostKey = 'remote_coding_mobile_host';
  static const _mobileTokenPrefix = 'caverno.remote_coding.token.';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  RemoteCodingServerSettings loadServerSettings() {
    final raw = _prefs.getString(_serverSettingsKey);
    if (raw == null || raw.isEmpty) {
      return const RemoteCodingServerSettings();
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return RemoteCodingServerSettings.fromJson(decoded);
    } catch (_) {
      return const RemoteCodingServerSettings();
    }
  }

  Future<void> saveServerSettings(RemoteCodingServerSettings settings) {
    return _prefs.setString(_serverSettingsKey, jsonEncode(settings.toJson()));
  }

  RemoteCodingHost? loadMobileHost() {
    final raw = _prefs.getString(_mobileHostKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final host = RemoteCodingHost.fromJson(decoded);
      return host.host.isEmpty || host.id.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMobileHost(RemoteCodingHost host, String token) async {
    await _prefs.setString(_mobileHostKey, jsonEncode(host.toJson()));
    await _secureStorage.write(key: _tokenKey(host.id), value: token);
  }

  Future<String?> loadMobileHostToken(String hostId) {
    return _secureStorage.read(key: _tokenKey(hostId));
  }

  Future<void> clearMobileHost() async {
    final host = loadMobileHost();
    await _prefs.remove(_mobileHostKey);
    if (host != null) {
      await _secureStorage.delete(key: _tokenKey(host.id));
    }
  }

  String _tokenKey(String hostId) => '$_mobileTokenPrefix$hostId';
}
