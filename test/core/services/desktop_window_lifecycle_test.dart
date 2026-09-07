import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop close hides or minimizes instead of terminating', () {
    final windowManagerSource = File(
      'lib/core/services/window_manager_service.dart',
    ).readAsStringSync();
    final appDelegateSource = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();

    expect(
      windowManagerSource,
      contains('windowManager.setPreventClose(true)'),
    );
    expect(windowManagerSource, contains('void onWindowClose()'));
    expect(windowManagerSource, contains('unawaited(_moveToBackground())'));
    expect(windowManagerSource, contains('windowManager.hide()'));
    expect(windowManagerSource, contains('windowManager.minimize()'));
    expect(
      appDelegateSource,
      contains('applicationShouldTerminateAfterLastWindowClosed'),
    );
    expect(appDelegateSource, contains('return false'));
  });

  test('desktop quit actions require Flutter confirmation', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final quitDialogSource = File(
      'lib/core/widgets/quit_confirmation_dialog.dart',
    ).readAsStringSync();
    final appMenuServiceSource = File(
      'lib/core/services/macos_app_menu_service.dart',
    ).readAsStringSync();
    final appDelegateSource = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final mainFlutterWindowSource = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final mainMenuXib = File(
      'macos/Runner/Base.lproj/MainMenu.xib',
    ).readAsStringSync();

    expect(
      mainSource,
      contains('SingleActivator(LogicalKeyboardKey.keyQ, control: true)'),
    );
    // The prompt itself lives in QuitConfirmationDialog; main.dart must still
    // route every quit through it before touching the window manager.
    expect(mainSource, contains('QuitConfirmationDialog.show('));
    expect(quitDialogSource, contains('Quit Caverno?'));
    expect(mainSource, contains('quitApplication()'));
    expect(appMenuServiceSource, contains("case 'quit':"));
    expect(appDelegateSource, contains('@IBAction func requestQuit'));
    expect(mainFlutterWindowSource, contains('func requestQuit()'));
    expect(mainMenuXib, contains('selector="requestQuit:"'));
    expect(mainMenuXib, isNot(contains('selector="terminate:"')));
  });

  test('Sparkle terminate closes drift before engine teardown', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final exitHandlerSource = File(
      'lib/core/services/caverno_app_exit_handler.dart',
    ).readAsStringSync();
    final appDelegateSource = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final mainFlutterWindowSource = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(mainSource, contains('didRequestAppExit'));
    expect(mainSource, contains('handleExitRequest'));
    expect(mainSource, contains('withMaintenancePausedForExit'));
    expect(mainSource, contains('AppExitResponse.cancel'));
    expect(mainSource, contains('CavernoAppExitHandler('));
    expect(exitHandlerSource, contains('sqlite3_finalize'));
    expect(exitHandlerSource, contains('NSApp.terminate'));
    expect(exitHandlerSource, contains('AppExitResponse.cancel'));
    expect(
      appDelegateSource,
      isNot(contains('func applicationShouldTerminate(_')),
    );
    expect(mainFlutterWindowSource, contains('SPUStandardUpdaterController'));
    expect(mainFlutterWindowSource, contains('updaterDelegate: nil'));
  });
}
