import 'package:caverno/features/settings/presentation/widgets/computer_use_action_gate_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes all helper boundary states', () {
    final cases = <({bool installed, bool running, bool ipc, String status})>[
      (installed: false, running: false, ipc: false, status: 'needs launch'),
      (installed: true, running: false, ipc: false, status: 'needs launch'),
      (installed: true, running: true, ipc: false, status: 'needs IPC'),
      (installed: true, running: true, ipc: true, status: 'ready'),
    ];

    for (final testCase in cases) {
      final row = _viewModel(
        helperInstalled: testCase.installed,
        helperRunning: testCase.running,
        helperIpcReady: testCase.ipc,
      ).rows.first;

      expect(row.status, testCase.status);
      expect(row.isPositive, testCase.status == 'ready');
    }
  });

  test('copies gate values into immutable rows and applies fallbacks', () {
    final captureGate = <String, dynamic>{'status': 7, 'nextAction': ''};
    final viewModel = _viewModel(
      captureGate: captureGate,
      inputGate: const {'status': 'blocked'},
      audioGate: const {'status': null, 'nextAction': 7},
      overlaySmoke: const {'status': 'failed', 'nextAction': ''},
      unsafeActionGate: null,
      hasLiveSmokeReport: true,
    );

    expect(viewModel.rows[3].status, 'not run');
    expect(
      viewModel.rows.sublist(3).map((row) => row.detail),
      everyElement('Review the latest live smoke report.'),
    );

    captureGate['status'] = 'ready';
    captureGate['nextAction'] = 'Mutated after construction.';

    expect(viewModel.rows[3].status, 'not run');
    expect(viewModel.rows[3].detail, 'Review the latest live smoke report.');
    expect(
      () => viewModel.rows.add(
        const ComputerUseActionGateRow(
          label: 'Unexpected',
          status: 'ready',
          isPositive: true,
          detail: 'Unexpected row.',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('preserves row order and pre-smoke instructional details', () {
    final rows = _viewModel(
      accessibilityGranted: false,
      screenCaptureGranted: false,
      captureGate: null,
    ).rows;

    expect(rows.map((row) => row.label), [
      'Helper boundary',
      'Accessibility permission',
      'Screen recording permission',
      'Capture smoke',
      'Input smoke',
      'System audio smoke',
      'Overlay smoke',
      'Unsafe arms',
    ]);
    expect(rows[1].status, 'blocked');
    expect(rows[1].detail, 'Grant Accessibility to Caverno Computer Use.');
    expect(rows[2].status, 'blocked');
    expect(
      rows[2].detail,
      'Grant Screen & System Audio Recording to Caverno Computer Use.',
    );
    expect(rows.sublist(3).map((row) => row.detail), [
      'Run live smoke after permissions are granted.',
      'Arm non-destructive input smoke only when ready to test.',
      'System audio is optional and uses Screen & System Audio Recording.',
      'Run overlay smoke before marking M1 onboarding ready.',
      'Click and text input remain separately armed.',
    ]);
  });

  test('uses live gate actions and preserves positive-state rules', () {
    final rows = _viewModel(
      inputGate: const {'status': 'failed', 'nextAction': 'Retry input smoke.'},
      audioGate: const {
        'status': 'unsupported',
        'nextAction': 'Audio is unavailable.',
      },
      overlaySmoke: const {'status': 'ready', 'nextAction': 'Overlay passed.'},
      unsafeActionGate: const {
        'status': 'armed',
        'nextAction': 'Unsafe actions are armed.',
      },
      hasLiveSmokeReport: true,
    ).rows;

    expect(rows[4].detail, 'Retry input smoke.');
    expect(rows[4].isPositive, isFalse);
    expect(rows[5].detail, 'Audio is unavailable.');
    expect(rows[5].isPositive, isTrue);
    expect(rows[6].detail, 'Overlay passed.');
    expect(rows[6].isPositive, isTrue);
    expect(rows[7].detail, 'Unsafe actions are armed.');
    expect(rows[7].isPositive, isTrue);
  });

  testWidgets('renders every immutable row with matching status icon', (
    tester,
  ) async {
    await _pumpPlan(
      tester,
      _viewModel(
        inputGate: const {'status': 'failed'},
        audioGate: const {'status': 'unsupported'},
        overlaySmoke: const {'status': 'ready'},
        unsafeActionGate: const {'status': 'armed'},
      ),
    );

    expect(find.text('Computer Use action plan'), findsOneWidget);
    expect(find.text('Helper boundary: ready'), findsOneWidget);
    expect(find.text('Input smoke: failed'), findsOneWidget);
    expect(find.text('System audio smoke: unsupported'), findsOneWidget);
    expect(find.text('Unsafe arms: armed'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(7));
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });
}

ComputerUseActionGatePlanViewModel _viewModel({
  bool helperInstalled = true,
  bool helperRunning = true,
  bool helperIpcReady = true,
  bool accessibilityGranted = true,
  bool screenCaptureGranted = true,
  Map<String, dynamic>? captureGate = const {
    'status': 'ready',
    'nextAction': 'Capture passed.',
  },
  Map<String, dynamic>? inputGate = const {'status': 'ready'},
  Map<String, dynamic>? audioGate = const {'status': 'ready'},
  Map<String, dynamic>? overlaySmoke = const {'status': 'ready'},
  Map<String, dynamic>? unsafeActionGate = const {'status': 'armed'},
  bool hasLiveSmokeReport = false,
}) {
  return ComputerUseActionGatePlanViewModel.fromState(
    helperInstalled: helperInstalled,
    helperRunning: helperRunning,
    helperIpcReady: helperIpcReady,
    accessibilityGranted: accessibilityGranted,
    screenCaptureGranted: screenCaptureGranted,
    captureGate: captureGate,
    inputGate: inputGate,
    audioGate: audioGate,
    overlaySmoke: overlaySmoke,
    unsafeActionGate: unsafeActionGate,
    hasLiveSmokeReport: hasLiveSmokeReport,
  );
}

Future<void> _pumpPlan(
  WidgetTester tester,
  ComputerUseActionGatePlanViewModel viewModel,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ComputerUseActionGatePlan(viewModel: viewModel),
        ),
      ),
    ),
  );
}
