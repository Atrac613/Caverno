import 'package:flutter/material.dart';

class ComputerUseDebugPermissionActionsViewModel {
  const ComputerUseDebugPermissionActionsViewModel({required this.isBusy});

  final bool isBusy;
}

class ComputerUseDebugPermissionActions extends StatelessWidget {
  const ComputerUseDebugPermissionActions({
    required this.viewModel,
    required this.onLaunchHelper,
    required this.onRestartHelper,
    required this.onPingHelper,
    required this.onRefresh,
    required this.onRequestAccessibility,
    required this.onOpenAccessibilitySettings,
    required this.onRequestScreenRecording,
    required this.onStopHelperWork,
    required this.onOpenScreenRecordingSettings,
    super.key,
  });

  final ComputerUseDebugPermissionActionsViewModel viewModel;
  final VoidCallback onLaunchHelper;
  final VoidCallback onRestartHelper;
  final VoidCallback onPingHelper;
  final VoidCallback onRefresh;
  final VoidCallback onRequestAccessibility;
  final VoidCallback onOpenAccessibilitySettings;
  final VoidCallback onRequestScreenRecording;
  final VoidCallback onStopHelperWork;
  final VoidCallback onOpenScreenRecordingSettings;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _PermissionAction(
        key: const ValueKey('computer-use-launch-helper'),
        icon: Icons.rocket_launch_outlined,
        label: 'Launch Helper',
        onPressed: onLaunchHelper,
      ),
      _PermissionAction(
        key: const ValueKey('computer-use-restart-helper'),
        icon: Icons.restart_alt,
        label: 'Restart Helper',
        onPressed: onRestartHelper,
      ),
      _PermissionAction(
        key: const ValueKey('computer-use-ping-helper'),
        icon: Icons.sensors_outlined,
        label: 'Ping Helper',
        onPressed: onPingHelper,
      ),
      _PermissionAction(
        icon: Icons.refresh,
        label: 'Refresh',
        onPressed: onRefresh,
      ),
      _PermissionAction(
        icon: Icons.accessibility_new_outlined,
        label: 'Request Accessibility',
        onPressed: onRequestAccessibility,
      ),
      _PermissionAction(
        key: const ValueKey('computer-use-open-accessibility-settings'),
        icon: Icons.settings_outlined,
        label: 'Open Accessibility Settings',
        onPressed: onOpenAccessibilitySettings,
      ),
      _PermissionAction(
        icon: Icons.screenshot_monitor_outlined,
        label: 'Request Screen Recording',
        onPressed: onRequestScreenRecording,
      ),
      _PermissionAction(
        key: const ValueKey('computer-use-stop-helper-work'),
        icon: Icons.stop_circle_outlined,
        label: 'Stop Helper Work',
        onPressed: onStopHelperWork,
      ),
      _PermissionAction(
        key: const ValueKey('computer-use-open-screen-recording-settings'),
        icon: Icons.settings_applications_outlined,
        label: 'Open Screen Recording Settings',
        onPressed: onOpenScreenRecordingSettings,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions)
          FilledButton.tonalIcon(
            key: action.key,
            onPressed: viewModel.isBusy ? null : action.onPressed,
            icon: Icon(action.icon),
            label: Text(action.label),
          ),
      ],
    );
  }
}

class _PermissionAction {
  const _PermissionAction({
    this.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key? key;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}
