import 'dart:io';

import 'package:caverno/core/services/ssh_client_connector.dart';
import 'package:test/test.dart';

/// An unencrypted ed25519 key, generated for this test only.
const _plainKey = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACDXJvBcMy0lLYhpJvJEJoZaLGBTOVMWBLDrOllCTshRQAAAAJgAAAAAAAAA
AAAAAAtzc2gtZWQyNTUxOQAAACDXJvBcMy0lLYhpJvJEJoZaLGBTOVMWBLDrOllCTshRQA
AAAEA0Y5rLdKVLE5vXCBnGVvBfHkDPmxHkxK5dVzSLj3sSXtcm8FwzLSUtiGkm8kQmhlos
YFM5UxYEsOs6WUJOyFFAAAAAEXRlc3RAY2F2ZXJuby5sb2NhbAECAwQ=
-----END OPENSSH PRIVATE KEY-----
''';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ssh-identity-'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, String contents) =>
      File('${dir.path}/$name')..writeAsStringSync(contents);

  group('SshClientConnector.loadIdentities', () {
    test('names the missing file instead of failing generically', () {
      expect(
        () => SshClientConnector.loadIdentities(
          SshPrivateKeyCredential(keyPath: '${dir.path}/absent'),
        ),
        throwsA(
          isA<SshIdentityException>().having(
            (e) => e.message,
            'message',
            contains('Private key not found'),
          ),
        ),
      );
    });

    test('reports an unparsable key as a parse failure', () {
      final file = write('garbage', 'not a key at all\n');

      expect(
        () => SshClientConnector.loadIdentities(
          SshPrivateKeyCredential(keyPath: file.path),
        ),
        throwsA(
          isA<SshIdentityException>().having(
            (e) => e.message,
            'message',
            contains('Cannot parse private key'),
          ),
        ),
      );
    });

    test('loads an unencrypted key with no passphrase supplied', () {
      final file = write('id_ed25519', _plainKey);

      final identities = SshClientConnector.loadIdentities(
        SshPrivateKeyCredential(keyPath: file.path),
      );

      expect(identities, isNotEmpty);
    });
  });

  group('SshClientConnector.discoverDefaultIdentities', () {
    test('returns only the identity files that exist, strongest first', () {
      final home = Directory('${dir.path}/home')..createSync();
      Directory('${home.path}/.ssh').createSync();
      File('${home.path}/.ssh/id_ed25519').writeAsStringSync(_plainKey);
      File('${home.path}/.ssh/id_rsa').writeAsStringSync(_plainKey);

      final found = SshClientConnector.discoverDefaultIdentities(
        homeDirectory: home.path,
      );

      expect(found, hasLength(2));
      expect(found.first, endsWith('id_ed25519'));
      expect(found.last, endsWith('id_rsa'));
    });

    test('returns nothing when the user has no default identity', () {
      final home = Directory('${dir.path}/empty-home')..createSync();

      expect(
        SshClientConnector.discoverDefaultIdentities(homeDirectory: home.path),
        isEmpty,
      );
    });
  });

  test('production connect always installs a host-key callback', () {
    final source = File('lib/core/services/ssh_client_connector.dart')
        .readAsStringSync();

    expect(source, contains('onVerifyHostKey: handshake.verify'));
    expect(source, contains('handshake.rethrowIfRejected(error)'));
    expect(source, isNot(contains('disableHostkeyVerification: true')));
  });
}
