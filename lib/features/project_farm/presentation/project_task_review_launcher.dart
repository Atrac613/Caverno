import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/project_task_review_workflow.dart';
import '../application/project_task_workflow_session.dart';

/// Starts the automatic workflow for a dashboard-started roadmap task when its
/// thread is first opened, and reports the outcome.
///
/// Lives outside `ChatPage` so the page only forwards the selection; the page
/// library has no size budget left for the wiring. The workflow itself is the
/// frontend-neutral [ProjectTaskWorkflowSession].
final class ProjectTaskReviewLauncher {
  ProjectTaskReviewLauncher({ProjectTaskWorkflowSession? session})
    : _session = session ?? ProjectTaskWorkflowSession();

  final ProjectTaskWorkflowSession _session;

  Future<void> start({
    required WidgetRef ref,
    required String conversationId,
    required String languageCode,
    required bool Function() isMounted,
    required void Function(String message) showMessage,
  }) async {
    final outcome = await _session.run(
      read: ref.read,
      conversationId: conversationId,
      languageCode: languageCode,
      isActive: isMounted,
    );
    switch (outcome) {
      case ProjectTaskWorkflowSkipped():
        return;
      case ProjectTaskWorkflowUnavailable():
        showMessage('chat.slash_review_not_configured'.tr());
      case ProjectTaskWorkflowFinished(:final result, :final stillSelected):
        if (!stillSelected) return;
        showMessage(switch (result) {
          ProjectTaskReviewResult.committed =>
            'chat.project_task_review_committed'.tr(),
          ProjectTaskReviewResult.findingsRemain =>
            'chat.project_task_review_findings'.tr(),
          ProjectTaskReviewResult.stopped =>
            'chat.project_task_review_stopped'.tr(),
        });
      case ProjectTaskWorkflowFailed(:final error):
        if (!isMounted()) return;
        showMessage(
          'chat.project_task_review_error'.tr(
            namedArgs: {'error': error.toString()},
          ),
        );
    }
  }
}
