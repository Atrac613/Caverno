import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/coding_terminal_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/flutter_run_device.dart';
import '../providers/bottom_dock_provider.dart';
import '../providers/flutter_run_provider.dart';
import 'flutter_run_device_sheet.dart';

/// Takes a run from a button press to a running app: open the log, list the
/// devices, pick one, start.
///
/// Separate from the control widget because it spans a process, a modal sheet
/// and a second process, and each hop is a place the run can end quietly.
class FlutterRunLauncher {
  const FlutterRunLauncher();

  Future<void> run({
    required BuildContext context,
    required WidgetRef ref,
    required String projectRoot,
    required String? threadId,
  }) async {
    final controller = ref.read(flutterRunControllerProvider(projectRoot));
    // Captured before anything async, and before the dock opens: opening it
    // re-parents this widget's subtree, which unmounts the context the picker
    // would otherwise be shown from -- the symptom was a run that listed
    // devices into the log and then silently did nothing.
    final navigator = Navigator.of(context, rootNavigator: true);
    // Open the log before the work starts: device discovery is the part that
    // can stall, and its output is the only thing that explains a stall.
    _showRunLog(ref, threadId);
    final devices = await controller.listDevices(projectRoot: projectRoot);
    // The run flow spans a process, a sheet and a second process; without this
    // a stall anywhere in it looks identical from the outside -- which is how
    // "the picker never appeared" reached the user with nothing to go on.
    appLog(
      '[FlutterRun] listed ${devices.length} device(s) '
      '(${devices.map((device) => device.id).join(', ')}); '
      'navigator mounted=${navigator.mounted}',
    );
    if (devices.isEmpty || !navigator.mounted) return;

    final runnable = [
      for (final device in devices)
        if (device.isSupported) device,
    ];
    // Asking about a single option is friction, not a choice.
    appLog('[FlutterRun] ${runnable.length} runnable device(s)');
    final FlutterRunDevice? device = runnable.length == 1
        ? runnable.single
        : await FlutterRunDeviceSheet.show(navigator.context, devices);
    appLog(
      '[FlutterRun] ${runnable.length == 1 ? 'single runnable device' : 'picker'}'
      ' resolved to ${device?.id ?? 'no selection'}',
    );
    if (device == null) return;

    await controller.start(projectRoot: projectRoot, device: device);
  }

  /// Brings the bottom dock up on the run log.
  void _showRunLog(WidgetRef ref, String? threadId) {
    ref
        .read(bottomDockTabProvider.notifier)
        .select(threadId, BottomDockTab.runLog);
    final terminal = ref.read(codingTerminalServiceProvider);
    if (!terminal.isPanelOpenFor(threadId)) {
      terminal.togglePanel(threadId);
    }
  }
}
