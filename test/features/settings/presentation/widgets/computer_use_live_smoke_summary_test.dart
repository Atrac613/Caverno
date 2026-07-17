import 'package:caverno/features/settings/presentation/widgets/computer_use_live_smoke_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the envelope as the report when no nested report exists', () {
    final viewModel = ComputerUseLiveSmokeSummaryViewModel.fromEnvelope({
      'ok': true,
      'coreOk': true,
      'captureOk': false,
      'generatedAt': '2026-07-17T12:00:00Z',
      'reportPath': '/tmp/report.json',
    });

    expect(
      viewModel.heading,
      'Last live smoke: passed at 2026-07-17T12:00:00Z',
    );
    expect(_renderedStatuses(viewModel), [
      'Live Core: Passed',
      'Live Capture: Needs attention',
    ]);
    expect(viewModel.details, ['Live smoke report: /tmp/report.json']);
  });

  test('uses nested report fields and prefers the outer path', () {
    final viewModel = ComputerUseLiveSmokeSummaryViewModel.fromEnvelope({
      'ok': true,
      'coreOk': true,
      'captureOk': true,
      'path': '/tmp/outer.json',
      'report': {
        'ok': false,
        'coreOk': false,
        'captureOk': false,
        'reportPath': '/tmp/inner.json',
      },
    });

    expect(viewModel.heading, 'Last live smoke: needs attention');
    expect(_renderedStatuses(viewModel), [
      'Live Core: Needs attention',
      'Live Capture: Needs attention',
    ]);
    expect(viewModel.details, ['Live smoke report: /tmp/outer.json']);
  });

  test('normalizes all status and detail rows in the existing order', () {
    final viewModel = ComputerUseLiveSmokeSummaryViewModel.fromEnvelope(
      _richEnvelope(),
    );

    expect(_renderedStatuses(viewModel), [
      'Live Core: Passed',
      'Live Capture: Needs attention',
      'Live Signing: Blocked',
      'Live XPC Runtime: Blocked',
      'Live Permissions: Blocked',
      'Live Capture Gate: blocked',
      'Live Input Gate: not_armed',
      'Live Audio Gate: Unsupported',
      'Live Unsafe Gate: Not armed',
      'Live Positive Smoke: blocked',
      'Live Expectations: Failed',
      'Live M4 Sign-off: blocked',
    ]);
    expect(viewModel.statusRows[7].isPositive, isTrue);
    expect(viewModel.details, [
      'signing: signature | runtime: listener | permissions: screen_capture | capture: capture_failed | input: input_not_armed | audio: audio_unavailable | unsafe: unsafe_not_armed | positive smoke: capture | m4: permissions, capture | expectations: capture_ready',
      'Live M4 helper: .../Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'Live M4 next action: Resolve M4 blockers.',
      'Live capture failure: timeout, permission',
      'Live capture next action: Retry capture.',
      'Live smoke report: /tmp/live-smoke.json',
    ]);
  });

  test('ignores wrong nested types but preserves empty-map presentation', () {
    final ignored = ComputerUseLiveSmokeSummaryViewModel.fromEnvelope({
      'signingDiagnostics': 'not a map',
      'xpcRuntimeDiagnostics': 7,
      'permissionGate': false,
      'captureGate': 'not a map',
      'inputGate': 'not a map',
      'audioGate': 'not a map',
      'unsafeActionGate': 'not a map',
      'positiveSmokeGateSummary': 'not a map',
      'readinessExpectations': 'not a map',
      'm4SignoffGate': 'not a map',
      'path': 42,
    });
    expect(ignored.statusRows, hasLength(2));
    expect(ignored.details, isEmpty);

    final emptyMaps = ComputerUseLiveSmokeSummaryViewModel.fromEnvelope({
      'signingDiagnostics': <String, dynamic>{},
      'xpcRuntimeDiagnostics': <String, dynamic>{},
      'permissionGate': <String, dynamic>{},
      'captureGate': <String, dynamic>{
        'failureClass': 'none',
        'nextAction': '',
      },
      'inputGate': <String, dynamic>{},
      'audioGate': <String, dynamic>{},
      'unsafeActionGate': <String, dynamic>{},
      'positiveSmokeGateSummary': <String, dynamic>{},
      'readinessExpectations': <String, dynamic>{},
      'm4SignoffGate': <String, dynamic>{
        'helperPath': {'embeddedHelperPath': '/short/helper.app'},
      },
      'reportPath': '',
    });

    expect(_renderedStatuses(emptyMaps), [
      'Live Core: Needs attention',
      'Live Capture: Needs attention',
      'Live Signing: Accepted',
      'Live XPC Runtime: Ready',
      'Live Permissions: Clear',
      'Live Capture Gate: Ready',
      'Live Input Gate: Ready',
      'Live Audio Gate: Ready',
      'Live Unsafe Gate: Not armed',
      'Live Positive Smoke: null',
      'Live Expectations: Failed',
      'Live M4 Sign-off: null',
    ]);
    expect(emptyMaps.details, ['Live M4 helper: /short/helper.app']);
  });

  test('copies envelope values into unmodifiable presentation lists', () {
    final captureBlockers = <dynamic>['capture_failed'];
    final captureGate = <String, dynamic>{
      'status': 'blocked',
      'blockers': captureBlockers,
      'nextAction': 'Retry capture.',
    };
    final report = <String, dynamic>{'ok': false, 'captureGate': captureGate};
    final envelope = <String, dynamic>{
      'path': '/tmp/original.json',
      'report': report,
    };
    final viewModel = ComputerUseLiveSmokeSummaryViewModel.fromEnvelope(
      envelope,
    );

    captureBlockers.clear();
    captureGate['status'] = 'ready';
    captureGate['nextAction'] = 'Changed.';
    report['ok'] = true;
    envelope['path'] = '/tmp/changed.json';

    expect(viewModel.heading, 'Last live smoke: needs attention');
    expect(viewModel.statusRows.last.statusText, 'blocked');
    expect(viewModel.details, [
      'capture: capture_failed',
      'Live capture next action: Retry capture.',
      'Live smoke report: /tmp/original.json',
    ]);
    expect(
      () => viewModel.statusRows.add(
        const ComputerUseLiveSmokeStatusRow(
          label: 'Extra',
          isPositive: true,
          positiveText: 'Ready',
          negativeText: 'Blocked',
        ),
      ),
      throwsUnsupportedError,
    );
    expect(() => viewModel.details.add('Extra'), throwsUnsupportedError);
  });

  testWidgets('renders immutable status rows and ordered details', (
    tester,
  ) async {
    final viewModel = ComputerUseLiveSmokeSummaryViewModel(
      heading: 'Last live smoke: needs attention',
      statusRows: const [
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Core',
          isPositive: true,
          positiveText: 'Passed',
          negativeText: 'Needs attention',
        ),
        ComputerUseLiveSmokeStatusRow(
          label: 'Live Capture',
          isPositive: false,
          positiveText: 'Passed',
          negativeText: 'Needs attention',
        ),
      ],
      details: const ['First detail', 'Second detail'],
    );

    await _pumpSummary(tester, viewModel);

    expect(find.text('Last live smoke: needs attention'), findsOneWidget);
    expect(find.text('Live Core: Passed'), findsOneWidget);
    expect(find.text('Live Capture: Needs attention'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('First detail')).dy,
      lessThan(tester.getTopLeft(find.text('Second detail')).dy),
    );
  });
}

List<String> _renderedStatuses(ComputerUseLiveSmokeSummaryViewModel viewModel) {
  return viewModel.statusRows
      .map((row) => '${row.label}: ${row.statusText}')
      .toList(growable: false);
}

Map<String, dynamic> _richEnvelope() {
  return {
    'path': '/tmp/live-smoke.json',
    'report': {
      'ok': false,
      'coreOk': true,
      'captureOk': false,
      'generatedAt': '2026-07-17T12:00:00Z',
      'signingDiagnostics': {
        'launchConstraintBlockers': ['signature', ''],
      },
      'xpcRuntimeDiagnostics': {
        'blockers': ['listener'],
      },
      'permissionGate': {
        'blockedByPermissions': ['screen_capture'],
      },
      'captureGate': {
        'status': 'blocked',
        'blockers': ['capture_failed'],
        'failureClass': 'timeout',
        'failureClasses': ['timeout', 'permission'],
        'nextAction': 'Retry capture.',
      },
      'inputGate': {
        'status': 'not_armed',
        'blockers': ['input_not_armed'],
      },
      'audioGate': {
        'status': 'unsupported',
        'blockers': ['audio_unavailable'],
      },
      'unsafeActionGate': {
        'unsafeArmed': false,
        'blockers': ['unsafe_not_armed'],
      },
      'positiveSmokeGateSummary': {
        'status': 'blocked',
        'blockedBy': ['capture'],
      },
      'readinessExpectations': {
        'ok': false,
        'failed': ['capture_ready'],
      },
      'm4SignoffGate': {
        'status': 'blocked',
        'blockers': ['permissions', 'capture'],
        'helperPath': {
          'embeddedHelperPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
        },
        'nextAction': 'Resolve M4 blockers.',
      },
    },
  };
}

Future<void> _pumpSummary(
  WidgetTester tester,
  ComputerUseLiveSmokeSummaryViewModel viewModel,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ComputerUseLiveSmokeSummary(viewModel: viewModel),
        ),
      ),
    ),
  );
}
