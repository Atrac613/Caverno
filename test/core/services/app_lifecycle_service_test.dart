import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('marks paused as background on all platforms', (tester) async {
    final service = AppLifecycleService();
    addTearDown(service.dispose);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(service.isInBackground, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(service.isInBackground, isFalse);
  });

  testWidgets('marks inactive and hidden as background on macOS', (
    tester,
  ) async {
    final service = AppLifecycleService();
    addTearDown(service.dispose);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(service.isInBackground, Platform.isMacOS);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(service.isInBackground, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(service.isInBackground, Platform.isMacOS);
  });

  testWidgets('records backgroundSince when entering and clears on resume', (
    tester,
  ) async {
    var now = DateTime(2026, 6, 16, 3);
    final service = AppLifecycleService(clock: () => now);
    addTearDown(service.dispose);

    expect(service.backgroundSince, isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(service.backgroundSince, DateTime(2026, 6, 16, 3));

    // The timestamp marks the *entry* instant; staying backgrounded keeps it.
    now = DateTime(2026, 6, 16, 3, 30);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(service.backgroundSince, DateTime(2026, 6, 16, 3));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(service.backgroundSince, isNull);
  });
}
