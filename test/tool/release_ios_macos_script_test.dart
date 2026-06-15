import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses Caverno App Store provisioning profile by default', () async {
    final fixture = _ReleaseScriptFixture.create();
    fixture.writeFvmEchoExportOptions();

    final result = await fixture.runReleaseScript(
      arguments: [
        '--only',
        'ios',
        '--no-pub-get',
        '--ios-export-root',
        '${fixture.root.path}/ios-export',
      ],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains('Provisioning profile: Caverno AppStore Provisioning Profile'),
    );
    expect(
      result.stdout,
      contains('<string>Caverno AppStore Provisioning Profile</string>'),
    );
  });

  test(
    'reports partial failure when iOS export emits failure marker with zero exit',
    () async {
      final fixture = _ReleaseScriptFixture.create();
      fixture.writeFvmWithIosExportFailure();

      final result = await fixture.runReleaseScript(
        arguments: [
          '--only',
          'ios',
          '--ios-signing-style',
          'automatic',
          '--no-pub-get',
          // Use a fixture-owned export root so Linux CI can exercise the
          // failure-marker path without depending on macOS temp directories.
          '--ios-export-root',
          '${fixture.root.path}/ios-export',
        ],
      );

      expect(result.exitCode, 1);
      expect(
        result.stdout,
        contains('Encountered error while creating the IPA'),
      );
      expect(result.stdout, contains('iOS: failed'));
      expect(result.stdout, contains('macOS: skipped'));
      expect(result.stdout, contains('overall: partial_failure'));
      expect(result.stderr, contains('Detected ios release failure marker'));
      expect(fixture.logDirectory.listSync(), isNotEmpty);
    },
  );
}

final class _ReleaseScriptFixture {
  _ReleaseScriptFixture._(this.root, this.bin, this.logDirectory);

  final Directory root;
  final Directory bin;
  final Directory logDirectory;

  static _ReleaseScriptFixture create() {
    final root = Directory.systemTemp.createTempSync('release_ios_macos_');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final bin = Directory('${root.path}/bin')..createSync();
    final logDirectory = Directory('${root.path}/logs')..createSync();
    return _ReleaseScriptFixture._(root, bin, logDirectory);
  }

  void writeFvmWithIosExportFailure() {
    _writeExecutable('fvm', '''
#!/usr/bin/env bash
echo "Encountered error while creating the IPA:"
echo "error: exportArchive The provided entity includes an attribute with a value that has already been used."
echo "The bundle version must be higher than the previously uploaded version: '17'."
exit 0
''');
  }

  void writeFvmEchoExportOptions() {
    _writeExecutable('fvm', r'''
#!/usr/bin/env bash
for ((i = 1; i <= $#; i++)); do
  if [[ "${!i}" == "--export-options-plist" ]]; then
    next=$((i + 1))
    cat "${!next}"
    exit 0
  fi
done
exit 0
''');
  }

  Future<ProcessResult> runReleaseScript({required List<String> arguments}) {
    final path = Platform.environment['PATH'] ?? '';
    return Process.run(
      'bash',
      [
        'tool/release_ios_macos.sh',
        ...arguments,
        '--release-log-dir',
        logDirectory.path,
      ],
      workingDirectory: Directory.current.path,
      environment: {'PATH': '${bin.path}:$path'},
    );
  }

  void _writeExecutable(String name, String content) {
    final file = File('${bin.path}/$name')..writeAsStringSync(content);
    final chmod = Process.runSync('chmod', ['+x', file.path]);
    if (chmod.exitCode != 0) {
      throw StateError('Failed to chmod ${file.path}: ${chmod.stderr}');
    }
  }
}
