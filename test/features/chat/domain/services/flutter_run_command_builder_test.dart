import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/flutter_run_command_builder.dart';

void main() {
  FlutterRunCommandBuilder builderWith({required bool fvm}) =>
      FlutterRunCommandBuilder(usesFvm: (_) => fvm);

  test('prefixes fvm when the project pins a Flutter version', () {
    final command = builderWith(
      fvm: true,
    ).run(projectRoot: '/work/app', deviceId: 'macos');

    expect(command.executable, 'fvm');
    expect(command.arguments, ['flutter', 'run', '-d', 'macos']);
    expect(command.workingDirectory, '/work/app');
    expect(command.displayCommand, 'fvm flutter run -d macos');
  });

  test('calls flutter directly without an fvm pin', () {
    final command = builderWith(
      fvm: false,
    ).run(projectRoot: '/work/app', deviceId: 'emulator-5554');

    expect(command.executable, 'flutter');
    expect(command.arguments, ['run', '-d', 'emulator-5554']);
  });

  test('device discovery follows the same toolchain choice', () {
    expect(
      builderWith(fvm: true).devices(projectRoot: '/work/app').displayCommand,
      'fvm flutter devices --machine',
    );
    expect(
      builderWith(fvm: false).devices(projectRoot: '/work/app').displayCommand,
      'flutter devices --machine',
    );
  });

  group('parseDevices', () {
    test('reads the machine output, banners and all', () {
      // The tool prints upgrade banners before the JSON on a first run; a
      // strict decode would report "no devices" on a machine that has them.
      const output = '''
Resolving dependencies...
A new version of Flutter is available!

[
  {"name":"macOS","id":"macos","isSupported":true,"targetPlatform":"darwin",
   "emulator":false,"sdk":"macOS 15.5"},
  {"name":"iPhone 16","id":"1234-ABCD","isSupported":true,
   "targetPlatform":"ios","emulator":true,"sdk":"iOS 18.0"}
]
''';

      final devices = FlutterRunCommandBuilder.parseDevices(output);

      expect(devices, hasLength(2));
      expect(devices.first.id, 'macos');
      expect(devices.first.displayName, 'macOS (darwin)');
      expect(devices.first.isEmulator, isFalse);
      expect(devices.last.id, '1234-ABCD');
      expect(devices.last.isEmulator, isTrue);
      expect(devices.last.sdk, 'iOS 18.0');
    });

    test('keeps unsupported devices so the picker can explain them', () {
      const output =
          '[{"name":"Web Server","id":"web-server","isSupported":false,'
          '"targetPlatform":"web-javascript"}]';

      final devices = FlutterRunCommandBuilder.parseDevices(output);

      expect(devices.single.isSupported, isFalse);
    });

    test('returns nothing for unusable output instead of throwing', () {
      for (final output in [
        '',
        'Waiting for another flutter command to release the startup lock...',
        '[not json',
        '{"id":"macos"}',
      ]) {
        expect(
          FlutterRunCommandBuilder.parseDevices(output),
          isEmpty,
          reason: output,
        );
      }
    });

    test('skips entries with no id', () {
      const output = '[{"name":"Nameless"},{"name":"macOS","id":"macos"}]';

      expect(FlutterRunCommandBuilder.parseDevices(output).map((d) => d.id), [
        'macos',
      ]);
    });
  });
}
