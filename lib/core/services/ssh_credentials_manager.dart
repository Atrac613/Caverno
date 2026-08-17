import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/chat/domain/entities/ssh_auth_credential.dart';

/// Per-host credential store for SSH connections.
///
/// One [SshAuthCredential] record is written to [FlutterSecureStorage] per
/// `host:port:username` triplet, keyed by a URL-safe base64 encoding of it.
/// Host / port / username stay ephemeral values the user types into the
/// connect dialog on demand.
///
/// Key credentials persist a path and optional passphrase, never the private
/// key itself, so the file on disk remains the source of truth. Records
/// written before key authentication existed hold a bare password string and
/// are decoded as such by [SshAuthCredential.decode].
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

  Future<void> saveCredential({
    required String host,
    required int port,
    required String username,
    required SshAuthCredential credential,
  }) {
    return _storage.write(
      key: _keyFor(host, port, username),
      value: credential.encode(),
    );
  }

  Future<SshAuthCredential?> loadCredential({
    required String host,
    required int port,
    required String username,
  }) async {
    final raw = await _storage.read(key: _keyFor(host, port, username));
    return SshAuthCredential.decode(raw);
  }

  Future<void> deleteCredential({
    required String host,
    required int port,
    required String username,
  }) {
    return _storage.delete(key: _keyFor(host, port, username));
  }

  Future<bool> hasCredential({
    required String host,
    required int port,
    required String username,
  }) async {
    final credential = await loadCredential(
      host: host,
      port: port,
      username: username,
    );
    return credential != null;
  }
}

final sshCredentialsManagerProvider = Provider<SshCredentialsManager>(
  (ref) => SshCredentialsManager(),
);
