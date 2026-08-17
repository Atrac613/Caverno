import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../../features/chat/domain/entities/ssh_auth_credential.dart';

export '../../features/chat/domain/entities/ssh_auth_credential.dart';

/// Private key material could not be turned into usable identities.
///
/// Carries a message meant for the tool result: the model retries on what the
/// failure says, so "not found" and "needs a passphrase" must not both arrive
/// as a generic connect error.
class SshIdentityException implements Exception {
  const SshIdentityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads private keys and opens authenticated clients for a credential.
///
/// Kept apart from `SshService` so session ownership does not also own file
/// IO and key parsing; the service only needs "credential in, client out".
class SshClientConnector {
  const SshClientConnector._();

  /// Identity file names ssh(1) tries by default, strongest first.
  static const List<String> defaultIdentityNames = [
    'id_ed25519',
    'id_ecdsa',
    'id_rsa',
  ];

  /// Absolute paths of the default identity files that exist for this user.
  ///
  /// Used to pre-fill the connect dialog so the common "this host already has
  /// my key" case needs no typing.
  ///
  /// [homeDirectory] exists so the search is testable; production callers omit
  /// it and get the current user's home.
  static List<String> discoverDefaultIdentities({String? homeDirectory}) {
    final home =
        homeDirectory ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return const [];
    final found = <String>[];
    for (final name in defaultIdentityNames) {
      final path = '$home${Platform.pathSeparator}.ssh'
          '${Platform.pathSeparator}$name';
      try {
        if (File(path).existsSync()) found.add(path);
      } catch (_) {
        // An unreadable home directory simply offers no default identity.
      }
    }
    return found;
  }

  /// Parses the key named by [credential] into identities for authentication.
  static List<SSHKeyPair> loadIdentities(SshPrivateKeyCredential credential) {
    final file = File(credential.keyPath);
    if (!file.existsSync()) {
      throw SshIdentityException(
        'Private key not found: ${credential.keyPath}',
      );
    }
    final String pem;
    try {
      pem = file.readAsStringSync();
    } catch (error) {
      throw SshIdentityException(
        'Cannot read private key ${credential.keyPath}: $error',
      );
    }
    final passphrase = credential.passphrase;
    final needsPassphrase = _isEncrypted(pem);
    if (needsPassphrase && (passphrase == null || passphrase.isEmpty)) {
      throw SshIdentityException(
        'Private key ${credential.keyPath} is passphrase-protected; supply '
        'its passphrase in the connect dialog',
      );
    }
    final List<SSHKeyPair> identities;
    try {
      identities = SSHKeyPair.fromPem(pem, passphrase);
    } catch (error) {
      throw SshIdentityException(
        needsPassphrase
            ? 'Cannot decrypt private key ${credential.keyPath}; the '
                  'passphrase may be wrong'
            : 'Cannot parse private key ${credential.keyPath}: $error',
      );
    }
    if (identities.isEmpty) {
      throw SshIdentityException(
        'Private key ${credential.keyPath} contains no usable key',
      );
    }
    return identities;
  }

  /// Opens a client authenticating with [credential].
  ///
  /// Identities are resolved before the socket so an unreadable or
  /// passphrase-protected key fails without touching the network.
  static Future<SSHClient> connect({
    required String host,
    required int port,
    required String username,
    required SshAuthCredential credential,
    required Duration timeout,
  }) async {
    final identities = switch (credential) {
      SshPrivateKeyCredential() => loadIdentities(credential),
      SshPasswordCredential() => null,
    };
    final socket = await SSHSocket.connect(host, port, timeout: timeout);
    return SSHClient(
      socket,
      username: username,
      identities: identities,
      onPasswordRequest: switch (credential) {
        SshPasswordCredential(:final password) => () => password,
        SshPrivateKeyCredential() => null,
      },
    );
  }

  static bool _isEncrypted(String pem) {
    try {
      return SSHKeyPair.isEncryptedPem(pem);
    } catch (_) {
      return false;
    }
  }
}
