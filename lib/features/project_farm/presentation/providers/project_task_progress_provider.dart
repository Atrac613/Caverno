import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/project_task_progress.dart';

/// The running or last-finished workflow stage of each project-task thread,
/// keyed by conversation id.
///
/// Held in memory on purpose: the workflow that writes it does not survive a
/// restart either, and a persisted stage would claim a run that no longer
/// exists.
final projectTaskProgressProvider =
    NotifierProvider<
      ProjectTaskProgressNotifier,
      Map<String, ProjectTaskProgress>
    >(ProjectTaskProgressNotifier.new);

class ProjectTaskProgressNotifier
    extends Notifier<Map<String, ProjectTaskProgress>> {
  @override
  Map<String, ProjectTaskProgress> build() => const {};

  void report(String conversationId, ProjectTaskProgress progress) {
    state = {...state, conversationId: progress};
  }
}
