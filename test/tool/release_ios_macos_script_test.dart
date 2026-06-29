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

  test(
    'treats the post-upload flutter crash as success for a direct upload',
    () async {
      final fixture = _ReleaseScriptFixture.create();
      fixture.writeFvmWithPostUploadCrash();

      final result = await fixture.runReleaseScript(
        arguments: [
          '--only',
          'ios',
          '--no-pub-get',
          '--ios-export-root',
          '${fixture.root.path}/ios-export',
        ],
      );

      // The upload completed; the trailing build/ios/ipa crash must not be
      // reported as a release failure.
      expect(result.exitCode, 0);
      expect(result.stdout, contains('iOS: succeeded'));
      expect(result.stdout, contains('overall: succeeded'));
      expect(
        result.stderr,
        contains('Ignoring known post-upload tooling crash'),
      );
    },
  );

  test(
    'still fails a direct upload when a real export error is emitted',
    () async {
      // The benign-crash override must not mask a genuine upload failure: the
      // failure marker is checked first even on the default upload destination.
      final fixture = _ReleaseScriptFixture.create();
      fixture.writeFvmWithIosExportFailure();

      final result = await fixture.runReleaseScript(
        arguments: [
          '--only',
          'ios',
          '--no-pub-get',
          '--ios-export-root',
          '${fixture.root.path}/ios-export',
        ],
      );

      expect(result.exitCode, 1);
      expect(result.stdout, contains('overall: partial_failure'));
      expect(result.stderr, contains('Detected ios release failure marker'));
    },
  );

  test(
    'blocks macOS release notes with a mismatched filename version',
    () async {
      final fixture = _ReleaseScriptFixture.create();

      final result = await fixture.runReleaseScript(
        arguments: [
          '--only',
          'macos',
          '--dry-run',
          '--no-pub-get',
          '--build-name',
          '1.2.3',
          '--build-number',
          '4',
          '--macos-release-notes',
          '${fixture.root.path}/docs/releases/caverno-9.8.7.md',
        ],
      );

      expect(result.exitCode, 66);
      expect(result.stderr, contains('macOS release notes version mismatch'));
      expect(result.stderr, contains('is for 9.8.7'));
      expect(result.stderr, contains('release build name is 1.2.3'));
    },
  );

  test('allows an intentional macOS release notes version mismatch', () async {
    final fixture = _ReleaseScriptFixture.create();

    final result = await fixture.runReleaseScript(
      arguments: [
        '--only',
        'macos',
        '--dry-run',
        '--no-pub-get',
        '--build-name',
        '1.2.3',
        '--build-number',
        '4',
        '--macos-release-notes',
        '${fixture.root.path}/docs/releases/caverno-9.8.7.md',
      ],
      environment: const {
        'CAVERNO_ALLOW_RELEASE_NOTES_VERSION_MISMATCH': 'yes',
      },
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('Version: 1.2.3+4'));
    expect(
      result.stdout,
      contains('${fixture.root.path}/docs/releases/caverno-9.8.7.md'),
    );
  });
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

  void writeFvmWithPostUploadCrash() {
    // Mirrors `flutter build ipa` with ExportOptions destination=upload: it
    // uploads to App Store Connect, then crashes measuring the build/ios/ipa
    // directory it never wrote, exiting non-zero after a successful upload.
    _writeExecutable('fvm', '''
#!/usr/bin/env bash
echo "Building App Store IPA..."
echo "Oops; flutter has exited unexpectedly: \\"PathNotFoundException: Directory listing failed, path = '/tmp/proj/build/ios/ipa/' (OS Error: No such file or directory, errno = 2)\\"."
exit 1
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

  Future<ProcessResult> runReleaseScript({
    required List<String> arguments,
    Map<String, String> environment = const {},
  }) {
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
      environment: {'PATH': '${bin.path}:$path', ...environment},
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
