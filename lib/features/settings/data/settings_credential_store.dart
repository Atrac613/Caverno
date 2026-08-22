import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SettingsCredentialStore {
  Future<Map<String, String>> readAll();

  Future<void> writeAll(Map<String, String> credentials);

  Future<void> clear();
}

final class FlutterSettingsCredentialStore implements SettingsCredentialStore {
  const FlutterSettingsCredentialStore({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  static const _storageKey = 'caverno.settings.credentials.v1';

  @override
  Future<Map<String, String>> readAll() async {
    final encoded = await storage.read(key: _storageKey);
    if (encoded == null || encoded.isEmpty) {
      return const <String, String>{};
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Invalid secure settings credential payload');
    }
    final credentials = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException(
          'Invalid secure settings credential payload',
        );
      }
      credentials[entry.key as String] = entry.value as String;
    }
    return credentials;
  }

  @override
  Future<void> writeAll(Map<String, String> credentials) {
    if (credentials.isEmpty) {
      return clear();
    }
    return storage.write(key: _storageKey, value: jsonEncode(credentials));
  }

  @override
  Future<void> clear() => storage.delete(key: _storageKey);
}
