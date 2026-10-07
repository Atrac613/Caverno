import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../tool/canaries/support/farm_unattended_maintenance_probe.dart';
import '../../../../support/farm_foreground_cancellation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final returnToBackground in [false, true]) {
    test(
      'foreground cancels pending Farm proposal without tick; background again=$returnToBackground',
      () async {
        final fixture = FarmForegroundCancellationFixture();
        await fixture.initialize();
        final probe = FarmUnattendedMaintenanceProbe(fixture.runner);
        addTearDown(() async {
          fixture.release();
          await probe.scheduler.drain();
          probe.dispose();
        });
        probe.lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
        await probe.scheduler.tick();
        await fixture.proposalStarted.future.timeout(
          const Duration(seconds: 5),
        );
        probe.lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
        if (returnToBackground) {
          probe.lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
        }
        fixture.release();
        await probe.scheduler.drain();
        expect(fixture.enqueueCalls, 0);
        expect(fixture.startCalls, 0);
        expect(
          probe.reports.single['body'],
          contains('cancelled before further dispatch; started 0, skipped 0'),
        );
      },
    );
  }
}
