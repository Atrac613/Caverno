import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_permission_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const labels = [
    'Launch Helper',
    'Restart Helper',
    'Ping Helper',
    'Refresh',
    'Request Accessibility',
    'Open Accessibility Settings',
    'Request Screen Recording',
    'Stop Helper Work',
    'Open Screen Recording Settings',
  ];
  const icons = [
    Icons.rocket_launch_outlined,
    Icons.restart_alt,
    Icons.sensors_outlined,
    Icons.refresh,
    Icons.accessibility_new_outlined,
    Icons.settings_outlined,
    Icons.screenshot_monitor_outlined,
    Icons.stop_circle_outlined,
    Icons.settings_applications_outlined,
  ];
  const keys = <Key?>[
    ValueKey('computer-use-launch-helper'),
    ValueKey('computer-use-restart-helper'),
    ValueKey('computer-use-ping-helper'),
    null,
    null,
    ValueKey('computer-use-open-accessibility-settings'),
    null,
    ValueKey('computer-use-stop-helper-work'),
    ValueKey('computer-use-open-screen-recording-settings'),
  ];

  testWidgets('idle state preserves order and dispatches every callback', (
    tester,
  ) async {
    final calls = <String>[];
    await _pumpActions(tester, isBusy: false, calls: calls);

    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.spacing, 8);
    expect(wrap.runSpacing, 8);

    final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton));
    expect(buttons, hasLength(labels.length));
    expect(
      tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
      labels,
    );
    expect(buttons.map((button) => button.key), keys);
    expect(
      tester.widgetList<Icon>(find.byType(Icon)).map((icon) => icon.icon),
      icons,
    );

    for (final button in buttons) {
      expect(button.onPressed, isNotNull);
      button.onPressed!();
    }
    expect(calls, labels);
  });

  testWidgets(
    'busy state disables every action without changing presentation',
    (tester) async {
      final calls = <String>[];
      await _pumpActions(tester, isBusy: true, calls: calls);

      final buttons = tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      );
      expect(buttons, hasLength(labels.length));
      expect(buttons.every((button) => button.onPressed == null), isTrue);
      expect(buttons.map((button) => button.key), keys);
      expect(
        tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
        labels,
      );
      expect(calls, isEmpty);
    },
  );
}

Future<void> _pumpActions(
  WidgetTester tester, {
  required bool isBusy,
  required List<String> calls,
}) {
  void record(String label) => calls.add(label);

  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ComputerUseDebugPermissionActions(
          viewModel: ComputerUseDebugPermissionActionsViewModel(isBusy: isBusy),
          onLaunchHelper: () => record('Launch Helper'),
          onRestartHelper: () => record('Restart Helper'),
          onPingHelper: () => record('Ping Helper'),
          onRefresh: () => record('Refresh'),
          onRequestAccessibility: () => record('Request Accessibility'),
          onOpenAccessibilitySettings: () =>
              record('Open Accessibility Settings'),
          onRequestScreenRecording: () => record('Request Screen Recording'),
          onStopHelperWork: () => record('Stop Helper Work'),
          onOpenScreenRecordingSettings: () =>
              record('Open Screen Recording Settings'),
        ),
      ),
    ),
  );
}
