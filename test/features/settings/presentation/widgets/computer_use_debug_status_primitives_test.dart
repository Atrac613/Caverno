import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_status_primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders section titles and onboarding notes', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          ComputerUseDebugSectionTitle(
            icon: Icons.verified_user_outlined,
            title: 'Permissions',
            subtitle: 'Permission status details',
          ),
          ComputerUseDebugOnboardingNote(
            icon: Icons.front_hand_outlined,
            title: 'User-Operated Runtime Boundary',
            body: 'Desktop actions stay user-operated.',
          ),
        ],
      ),
    );

    expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('Permission status details'), findsOneWidget);
    expect(find.byIcon(Icons.front_hand_outlined), findsOneWidget);
    expect(find.text('User-Operated Runtime Boundary'), findsOneWidget);
    expect(find.text('Desktop actions stay user-operated.'), findsOneWidget);

    final note = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = note.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(8));
    expect(decoration.border, isNotNull);
  });

  testWidgets('renders helper and compatibility backend boundaries', (
    tester,
  ) async {
    await _pump(
      tester,
      const ComputerUseDebugHelperBoundaryPanel(
        backend: MacosComputerUseBackends.helperIpc,
      ),
    );

    expect(find.text('Computer Use App Boundary'), findsOneWidget);
    expect(
      find.text(
        'Privileged desktop control runs in the helper app, which also owns capture TCC.',
      ),
      findsOneWidget,
    );
    expect(find.text('Current executor'), findsOneWidget);
    expect(find.text('Accessibility owner'), findsOneWidget);
    expect(find.text('Screen/audio owner'), findsOneWidget);
    expect(find.text('Target helper'), findsOneWidget);
    expect(find.text('Caverno Computer Use (helper_ipc)'), findsOneWidget);
    expect(
      find.text('Caverno Computer Use (com.noguwo.apps.caverno.computer-use)'),
      findsOneWidget,
    );
    expect(find.byType(SelectableText), findsNWidgets(4));

    await _pump(
      tester,
      const ComputerUseDebugHelperBoundaryPanel(
        backend: MacosComputerUseBackends.inProcessCompatibility,
      ),
    );

    expect(
      find.text('Smoke checks still use the in-process compatibility backend.'),
      findsOneWidget,
    );
    expect(find.text('Caverno (in_process_compatibility)'), findsOneWidget);
  });

  testWidgets('renders onboarding progress and step states', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          ComputerUseDebugOnboardingProgressRow(completed: 2, total: 4),
          ComputerUseDebugOnboardingProgressRow(completed: 0, total: 0),
          ComputerUseDebugOnboardingStepRow(
            label: 'Launch helper',
            complete: true,
          ),
          ComputerUseDebugOnboardingStepRow(
            label: 'Grant permission',
            complete: false,
          ),
        ],
      ),
    );

    final indicators = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(indicators.map((indicator) => indicator.value), [0.5, 0.0]);
    expect(indicators.map((indicator) => indicator.minHeight), [8, 8]);
    expect(find.text('2 of 4 complete'), findsOneWidget);
    expect(find.text('0 of 0 complete'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('maps permission states and delegates settings actions', (
    tester,
  ) async {
    var customActionCount = 0;
    var defaultActionCount = 0;
    await _pump(
      tester,
      Column(
        children: [
          ComputerUseDebugPermissionRow(
            label: 'Granted permission',
            value: true,
            onOpenSettings: () => customActionCount += 100,
          ),
          ComputerUseDebugPermissionRow(
            label: 'Missing permission',
            value: false,
            openSettingsTooltip: 'Open Accessibility Settings',
            onOpenSettings: () => customActionCount += 1,
          ),
          ComputerUseDebugPermissionRow(
            label: 'Unknown permission',
            value: null,
            onOpenSettings: () => defaultActionCount += 1,
          ),
        ],
      ),
    );

    expect(find.text('Granted'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsNWidgets(2));

    await tester.tap(find.byTooltip('Open Accessibility Settings'));
    await tester.pump();
    await tester.tap(find.byTooltip('Open System Settings'));
    await tester.pump();

    expect(customActionCount, 1);
    expect(defaultActionCount, 1);
  });

  testWidgets('maps caller labels across all status states', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          ComputerUseDebugStatusRow(
            label: 'Installed status',
            value: true,
            trueLabel: 'Installed',
            falseLabel: 'Missing',
            unknownLabel: 'Unknown',
          ),
          ComputerUseDebugStatusRow(
            label: 'Running status',
            value: false,
            trueLabel: 'Running',
            falseLabel: 'Stopped',
            unknownLabel: 'Unknown',
          ),
          ComputerUseDebugStatusRow(
            label: 'Reachable status',
            value: null,
            trueLabel: 'Reachable',
            falseLabel: 'Unreachable',
            unknownLabel: 'Not checked',
          ),
        ],
      ),
    );

    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Not checked'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('renders and delegates armed and disabled switches', (
    tester,
  ) async {
    bool? changedValue;
    await _pump(
      tester,
      Column(
        children: [
          ComputerUseDebugArmSwitch(
            key: const ValueKey('armed'),
            title: 'Input Events Armed',
            subtitle: 'Required before pointer input.',
            value: true,
            onChanged: (value) => changedValue = value,
          ),
          const ComputerUseDebugArmSwitch(
            key: ValueKey('disarmed'),
            title: 'System Audio Armed',
            subtitle: 'Required before audio capture.',
            value: false,
            onChanged: null,
          ),
        ],
      ),
    );

    expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    final armedTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(const ValueKey('armed')),
        matching: find.byType(SwitchListTile),
      ),
    );
    final disarmedTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(const ValueKey('disarmed')),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(armedTile.value, isTrue);
    expect(armedTile.onChanged, isNotNull);
    expect(disarmedTile.value, isFalse);
    expect(disarmedTile.onChanged, isNull);

    await tester.tap(find.text('Input Events Armed'));
    await tester.pump();
    expect(changedValue, isFalse);
  });

  testWidgets('renders the active coordinate target label', (tester) async {
    await _pump(
      tester,
      const ComputerUseDebugCoordinateTargetRow(
        label: 'Active source: display screenshot',
      ),
    );

    expect(find.byIcon(Icons.my_location_outlined), findsOneWidget);
    expect(find.text('Active source: display screenshot'), findsOneWidget);
    final decoration = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    expect(
      (decoration.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(8),
    );
  });
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 800, child: SingleChildScrollView(child: child)),
      ),
    ),
  );
}
