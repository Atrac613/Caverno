import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS runner keeps GUI single-instance activation but admits CLI starts',
    () {
      final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

      expect(source, contains('applicationWillFinishLaunching'));
      expect(source, contains('isCommandLineInvocation(arguments: arguments)'));
      expect(source, contains('arguments.dropFirst().first'));
      for (final command in <String>[
        'chat',
        'coding',
        'plan',
        'conversations',
        'doctor',
        '--help',
        '-h',
        '--version',
      ]) {
        expect(source, contains('"$command"'));
      }
      expect(source, contains('!firstArgument.hasPrefix("-psn_")'));
      expect(source, contains('!firstArgument.hasPrefix("-")'));
      expect(source, contains('activateExistingInstanceIfNeeded'));
      expect(source, contains('runningApplications('));
      expect(source, contains('withBundleIdentifier: bundleIdentifier'));
      expect(
        source,
        contains('options: [.activateAllWindows, .activateIgnoringOtherApps]'),
      );
      expect(source, contains('Darwin.exit(0)'));
    },
  );

  test('Windows runner exits duplicate processes behind a named mutex', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(
      source,
      contains('Local\\\\com.noguwo.apps.caverno.single_instance'),
    );
    expect(source, contains('CreateMutexW(nullptr, TRUE'));
    expect(source, contains('ERROR_ALREADY_EXISTS'));
    expect(source, contains('ActivateExistingInstance();'));
    expect(source, contains('FindWindowW(kCavernoWindowClassName'));
    expect(source, contains('CloseHandle(single_instance_mutex)'));
  });

  test(
    'Linux runner uses a unique application id and presents the first window',
    () {
      final source = File('linux/runner/my_application.cc').readAsStringSync();

      expect(source, contains('GtkWindow* window;'));
      expect(source, contains('gtk_window_present(self->window)'));
      expect(source, contains('g_signal_connect(window, "destroy"'));
      expect(source, isNot(contains('G_APPLICATION_NON_UNIQUE')));
      expect(source, contains('"application-id", APPLICATION_ID'));
    },
  );
}
