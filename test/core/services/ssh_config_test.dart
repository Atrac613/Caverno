import 'dart:io';

import 'package:caverno/core/services/ssh_config.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('ssh-config-');
    Directory('${home.path}/.ssh').createSync();
  });
  tearDown(() => home.deleteSync(recursive: true));

  void writeConfig(String contents) =>
      File('${home.path}/.ssh/config').writeAsStringSync(contents);

  SshConfigHostSettings resolve(String host) =>
      SshConfigReader.resolve(host, homeDirectory: home.path);

  // The reported failure: `ssh 192.168.100.241` worked from the user's shell
  // only because of this block, and offering the generic ~/.ssh/id_ed25519
  // instead produced "All authentication methods failed".
  test('resolves the user and identity that make a host passwordless', () {
    writeConfig('''
Host 192.168.100.241
    HostName 192.168.100.241
    User atrac
    IdentityFile ~/.ssh/id_ed25519_vms241
    IdentitiesOnly yes
''');

    final settings = resolve('192.168.100.241');

    expect(settings.user, 'atrac');
    expect(settings.identityFiles, [
      '${home.path}/.ssh/id_ed25519_vms241',
    ]);
  });

  test('returns nothing for a host with no matching block', () {
    writeConfig('Host other.example\n  User someone\n');

    expect(resolve('192.168.100.241').isEmpty, isTrue);
  });

  test('returns nothing when there is no config at all', () {
    expect(resolve('192.168.100.241').isEmpty, isTrue);
  });

  test('reads port and keeps the first value obtained', () {
    writeConfig('''
Host target.example
  User first
  Port 2222
Host target.example
  User second
  Port 2200
''');

    final settings = resolve('target.example');

    expect(settings.user, 'first');
    expect(settings.port, 2222);
  });

  test('accumulates every matching IdentityFile in order', () {
    writeConfig('''
Host *.example
  IdentityFile ~/.ssh/wildcard_key
Host target.example
  IdentityFile ~/.ssh/exact_key
''');

    expect(resolve('target.example').identityFiles, [
      '${home.path}/.ssh/wildcard_key',
      '${home.path}/.ssh/exact_key',
    ]);
  });

  test('honors glob and negated host patterns', () {
    writeConfig('''
Host 10.0.0.* !10.0.0.9
  User globbed
''');

    expect(resolve('10.0.0.5').user, 'globbed');
    expect(resolve('10.0.0.9').user, isNull);
    expect(resolve('10.0.1.5').user, isNull);
  });

  test('accepts keyword=value, quotes, and comments', () {
    writeConfig('''
# leading comment
Host target.example
  User=quoted            # trailing comment
  IdentityFile "~/.ssh/key with space"
''');

    final settings = resolve('target.example');

    expect(settings.user, 'quoted');
    expect(settings.identityFiles, ['${home.path}/.ssh/key with space']);
  });

  test('follows Include, resolving relative paths against ~/.ssh', () {
    Directory('${home.path}/.ssh/conf.d').createSync();
    File('${home.path}/.ssh/conf.d/10-target').writeAsStringSync(
      'Host target.example\n  User included\n',
    );
    writeConfig('Include conf.d/*\n');

    expect(resolve('target.example').user, 'included');
  });

  test('stops rather than looping on a self-including config', () {
    writeConfig('Include config\nHost target.example\n  User survivor\n');

    expect(resolve('target.example').user, 'survivor');
  });

  // A Match block's conditions can depend on the resolved user, the original
  // host, or an external command. Applying a value ssh(1) would not apply is
  // worse than offering none, so the block is skipped.
  test('ignores Match blocks instead of guessing they apply', () {
    writeConfig('''
Match host target.example
  User matched
''');

    expect(resolve('target.example').user, isNull);
  });

  test('does not resolve HostName, which would redirect the destination', () {
    writeConfig('Host alias\n  HostName 10.9.9.9\n  User someone\n');

    // The user is offered; where to connect stays what the caller named.
    expect(resolve('alias').user, 'someone');
  });
}
