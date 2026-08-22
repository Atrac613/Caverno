import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final class EncryptedSettingsExportCodec {
  final Random _secureRandom = Random.secure();

  static const schema = 'caverno_encrypted_settings_export';
  static const version = 1;
  static const kdfAlgorithm = 'pbkdf2-hmac-sha256';
  static const cipherAlgorithm = 'aes-256-gcm';
  static const iterationCount = 600000;
  static const minimumIterationCount = 600000;
  static const maximumIterationCount = 2000000;
  static const minimumPassphraseCharacters = 12;
  static const maximumPassphraseBytes = 1024;
  static const maximumPlaintextBytes = 4 * 1024 * 1024;
  static const maximumEnvelopeBytes = 8 * 1024 * 1024;

  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _keyLength = 32;
  static const _authenticationTagBits = 128;

  String encrypt({required String plaintext, required String passphrase}) {
    final passwordBytes = _validatePassphrase(passphrase);
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    if (plaintextBytes.length > maximumPlaintextBytes) {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      plaintextBytes.fillRange(0, plaintextBytes.length, 0);
      throw const FormatException('Settings export is too large');
    }

    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = _deriveKey(
      passwordBytes: passwordBytes,
      salt: salt,
      iterations: iterationCount,
    );
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(
            KeyParameter(key),
            _authenticationTagBits,
            nonce,
            _associatedData(iterationCount),
          ),
        );
      final ciphertext = cipher.process(plaintextBytes);
      return jsonEncode(<String, dynamic>{
        'schema': schema,
        'version': version,
        'kdf': <String, dynamic>{
          'algorithm': kdfAlgorithm,
          'iterations': iterationCount,
          'salt': _encodeBytes(salt),
        },
        'cipher': <String, dynamic>{
          'algorithm': cipherAlgorithm,
          'nonce': _encodeBytes(nonce),
          'ciphertext': _encodeBytes(ciphertext),
        },
      });
    } finally {
      key.fillRange(0, key.length, 0);
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      plaintextBytes.fillRange(0, plaintextBytes.length, 0);
    }
  }

  String decrypt({required String envelope, required String passphrase}) {
    if (utf8.encode(envelope).length > maximumEnvelopeBytes) {
      throw const FormatException('Invalid encrypted settings export');
    }
    final passwordBytes = _validatePassphrase(passphrase);
    Uint8List? key;
    Uint8List? plaintextBytes;
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map<String, dynamic> ||
          decoded['schema'] != schema ||
          decoded['version'] != version) {
        throw const FormatException('Invalid encrypted settings export');
      }
      final kdf = decoded['kdf'];
      final cipherSettings = decoded['cipher'];
      if (kdf is! Map ||
          cipherSettings is! Map ||
          kdf['algorithm'] != kdfAlgorithm ||
          cipherSettings['algorithm'] != cipherAlgorithm) {
        throw const FormatException('Invalid encrypted settings export');
      }
      final iterations = kdf['iterations'];
      if (iterations is! int ||
          iterations < minimumIterationCount ||
          iterations > maximumIterationCount) {
        throw const FormatException('Invalid encrypted settings export');
      }
      final salt = _decodeBytes(kdf['salt']);
      final nonce = _decodeBytes(cipherSettings['nonce']);
      final ciphertext = _decodeBytes(cipherSettings['ciphertext']);
      if (salt.length != _saltLength ||
          nonce.length != _nonceLength ||
          ciphertext.length < _authenticationTagBits ~/ 8 ||
          ciphertext.length >
              maximumPlaintextBytes + (_authenticationTagBits ~/ 8)) {
        throw const FormatException('Invalid encrypted settings export');
      }

      key = _deriveKey(
        passwordBytes: passwordBytes,
        salt: salt,
        iterations: iterations,
      );
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            _authenticationTagBits,
            nonce,
            _associatedData(iterations),
          ),
        );
      plaintextBytes = cipher.process(ciphertext);
      return utf8.decode(plaintextBytes);
    } catch (_) {
      throw const FormatException('Invalid encrypted settings export');
    } finally {
      key?.fillRange(0, key.length, 0);
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      plaintextBytes?.fillRange(0, plaintextBytes.length, 0);
    }
  }

  Uint8List _validatePassphrase(String passphrase) {
    final bytes = Uint8List.fromList(utf8.encode(passphrase));
    if (passphrase.runes.length < minimumPassphraseCharacters ||
        bytes.length > maximumPassphraseBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const FormatException(
        'Passphrase must contain at least 12 characters and at most 1024 bytes',
      );
    }
    return bytes;
  }

  Uint8List _deriveKey({
    required Uint8List passwordBytes,
    required Uint8List salt,
    required int iterations,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyLength));
    return derivator.process(passwordBytes);
  }

  Uint8List _associatedData(int iterations) => Uint8List.fromList(
    utf8.encode(
      '$schema\n$version\n$kdfAlgorithm\n$iterations\n$cipherAlgorithm',
    ),
  );

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _secureRandom.nextInt(256)),
  );

  String _encodeBytes(Uint8List bytes) => base64UrlEncode(bytes);

  Uint8List _decodeBytes(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) {
      throw const FormatException('Invalid encrypted settings export');
    }
    return Uint8List.fromList(base64Url.decode(encoded));
  }
}
