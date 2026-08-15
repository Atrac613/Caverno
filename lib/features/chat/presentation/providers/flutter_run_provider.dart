import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/flutter_run_process_runner.dart';
import '../../domain/entities/flutter_run_issue.dart';
import '../../domain/entities/flutter_run_session.dart';
import '../../domain/services/flutter_run_command_builder.dart';
import '../../domain/services/flutter_run_issue_collector.dart';
import '../../domain/services/flutter_run_session_controller.dart';
import 'chat_data_source_provider.dart';

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

/// Collects issues out of one project's run log.
///
/// Kept alive alongside the run controller: the issues a run produced remain
/// worth reading after the panel that showed them is closed.
final flutterRunIssueCollectorProvider =
    Provider.family<FlutterRunIssueCollector, String>((ref, projectRoot) {
      final collector = FlutterRunIssueCollector(
        dataSource: () => ref.read(chatRemoteDataSourceProvider),
        model: () =>
            ref.read(settingsNotifierProvider).effectiveLogAnalysisModel,
      );
      ref.onDispose(collector.dispose);

      // Every state change carries the whole log, and the collector drops what
      // it has already seen, so feeding it here needs no incremental bookkeeping.
      final subscription = ref
          .watch(flutterRunControllerProvider(projectRoot))
          .states
          .listen((state) {
            collector.observe(state.logs);
            // A failed run gets one final pass, which is where an unknown
            // failure shape becomes an issue from the tail of the output.
            if (state.status == FlutterRunStatus.failed) {
              unawaited(collector.analyseNow(runFailed: true));
            }
          });
      ref.onDispose(subscription.cancel);

      return collector;
    });

/// The issue list for [projectRoot], newest analysis first.
final flutterRunIssuesProvider =
    StreamProvider.family<List<FlutterRunIssue>, String>((ref, projectRoot) {
      final collector = ref.watch(
        flutterRunIssueCollectorProvider(projectRoot),
      );
      return collector.changes;
    });
