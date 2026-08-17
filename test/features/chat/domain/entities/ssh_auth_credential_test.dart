import 'package:caverno/features/chat/domain/entities/ssh_auth_credential.dart';
import 'package:test/test.dart';

void main() {
  group('SshAuthCredential', () {
    test('round-trips a password credential', () {
      const credential = SshPasswordCredential('secret');

      expect(SshAuthCredential.decode(credential.encode()), credential);
    });

    test('round-trips a private key credential with a passphrase', () {
      const credential = SshPrivateKeyCredential(
        keyPath: '/home/deploy/.ssh/id_ed25519',
        passphrase: 'unlock',
      );

      expect(SshAuthCredential.decode(credential.encode()), credential);
    });

    test('omits an empty passphrase rather than storing it', () {
      const credential = SshPrivateKeyCredential(
        keyPath: '/home/deploy/.ssh/id_rsa',
        passphrase: '',
      );

      expect(credential.toJson().containsKey('passphrase'), isFalse);
      expect(
        SshAuthCredential.decode(credential.encode()),
        const SshPrivateKeyCredential(keyPath: '/home/deploy/.ssh/id_rsa'),
      );
    });

    // Records written before key authentication existed stored the password
    // itself; decoding must keep those hosts connecting.
    test('reads a legacy bare password record', () {
      expect(
        SshAuthCredential.decode('legacy-secret'),
        const SshPasswordCredential('legacy-secret'),
      );
    });

    test('reads a legacy password that happens to parse as JSON', () {
      expect(
        SshAuthCredential.decode('12345'),
        const SshPasswordCredential('12345'),
      );
    });

    // The connect failure message names what was offered; a rejected
    // connection has to say the method without saying the secret.
    test('describes itself without revealing secret material', () {
      expect(const SshPasswordCredential('hunter2').toString(), 'password auth');
      expect(
        const SshPrivateKeyCredential(
          keyPath: '/home/deploy/.ssh/id_ed25519',
          passphrase: 'unlock',
        ).toString(),
        'key /home/deploy/.ssh/id_ed25519',
      );
    });

    test('treats missing and empty records as no credential', () {
      expect(SshAuthCredential.decode(null), isNull);
      expect(SshAuthCredential.decode(''), isNull);
    });

    test('rejects a record whose method is unknown or incomplete', () {
      expect(SshAuthCredential.decode('{"method":"totp"}'), isNull);
      expect(SshAuthCredential.decode('{"method":"privateKey"}'), isNull);
      expect(
        SshAuthCredential.decode('{"method":"password","password":""}'),
        isNull,
      );
    });
  });
}
