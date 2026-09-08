import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const helper = 'tool/macos_release_app_entitlements.py';
  const source = 'macos/Runner/Release.entitlements';

  Future<ProcessResult> runHelper(List<String> args) {
    return Process.run('python3', [helper, ...args]);
  }

  test('expands Release entitlements with team and bundle ids', () async {
    final out = File(
      '${Directory.systemTemp.createTempSync('caverno-entitlements-').path}/out.plist',
    );
    addTearDown(() => out.parent.deleteSync(recursive: true));

    final expanded = await runHelper([
      'expand',
      '--source',
      source,
      '--team-id',
      '89UG59TBNX',
      '--bundle-id',
      'com.noguwo.apps.caverno',
      '--output',
      out.path,
    ]);
    expect(expanded.exitCode, 0, reason: expanded.stderr.toString());

    final verified = await runHelper(['verify-file', '--path', out.path]);
    expect(verified.exitCode, 0, reason: verified.stderr.toString());
    expect(
      verified.stdout.toString(),
      contains('keychain-access-groups'),
    );

    final body = out.readAsStringSync();
    expect(body, contains('89UG59TBNX.com.noguwo.apps.caverno'));
    expect(body, isNot(contains(r'$(AppIdentifierPrefix)')));
    expect(body, isNot(contains('get-task-allow')));
  });

  test('refuses Debug-only get-task-allow in a Release entitlements source', () async {
    final root = Directory.systemTemp.createTempSync('caverno-entitlements-');
    addTearDown(() => root.deleteSync(recursive: true));
    final debugLike = File('${root.path}/Debug.entitlements')
      ..writeAsStringSync(
        File('macos/Runner/DebugProfile.entitlements').readAsStringSync(),
      );
    final out = File('${root.path}/out.plist');

    final result = await runHelper([
      'expand',
      '--source',
      debugLike.path,
      '--team-id',
      '89UG59TBNX',
      '--bundle-id',
      'com.noguwo.apps.caverno',
      '--output',
      out.path,
    ]);
    expect(result.exitCode, 65);
    expect(result.stderr.toString(), contains('get-task-allow'));
  });

  test('fails closed on an empty entitlements dump', () async {
    final root = Directory.systemTemp.createTempSync('caverno-entitlements-');
    addTearDown(() => root.deleteSync(recursive: true));
    final empty = File('${root.path}/empty.plist')..writeAsBytesSync(const []);

    final result = await runHelper(['verify-file', '--path', empty.path]);
    expect(result.exitCode, 65);
    expect(result.stderr.toString(), contains('empty'));
  });

  test('parses a codesign blob header before the XML plist', () async {
    final root = Directory.systemTemp.createTempSync('caverno-entitlements-');
    addTearDown(() => root.deleteSync(recursive: true));
    final expanded = File('${root.path}/expanded.plist');
    final expand = await runHelper([
      'expand',
      '--source',
      source,
      '--team-id',
      '89UG59TBNX',
      '--bundle-id',
      'com.noguwo.apps.caverno',
      '--output',
      expanded.path,
    ]);
    expect(expand.exitCode, 0, reason: expand.stderr.toString());

    final blob = File('${root.path}/blob.plist')
      ..writeAsBytesSync([
        0xfa,
        0xde,
        0x71,
        0x71,
        0x00,
        0x00,
        0x00,
        0x00,
        ...expanded.readAsBytesSync(),
      ]);
    final result = await runHelper(['verify-file', '--path', blob.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
}
