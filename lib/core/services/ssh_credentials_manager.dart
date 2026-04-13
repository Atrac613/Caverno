import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-host credential store for SSH connections.
///
/// Passwords are written to [FlutterSecureStorage] keyed by a URL-safe
/// base64 encoding of the `host:port:username` triplet. Only passwords are
/// stored here — host / port / username are ephemeral values the user
/// types into the connect dialog on demand.
class SshCredentialsManager {
  SshCredentialsManager({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'caverno.ssh.';

  String _keyFor(String host, int port, String username) {
    final raw = '$host:$port:$username';
    final encoded = base64Url.encode(utf8.encode(raw));
    return '$_keyPrefix$encoded';
  }

  Future<void> savePassword({
    required String host,
    required int port,
    required String username,
    required String password,
  }) {
    return _storage.write(
      key: _keyFor(host, port, username),
      value: password,
    );
  }

  Future<String?> loadPassword({
    required String host,
    required int port,
    required String username,
  }) {
    return _storage.read(key: _keyFor(host, port, username));
  }

  Future<void> deletePassword({
    required String host,
    required int port,
    required String username,
  }) {
    return _storage.delete(key: _keyFor(host, port, username));
  }

  Future<bool> hasPassword({
    required String host,
    required int port,
    required String username,
  }) async {
    final value = await loadPassword(
      host: host,
      port: port,
      username: username,
    );
    return value != null && value.isNotEmpty;
  }
}

final sshCredentialsManagerProvider = Provider<SshCredentialsManager>(
  (ref) => SshCredentialsManager(),
);
