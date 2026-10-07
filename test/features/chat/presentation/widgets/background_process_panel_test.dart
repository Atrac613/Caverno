import 'package:caverno/features/chat/data/datasources/background_process_monitor_snapshot.dart';
import 'package:caverno/features/chat/presentation/widgets/background_process_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BackgroundProcessMonitorSnapshot snapshot({
    required String status,
    int? exitCode,
    String stdoutTail = '',
    String stderrTail = '',
  }) {
    final startedAt = DateTime(2026, 9, 23, 15);
    return BackgroundProcessMonitorSnapshot(
      jobId: 'proc_1',
      status: status,
      command: 'flutter test',
      workingDirectory: '/tmp',
      label: 'Run tests',
      exitCode: exitCode,
      elapsedMs: 141000,
      startedAt: startedAt,
      lastCheckedAt: startedAt,
      stdoutTail: stdoutTail,
      stderrTail: stderrTail,
    );
  }

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  );

  test('elapsed time reads at a glance', () {
    expect(formatBackgroundProcessElapsed(null), '0s');
    expect(formatBackgroundProcessElapsed(45900), '45s');
    expect(formatBackgroundProcessElapsed(141000), '2m 21s');
    expect(formatBackgroundProcessElapsed(3780000), '1h 03m');
  });

  testWidgets('running job opens with its output and offers stop', (
    tester,
  ) async {
    var stopped = 0;
    await tester.pumpWidget(
      host(
        BackgroundProcessCard(
          job: snapshot(status: 'running', stdoutTail: 'compiling...\n'),
          onStop: () => stopped++,
        ),
      ),
    );

    expect(find.text('Run tests'), findsOneWidget);
    expect(find.textContaining('2m 21s'), findsOneWidget);
    expect(find.textContaining('compiling...', findRichText: true), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('background-process-stop-proc_1')),
    );
    expect(stopped, 1);
  });

  testWidgets('finished job starts collapsed and expands on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        BackgroundProcessCard(
          job: snapshot(status: 'exited', exitCode: 1, stderrTail: 'boom'),
        ),
      ),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      find.byKey(const ValueKey('background-process-stop-proc_1')),
      findsNothing,
    );
    expect(find.textContaining('boom', findRichText: true), findsNothing);

    await tester.tap(find.text('Run tests'));
    await tester.pump();

    expect(find.textContaining('boom', findRichText: true), findsOne);
  });
}
