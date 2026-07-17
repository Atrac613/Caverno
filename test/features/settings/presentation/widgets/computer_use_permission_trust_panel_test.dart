import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:caverno/features/settings/presentation/widgets/computer_use_permission_trust_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders permission flow before recovery and routes callbacks', (
    tester,
  ) async {
    var accessibilityCalls = 0;
    var screenRecordingCalls = 0;
    var recheckCalls = 0;

    await _pumpPanel(
      tester,
      accessibilityGranted: false,
      screenCaptureGranted: false,
      recoverySummary: _readySummary,
      onOpenAccessibility: () => accessibilityCalls += 1,
      onOpenScreenRecording: () => screenRecordingCalls += 1,
      onRecheck: () => recheckCalls += 1,
    );

    expect(
      tester.getTopLeft(find.text('Permission flow')).dy,
      lessThan(tester.getTopLeft(find.text('Recovery guidance')).dy),
    );

    await tester.tap(
      find.byKey(const ValueKey('computer-use-permission-flow-accessibility')),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('computer-use-permission-flow-screen-recording'),
      ),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Recheck').first);

    expect(accessibilityCalls, 1);
    expect(screenRecordingCalls, 1);
    expect(recheckCalls, 1);
  });

  testWidgets('disables every permission action while loading', (tester) async {
    await _pumpPanel(
      tester,
      accessibilityGranted: false,
      screenCaptureGranted: false,
      isLoading: true,
      recoverySummary: _readySummary,
    );

    final openButtons = tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    final recheckButtons = tester.widgetList<TextButton>(
      find.widgetWithText(TextButton, 'Recheck'),
    );

    expect(openButtons, hasLength(2));
    expect(openButtons.every((button) => button.onPressed == null), isTrue);
    expect(recheckButtons, hasLength(2));
    expect(recheckButtons.every((button) => button.onPressed == null), isTrue);
  });

  testWidgets('shows completed permission rows without open actions', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      accessibilityGranted: true,
      screenCaptureGranted: true,
      recoverySummary: _readySummary,
    );

    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('Granted to Caverno Computer Use.'), findsNWidgets(2));
    expect(find.text('Done'), findsNWidgets(2));
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('No recovery action is required.'), findsOneWidget);
  });

  testWidgets('renders every conditional recovery detail', (tester) async {
    await _pumpPanel(
      tester,
      accessibilityGranted: false,
      screenCaptureGranted: false,
      recoverySummary: const MacosComputerUsePermissionRecoverySummary(
        status: 'needs_recovery',
        issueIds: [
          'helper_unreachable',
          'stale_helper_diagnostics',
          'debug_release_helper_mismatch',
          'revoked_permissions',
          'missing_permissions',
        ],
        missingPermissionLabels: [
          'Accessibility',
          'Screen & System Audio Recording',
        ],
        revokedPermissionLabels: ['Accessibility'],
        helperSharedDiagnosticsStale: true,
        helperSharedDiagnosticsStaleReasons: ['helper_status_expired'],
        helperPathMismatch: true,
        debugReleaseHelperMismatch: true,
        helperUnreachable: true,
        mainAppPermissionPromptsBlocked: true,
        mainAppPermissionPromptBoundary: 'split_permission_owner',
        nextAction: 'Restart the helper and recheck permissions.',
      ),
    );

    expect(find.text('Needs recovery'), findsOneWidget);
    expect(find.text('Missing permissions'), findsOneWidget);
    expect(
      find.text('Accessibility, Screen & System Audio Recording'),
      findsOneWidget,
    );
    expect(find.text('Revoked permissions'), findsOneWidget);
    expect(find.text('Helper diagnostics'), findsOneWidget);
    expect(find.text('stale: helper_status_expired'), findsOneWidget);
    expect(find.text('Helper path'), findsOneWidget);
    expect(
      find.text('debug/release or standalone helper mismatch'),
      findsOneWidget,
    );
    expect(find.text('Helper reachability'), findsOneWidget);
    expect(find.text('unreachable'), findsOneWidget);
    expect(
      find.text(
        'Accessibility and Screen & System Audio Recording via Caverno Computer Use',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Restart the helper and recheck permissions.'),
      findsOneWidget,
    );
  });
}

const _readySummary = MacosComputerUsePermissionRecoverySummary(
  status: 'ready',
  issueIds: [],
  missingPermissionLabels: [],
  revokedPermissionLabels: [],
  helperSharedDiagnosticsStale: false,
  helperSharedDiagnosticsStaleReasons: [],
  helperPathMismatch: false,
  debugReleaseHelperMismatch: false,
  helperUnreachable: false,
  mainAppPermissionPromptsBlocked: true,
  mainAppPermissionPromptBoundary: 'split_permission_owner',
  nextAction: 'No recovery action is required.',
);

Future<void> _pumpPanel(
  WidgetTester tester, {
  required bool accessibilityGranted,
  required bool screenCaptureGranted,
  required MacosComputerUsePermissionRecoverySummary recoverySummary,
  bool isLoading = false,
  VoidCallback? onOpenAccessibility,
  VoidCallback? onOpenScreenRecording,
  VoidCallback? onRecheck,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ComputerUsePermissionTrustPanel(
            accessibilityGranted: accessibilityGranted,
            screenCaptureGranted: screenCaptureGranted,
            isLoading: isLoading,
            recoverySummary: recoverySummary,
            onOpenAccessibility: onOpenAccessibility ?? () {},
            onOpenScreenRecording: onOpenScreenRecording ?? () {},
            onRecheck: onRecheck ?? () {},
          ),
        ),
      ),
    ),
  );
}
