import 'dart:convert';

/// How one SSH connection attempt proves its identity to the server.
enum SshAuthMethod { password, privateKey }

/// Immutable authentication material for one approved SSH target.
///
/// Password and key connections are separate variants rather than one record
/// with a nullable password. A key connection whose password happens to be
/// empty is not a password connection: collapsing the two is what let an
/// empty-password check reject every passwordless connection outright.
sealed class SshAuthCredential {
  const SshAuthCredential();

  SshAuthMethod get method;

  Map<String, dynamic> toJson();

  /// Names the method for error messages. Never includes secret material: a
  /// rejected connection has to say what it offered without saying the secret.
  @override
  String toString();

  /// Serializes to the single secure-storage record kept per target.
  String encode() => jsonEncode(toJson());

  /// Decodes [raw], treating a non-JSON payload as a legacy bare password.
  ///
  /// Records written before key authentication existed stored the password
  /// itself, so a decode failure means an old record rather than a corrupt
  /// one and must keep working.
  static SshAuthCredential? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return SshPasswordCredential(raw);
    }
    if (decoded is! Map<String, dynamic>) return SshPasswordCredential(raw);
    switch (decoded['method']) {
      case 'password':
        final password = decoded['password'];
        if (password is! String || password.isEmpty) return null;
        return SshPasswordCredential(password);
      case 'privateKey':
        final keyPath = decoded['keyPath'];
        if (keyPath is! String || keyPath.trim().isEmpty) return null;
        final passphrase = decoded['passphrase'];
        return SshPrivateKeyCredential(
          keyPath: keyPath.trim(),
          passphrase: passphrase is String && passphrase.isNotEmpty
              ? passphrase
              : null,
        );
      default:
        return null;
    }
  }
}

/// Keyboard-interactive / password authentication.
final class SshPasswordCredential extends SshAuthCredential {
  const SshPasswordCredential(this.password);

  final String password;

  @override
  SshAuthMethod get method => SshAuthMethod.password;

  @override
  Map<String, dynamic> toJson() => {'method': 'password', 'password': password};

  @override
  bool operator ==(Object other) =>
      other is SshPasswordCredential && other.password == password;

  @override
  String toString() => 'password auth';

  @override
  int get hashCode => Object.hash(method, password);
}

/// Public-key authentication against an on-disk private key.
///
/// The PEM is deliberately not captured here: it is read at connect time so
/// the file stays the single source of truth, and so remembering a key
/// persists a path plus an optional passphrase instead of the private key.
final class SshPrivateKeyCredential extends SshAuthCredential {
  const SshPrivateKeyCredential({required this.keyPath, this.passphrase});

  final String keyPath;
  final String? passphrase;

  @override
  SshAuthMethod get method => SshAuthMethod.privateKey;

  @override
  Map<String, dynamic> toJson() => {
    'method': 'privateKey',
    'keyPath': keyPath,
    if (passphrase != null && passphrase!.isNotEmpty) 'passphrase': passphrase,
  };

  @override
  bool operator ==(Object other) =>
      other is SshPrivateKeyCredential &&
      other.keyPath == keyPath &&
      other.passphrase == passphrase;

  @override
  String toString() => 'key $keyPath';

  @override
  int get hashCode => Object.hash(method, keyPath, passphrase);
}
