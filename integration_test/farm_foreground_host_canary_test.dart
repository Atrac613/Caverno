import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/farm_foreground_cancellation_fixture.dart';
import '../tool/canaries/support/farm_unattended_maintenance_probe.dart';

Future<void> _waitFor(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Native lifecycle event did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native macOS resume cancels Farm before the next timer tick', (
    tester,
  ) async {
    expect(Platform.isMacOS, isTrue);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Farm lifecycle canary'))),
    );
    await tester.runAsync(() async {
      final evidence = <String, Object?>{'schemaVersion': 1, 'passed': false};
      final fixture = FarmForegroundCancellationFixture();
      await fixture.initialize();
      final lifecycle = AppLifecycleService();
      final events = <bool>[];
      lifecycle.addListener(() => events.add(lifecycle.isInBackground));
      final probe = FarmUnattendedMaintenanceProbe(
        fixture.runner,
        lifecycleService: lifecycle,
        minIdle: const Duration(milliseconds: 100),
      );
      try {
        await windowManager.ensureInitialized();
        await windowManager.show();
        await windowManager.focus();
        await _waitFor(() => !lifecycle.isInBackground);
        probe.scheduler.start(interval: const Duration(seconds: 5));
        await windowManager.hide();
        await _waitFor(() => lifecycle.isInBackground);
        await fixture.proposalStarted.future.timeout(
          const Duration(seconds: 15),
        );
        final sinceDispatch = Stopwatch()..start();
        await windowManager.show();
        await windowManager.focus();
        await _waitFor(() => !lifecycle.isInBackground);
        fixture.release();
        await probe.scheduler.drain();
        expect(sinceDispatch.elapsed, lessThan(const Duration(seconds: 4)));
        expect(fixture.enqueueCalls, 0);
        expect(fixture.startCalls, 0);
        expect(events, containsAllInOrder([true, false]));
        evidence.addAll({
          'passed': true,
          'nativeBackgroundTransitions': events,
          'timerIntervalMs': 5000,
          'resumeToDrainMs': sinceDispatch.elapsedMilliseconds,
          'enqueueCalls': fixture.enqueueCalls,
          'startCalls': fixture.startCalls,
          'reports': probe.reports,
        });
      } finally {
        fixture.release();
        await probe.scheduler.drain();
        probe.dispose();
        await windowManager.show();
        await windowManager.focus();
        final path = const String.fromEnvironment(
          'CAVERNO_FARM_HOST_REPORT_PATH',
        );
        if (path.isNotEmpty) {
          await File(path).writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(evidence)}\n',
          );
        }
      }
    });
  });
}
