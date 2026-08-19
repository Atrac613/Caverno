import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ssh_host_key.dart';

/// Persists SSH host identities by host and port, independent of username.
abstract interface class SshKnownHostsStore {
  Future<SshKnownHostIdentity?> lookup({
    required String host,
    required int port,
  });

  Future<void> remember(SshKnownHostIdentity identity);

  Future<void> remove({required String host, required int port});
}

final class MemorySshKnownHostsStore implements SshKnownHostsStore {
  MemorySshKnownHostsStore([Map<String, SshKnownHostIdentity>? seed])
    : _records = {...?seed};

  final Map<String, SshKnownHostIdentity> _records;

  @override
  Future<SshKnownHostIdentity?> lookup({
    required String host,
    required int port,
  }) async {
    return _records[sshKnownHostRecordKey(host: host, port: port)];
  }

  @override
  Future<void> remember(SshKnownHostIdentity identity) async {
    _records[identity.recordKey] = identity;
  }

  @override
  Future<void> remove({required String host, required int port}) async {
    _records.remove(sshKnownHostRecordKey(host: host, port: port));
  }
}

/// Known-host records in [FlutterSecureStorage], keyed separately from
/// credentials so a password rotation cannot rewrite the host identity.
final class SecureSshKnownHostsStore implements SshKnownHostsStore {
  SecureSshKnownHostsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'caverno.ssh.known_host.';

  String _storageKey(String host, int port) {
    final encoded = base64Url.encode(
      utf8.encode(sshKnownHostRecordKey(host: host, port: port)),
    );
    return '$_keyPrefix$encoded';
  }

  @override
  Future<SshKnownHostIdentity?> lookup({
    required String host,
    required int port,
  }) async {
    final raw = await _storage.read(
      key: _storageKey(host, port),
    );
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SshKnownHostIdentity.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remember(SshKnownHostIdentity identity) {
    return _storage.write(
      key: _storageKey(identity.host, identity.port),
      value: jsonEncode(identity.toJson()),
    );
  }

  @override
  Future<void> remove({required String host, required int port}) {
    return _storage.delete(key: _storageKey(host, port));
  }
}
