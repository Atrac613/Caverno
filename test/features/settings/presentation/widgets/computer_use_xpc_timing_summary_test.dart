import 'package:caverno/features/settings/presentation/widgets/computer_use_xpc_timing_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds required rows with existing missing-value fallbacks', () {
    final viewModel = ComputerUseXpcTimingSummaryViewModel.fromSummary({});

    expect(viewModel.heading, 'XPC timing: unknown');
    expect(_renderedRows(viewModel), [
      'Timing status: unknown',
      'Timing gate: review',
    ]);
  });

  test('normalizes every optional timing row in the existing order', () {
    final viewModel = ComputerUseXpcTimingSummaryViewModel.fromSummary({
      'ready': true,
      'classification': 'late_response_within_current_budget',
      'status': 'fallback_succeeded',
      'elapsedMs': 2001,
      'timeoutMs': 2000,
      'currentPreferredFallbackTimeoutMs': 3000,
      'currentTimeoutHeadroomMs': 950,
      'responseReceivedBeforeTimeout': false,
      'responseReceivedAfterTimeout': true,
      'lateResponseElapsedMs': 2050,
      'warmupStatus': 'xpc_response',
      'warmupElapsedMs': 43,
      'warmupResponseReceivedBeforeTimeout': true,
      'preferredFallbackSucceeded': true,
      'recommendedActionId': 'rerun_with_current_xpc_timeout',
      'userNextAction': 'Recheck permissions.',
      'engineeringNextAction': 'Keep the current timeout.',
      'nextAction': 'Rerun diagnostics.',
    });

    expect(
      viewModel.heading,
      'XPC timing: late_response_within_current_budget',
    );
    expect(_renderedRows(viewModel), [
      'Timing status: fallback_succeeded',
      'Timing gate: ready',
      'Elapsed: 2001ms',
      'Timeout budget: 2000ms',
      'Current XPC timeout: 3000ms',
      'Current headroom: 950ms',
      'Before timeout: no',
      'Late response: yes',
      'Late elapsed: 2050ms',
      'Warmup status: xpc_response',
      'Warmup elapsed: 43ms',
      'Warmup before timeout: yes',
      'Fallback: succeeded',
      'Timing action: rerun_with_current_xpc_timeout',
      'User next action: Recheck permissions.',
      'Engineering next action: Keep the current timeout.',
      'Timing next action: Rerun diagnostics.',
    ]);
  });

  test('keeps false boolean rows visible with their negative labels', () {
    final viewModel = ComputerUseXpcTimingSummaryViewModel.fromSummary({
      'responseReceivedBeforeTimeout': false,
      'responseReceivedAfterTimeout': false,
      'warmupResponseReceivedBeforeTimeout': false,
      'preferredFallbackSucceeded': false,
    });

    expect(_renderedRows(viewModel), [
      'Timing status: unknown',
      'Timing gate: review',
      'Before timeout: no',
      'Late response: no',
      'Warmup before timeout: no',
      'Fallback: not used',
    ]);
  });

  test('ignores malformed optional scalars and empty strings', () {
    final viewModel = ComputerUseXpcTimingSummaryViewModel.fromSummary({
      'ready': 'true',
      'classification': 7,
      'status': '',
      'elapsedMs': 1.5,
      'timeoutMs': '2000',
      'currentPreferredFallbackTimeoutMs': true,
      'currentTimeoutHeadroomMs': <int>[],
      'responseReceivedBeforeTimeout': 'no',
      'responseReceivedAfterTimeout': 0,
      'lateResponseElapsedMs': 2050.0,
      'warmupStatus': '',
      'warmupElapsedMs': 43.0,
      'warmupResponseReceivedBeforeTimeout': 'yes',
      'preferredFallbackSucceeded': 1,
      'recommendedActionId': '',
      'userNextAction': false,
      'engineeringNextAction': <String, dynamic>{},
      'nextAction': '',
    });

    expect(viewModel.heading, 'XPC timing: unknown');
    expect(_renderedRows(viewModel), [
      'Timing status: unknown',
      'Timing gate: review',
    ]);
  });

  test('copies source values into an unmodifiable presentation list', () {
    final source = <String, dynamic>{
      'ready': false,
      'classification': 'timeout',
      'status': 'blocked',
      'elapsedMs': 2000,
      'nextAction': 'Restart the helper.',
    };
    final viewModel = ComputerUseXpcTimingSummaryViewModel.fromSummary(source);

    source
      ..['ready'] = true
      ..['classification'] = 'ready'
      ..['status'] = 'ready'
      ..['elapsedMs'] = 1
      ..['nextAction'] = 'Changed.';

    expect(viewModel.heading, 'XPC timing: timeout');
    expect(_renderedRows(viewModel), [
      'Timing status: blocked',
      'Timing gate: review',
      'Elapsed: 2000ms',
      'Timing next action: Restart the helper.',
    ]);
    expect(
      () => viewModel.rows.add(
        const ComputerUseXpcTimingInfoRow(label: 'Extra', value: 'value'),
      ),
      throwsUnsupportedError,
    );
  });

  testWidgets('renders immutable information rows with Material icons', (
    tester,
  ) async {
    final viewModel = ComputerUseXpcTimingSummaryViewModel(
      heading: 'XPC timing: timeout',
      rows: const [
        ComputerUseXpcTimingInfoRow(label: 'Timing status', value: 'blocked'),
        ComputerUseXpcTimingInfoRow(label: 'Timing gate', value: 'review'),
      ],
    );

    await _pumpSummary(tester, viewModel);

    expect(find.text('XPC timing: timeout'), findsOneWidget);
    expect(find.text('Timing status: blocked'), findsOneWidget);
    expect(find.text('Timing gate: review'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Timing status: blocked')).dx,
      lessThan(tester.getTopLeft(find.text('Timing gate: review')).dx),
    );
  });
}

List<String> _renderedRows(ComputerUseXpcTimingSummaryViewModel viewModel) {
  return viewModel.rows
      .map((row) => '${row.label}: ${row.value}')
      .toList(growable: false);
}

Future<void> _pumpSummary(
  WidgetTester tester,
  ComputerUseXpcTimingSummaryViewModel viewModel,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ComputerUseXpcTimingSummary(viewModel: viewModel)),
    ),
  );
}
