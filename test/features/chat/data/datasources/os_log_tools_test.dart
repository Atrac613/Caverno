import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/os_log_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'returns structured system information for the current platform',
    () async {
      final raw = await OsLogTools.getSystemInfo(
        linuxOsReleaseContents: '''
NAME="Ubuntu"
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS"
ID=ubuntu
''',
        processRunner: (executable, arguments) async {
          if (Platform.isMacOS && executable == '/usr/bin/sw_vers') {
            return ProcessResult(10, 0, '''
ProductName: macOS
ProductVersion: 14.5
BuildVersion: 23F79
''', '');
          }
          if (arguments.join(' ') == '-r') {
            return ProcessResult(11, 0, '23.5.0\n', '');
          }
          if (arguments.join(' ') == '-m') {
            return ProcessResult(12, 0, 'arm64\n', '');
          }
          return ProcessResult(13, 0, '', '');
        },
        environment: const {'PROCESSOR_ARCHITECTURE': 'AMD64'},
      );

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['error'], isNot(true));
      expect(decoded['os_family'], isA<String>());
      expect(decoded['os_log_read_supported'], isA<bool>());

      if (Platform.isMacOS) {
        expect(decoded['name'], 'macOS');
        expect(decoded['version'], '14.5');
        expect(decoded['build'], '23F79');
        expect(decoded['architecture'], 'arm64');
      } else if (Platform.isLinux) {
        expect(decoded['name'], 'Ubuntu 24.04 LTS');
        expect(decoded['distribution_id'], 'ubuntu');
        expect(decoded['kernel_version'], '23.5.0');
        expect(decoded['architecture'], 'arm64');
      } else if (Platform.isWindows) {
        expect(decoded['name'], 'Windows');
        expect(decoded['architecture'], 'AMD64');
      }
    },
  );

  test('returns the newest matching OS log entries first', () async {
    final raw = await OsLogTools.read(
      scope: 'authentication',
      keywords: const ['auth'],
      maxEntries: 2,
      processRunner: (executable, arguments) async {
        expect(arguments, isNotEmpty);
        if (Platform.isMacOS) {
          expect(executable, '/usr/bin/log');
          expect(arguments, contains('--predicate'));
        } else if (Platform.isLinux) {
          expect(executable, 'journalctl');
          expect(arguments, containsAll(['-u', 'NetworkManager']));
        }

        return ProcessResult(42, 0, '''
2026-04-22 09:00:00 wifi info Initial association succeeded
2026-04-22 09:01:00 eapolclient error Authentication failed for user
2026-04-22 09:02:00 eapolclient notice Auth retry scheduled
''', '');
      },
    );

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['error'], isNot(true));
    expect(decoded['scope'], 'authentication');
    expect(decoded['matches_found'], 2);
    expect(decoded['entries_returned'], 2);

    final entries = decoded['entries'] as List<dynamic>;
    expect(entries, hasLength(2));
    expect(
      (entries.first as Map<String, dynamic>)['line'],
      contains('Auth retry scheduled'),
    );
    expect(
      (entries.last as Map<String, dynamic>)['line'],
      contains('Authentication failed'),
    );
    expect(
      (entries.first as Map<String, dynamic>)['matched_keywords'],
      contains('auth'),
    );
  });

  test('returns a structured error for an invalid scope', () async {
    final raw = await OsLogTools.read(
      scope: 'invalid-scope',
      processRunner: (executable, arguments) async =>
          ProcessResult(1, 0, '', ''),
    );

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['error'], isTrue);
    expect(decoded['message'], contains('scope must be one of'));
  });
}
