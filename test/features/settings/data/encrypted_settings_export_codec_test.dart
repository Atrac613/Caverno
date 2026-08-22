import 'dart:convert';

import 'package:caverno/features/settings/data/encrypted_settings_export_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final codec = EncryptedSettingsExportCodec();
  const passphrase = 'correct horse battery staple';
  const plaintext = '''{"apiKey":"primary-secret","model":"test-model"}''';

  test('round-trips settings through authenticated encryption', () {
    final encrypted = codec.encrypt(
      plaintext: plaintext,
      passphrase: passphrase,
    );

    expect(encrypted, isNot(contains('primary-secret')));
    expect(
      codec.decrypt(envelope: encrypted, passphrase: passphrase),
      plaintext,
    );
  });

  test('uses independent salt and nonce values for each export', () {
    final first = codec.encrypt(plaintext: plaintext, passphrase: passphrase);
    final second = codec.encrypt(plaintext: plaintext, passphrase: passphrase);

    expect(first, isNot(second));
    final firstJson = jsonDecode(first) as Map<String, dynamic>;
    final secondJson = jsonDecode(second) as Map<String, dynamic>;
    expect(firstJson['kdf']['salt'], isNot(secondJson['kdf']['salt']));
    expect(firstJson['cipher']['nonce'], isNot(secondJson['cipher']['nonce']));
  });

  test('rejects the wrong passphrase without returning plaintext', () {
    final encrypted = codec.encrypt(
      plaintext: plaintext,
      passphrase: passphrase,
    );

    expect(
      () => codec.decrypt(
        envelope: encrypted,
        passphrase: 'incorrect passphrase value',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Invalid encrypted settings export',
        ),
      ),
    );
  });

  test('rejects ciphertext tampering', () {
    final encrypted = codec.encrypt(
      plaintext: plaintext,
      passphrase: passphrase,
    );
    final json = jsonDecode(encrypted) as Map<String, dynamic>;
    final cipher = Map<String, dynamic>.from(json['cipher'] as Map);
    final ciphertext = cipher['ciphertext'] as String;
    cipher['ciphertext'] =
        '${ciphertext.substring(0, ciphertext.length - 2)}AA';
    json['cipher'] = cipher;

    expect(
      () => codec.decrypt(envelope: jsonEncode(json), passphrase: passphrase),
      throwsFormatException,
    );
  });

  test('rejects unsupported or unreasonably expensive envelopes', () {
    final encrypted = codec.encrypt(
      plaintext: plaintext,
      passphrase: passphrase,
    );
    final unsupported = jsonDecode(encrypted) as Map<String, dynamic>;
    unsupported['version'] = 2;
    expect(
      () => codec.decrypt(
        envelope: jsonEncode(unsupported),
        passphrase: passphrase,
      ),
      throwsFormatException,
    );

    final expensive = jsonDecode(encrypted) as Map<String, dynamic>;
    final kdf = Map<String, dynamic>.from(expensive['kdf'] as Map);
    kdf['iterations'] = EncryptedSettingsExportCodec.maximumIterationCount + 1;
    expensive['kdf'] = kdf;
    expect(
      () => codec.decrypt(
        envelope: jsonEncode(expensive),
        passphrase: passphrase,
      ),
      throwsFormatException,
    );

    final weak = jsonDecode(encrypted) as Map<String, dynamic>;
    final weakKdf = Map<String, dynamic>.from(weak['kdf'] as Map);
    weakKdf['iterations'] =
        EncryptedSettingsExportCodec.minimumIterationCount - 1;
    weak['kdf'] = weakKdf;
    expect(
      () => codec.decrypt(envelope: jsonEncode(weak), passphrase: passphrase),
      throwsFormatException,
    );

    final malformed = jsonDecode(encrypted) as Map<String, dynamic>;
    final malformedCipher = Map<String, dynamic>.from(
      malformed['cipher'] as Map,
    );
    malformedCipher['ciphertext'] = 'not valid base64';
    malformed['cipher'] = malformedCipher;
    expect(
      () => codec.decrypt(
        envelope: jsonEncode(malformed),
        passphrase: passphrase,
      ),
      throwsFormatException,
    );
  });

  test('rejects an oversized envelope before key derivation', () {
    expect(
      () => codec.decrypt(
        envelope: 'x' * (EncryptedSettingsExportCodec.maximumEnvelopeBytes + 1),
        passphrase: passphrase,
      ),
      throwsFormatException,
    );
  });

  test('requires a bounded nontrivial passphrase', () {
    expect(
      () => codec.encrypt(plaintext: plaintext, passphrase: 'too-short'),
      throwsFormatException,
    );
    expect(
      () => codec.encrypt(
        plaintext: plaintext,
        passphrase:
            'x' * (EncryptedSettingsExportCodec.maximumPassphraseBytes + 1),
      ),
      throwsFormatException,
    );
  });
}
