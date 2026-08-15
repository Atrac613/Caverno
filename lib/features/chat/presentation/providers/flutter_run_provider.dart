import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/flutter_run_process_runner.dart';
import '../../domain/entities/flutter_run_session.dart';
import '../../domain/services/flutter_run_command_builder.dart';
import '../../domain/services/flutter_run_session_controller.dart';

final flutterRunProcessRunnerProvider = Provider<FlutterRunProcessRunner>((
  ref,
) {
  return const SystemFlutterRunProcessRunner();
});

final flutterRunCommandBuilderProvider = Provider<FlutterRunCommandBuilder>((
  ref,
) {
  return const FlutterRunCommandBuilder();
});

/// One controller per project root.
///
/// Not auto-disposed: a run outlives the panel that started it, and dropping
/// the controller when the sidebar closes would orphan a live `flutter run`
/// with no way back to its logs or its stop button.
final flutterRunControllerProvider =
    Provider.family<FlutterRunSessionController, String>((ref, projectRoot) {
      final controller = FlutterRunSessionController(
        runner: ref.watch(flutterRunProcessRunnerProvider),
        commands: ref.watch(flutterRunCommandBuilderProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The run state for [projectRoot], starting from whatever the controller
/// already holds so a reopened panel shows a run in progress.
final flutterRunSessionProvider =
    StreamProvider.family<FlutterRunSessionState, String>((ref, projectRoot) {
      final controller = ref.watch(flutterRunControllerProvider(projectRoot));
      return controller.states;
    });

/// Whether the run button applies to [projectRoot] at all.
final flutterRunSupportedProvider = Provider.family<bool, String>((
  ref,
  projectRoot,
) {
  if (projectRoot.trim().isEmpty) return false;
  return ref
      .watch(flutterRunCommandBuilderProvider)
      .isFlutterProject(projectRoot);
});
