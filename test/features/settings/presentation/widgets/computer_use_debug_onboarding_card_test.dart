import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_onboarding_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('view model copies source collections and exposes snapshots', () {
    final steps = <ComputerUseDebugOnboardingStep>[
      const ComputerUseDebugOnboardingStep(
        label: 'Launch helper',
        complete: false,
      ),
    ];
    final blockers = <String>['helper_unreachable'];
    final viewModel = ComputerUseDebugOnboardingViewModel(
      steps: steps,
      xpcProductionBlockers: blockers,
      xpcProductionNextAction: 'Start the helper.',
    );

    steps.add(
      const ComputerUseDebugOnboardingStep(
        label: 'Grant permission',
        complete: true,
      ),
    );
    blockers[0] = 'changed';

    expect(viewModel.steps, hasLength(1));
    expect(viewModel.steps.single.label, 'Launch helper');
    expect(viewModel.xpcProductionBlockers, ['helper_unreachable']);
    expect(
      () => viewModel.steps.add(
        const ComputerUseDebugOnboardingStep(
          label: 'Unexpected',
          complete: false,
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => viewModel.xpcProductionBlockers.add('unexpected'),
      throwsUnsupportedError,
    );
  });

  testWidgets('renders first incomplete step and ordered XPC blockers', (
    tester,
  ) async {
    await _pump(
      tester,
      ComputerUseDebugOnboardingViewModel(
        steps: const [
          ComputerUseDebugOnboardingStep(
            label: 'Launch helper',
            complete: true,
          ),
          ComputerUseDebugOnboardingStep(
            label: 'Verify helper IPC',
            complete: false,
          ),
          ComputerUseDebugOnboardingStep(
            label: 'Grant Accessibility',
            complete: false,
          ),
        ],
        xpcProductionBlockers: const [
          'helper_unreachable',
          'permission_missing',
        ],
        xpcProductionNextAction: 'Resolve the first blocker.',
      ),
    );

    expect(find.text('Computer Use Onboarding'), findsOneWidget);
    expect(find.text('Next: Verify helper IPC'), findsOneWidget);
    expect(find.text('1 of 3 complete'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Pending'), findsNWidgets(2));
    expect(find.text('XPC Production Blocker'), findsOneWidget);
    expect(find.text('helper_unreachable, permission_missing'), findsOneWidget);
    expect(find.text('XPC Next Action'), findsOneWidget);
    expect(find.text('Resolve the first blocker.'), findsOneWidget);
    expect(find.byIcon(Icons.route_outlined), findsOneWidget);
    expect(find.byIcon(Icons.next_plan_outlined), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsNothing);

    expect(
      tester.getTopLeft(find.text('Launch helper')).dy,
      lessThan(tester.getTopLeft(find.text('Verify helper IPC')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Verify helper IPC')).dy,
      lessThan(tester.getTopLeft(find.text('Grant Accessibility')).dy),
    );
  });

  testWidgets('renders the ready state when every step is complete', (
    tester,
  ) async {
    await _pump(
      tester,
      ComputerUseDebugOnboardingViewModel(
        steps: const [
          ComputerUseDebugOnboardingStep(
            label: 'Launch helper',
            complete: true,
          ),
          ComputerUseDebugOnboardingStep(
            label: 'Verify helper IPC',
            complete: true,
          ),
        ],
        xpcProductionBlockers: const [],
        xpcProductionNextAction: 'XPC is production ready.',
      ),
    );

    expect(find.text('All onboarding checks are complete.'), findsOneWidget);
    expect(find.text('2 of 2 complete'), findsOneWidget);
    expect(find.text('Done'), findsNWidgets(2));
    expect(find.text('Pending'), findsNothing);
    expect(find.text('XPC Production Ready'), findsOneWidget);
    expect(find.text('XPC is production ready.'), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    expect(find.text('XPC Production Blocker'), findsNothing);
    expect(find.text('XPC Next Action'), findsNothing);
  });

  testWidgets('renders a zero-step ready state without step rows', (
    tester,
  ) async {
    await _pump(
      tester,
      ComputerUseDebugOnboardingViewModel(
        steps: const [],
        xpcProductionBlockers: const [],
        xpcProductionNextAction: 'No onboarding checks are required.',
      ),
    );

    expect(find.text('All onboarding checks are complete.'), findsOneWidget);
    expect(find.text('0 of 0 complete'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    expect(find.text('Pending'), findsNothing);
    expect(find.text('XPC Production Ready'), findsOneWidget);
    expect(find.text('No onboarding checks are required.'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ComputerUseDebugOnboardingViewModel viewModel,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 800,
            child: ComputerUseDebugOnboardingCard(viewModel: viewModel),
          ),
        ),
      ),
    ),
  );
}
