import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../../project_farm/application/project_task_review_workflow.dart';
import '../../../project_farm/application/project_task_starter.dart';
import '../../../project_farm/application/project_task_workflow_session.dart';
import '../../../project_farm/data/project_git_status_reader.dart';
import '../../../project_farm/domain/entities/roadmap_snapshot.dart';
import '../../../project_farm/presentation/providers/roadmap_snapshot_providers.dart';
import '../../application/caverno_cli_contract.dart';

/// The roadmap item a farm run works on: [requestedId] when given, otherwise
/// the snapshot's recommendation. Blocked items are never started.
RoadmapItemSnapshot selectFarmRoadmapItem(
  RoadmapSnapshot snapshot,
  String? requestedId,
) {
  final wanted = requestedId?.trim().toLowerCase() ?? '';
  if (wanted.isEmpty) {
    final recommended = snapshot.recommended;
    if (recommended == null) {
      throw const CavernoCliFailure(
        code: 'roadmap_item_unavailable',
        message:
            'The roadmap has no recommended item; select one with --item <id>.',
        exitCode: CavernoCliExitCode.blocked,
      );
    }
    return recommended;
  }
  bool matches(RoadmapItemSnapshot item) =>
      item.id.trim().toLowerCase() == wanted;
  if (snapshot.blocked.any(matches)) {
    throw CavernoCliFailure(
      code: 'roadmap_item_blocked',
      message: 'Roadmap item $requestedId is blocked.',
      exitCode: CavernoCliExitCode.blocked,
    );
  }
  final item = [
    ?snapshot.recommended,
    ...snapshot.current,
    ...snapshot.upcoming,
  ].where(matches).firstOrNull;
  if (item == null) {
    throw CavernoCliFailure(
      code: 'roadmap_item_not_found',
      message: 'Roadmap item not found: $requestedId',
      exitCode: CavernoCliExitCode.input,
    );
  }
  return item;
}

/// Runs one roadmap task through the shared project task workflow from the
/// terminal, publishing its decisions and one session terminal event.
final class CavernoTerminalFarmRun {
  CavernoTerminalFarmRun({
    required this.container,
    required this.runtime,
    ProjectGitStatusReader gitReader = const ProjectGitStatusReader(),
  }) : _gitReader = gitReader;

  final ProviderContainer container;
  final CavernoExecutionRuntime runtime;
  final ProjectGitStatusReader _gitReader;
  final ProjectTaskWorkflowSession _session = ProjectTaskWorkflowSession();
  String? _conversationId;
  bool _ended = false;

  /// Starts the task for [projectId] and returns once the workflow ends and
  /// its terminal event is published. A [CavernoCliFailure] thrown before the
  /// workflow starts is reported by the caller.
  Future<void> run({
    required String projectId,
    required String? roadmapItemId,
  }) async {
    final project = container
        .read(codingProjectsNotifierProvider)
        .findById(projectId);
    if (project == null) {
      throw CavernoCliFailure(
        code: 'project_not_found',
        message: 'The coding project is unavailable: $projectId',
        exitCode: CavernoCliExitCode.input,
      );
    }
    // The dashboard asks before starting over uncommitted work; a terminal
    // run has nobody to ask, so it refuses instead of mixing changes.
    final status = await _gitReader.read(project.rootPath);
    if (status != null && status.changedFiles > 0) {
      throw CavernoCliFailure(
        code: 'uncommitted_changes',
        message:
            '${project.rootPath} has ${status.changedFiles} uncommitted '
            'change(s); commit or stash them before a farm run.',
        exitCode: CavernoCliExitCode.blocked,
      );
    }
    final snapshot = await container
        .read(roadmapSnapshotServiceProvider)
        .refresh(projectId: project.id, projectRoot: project.rootPath);
    if (snapshot == null) {
      throw CavernoCliFailure(
        code: 'roadmap_not_found',
        message: 'No readable roadmap document in ${project.rootPath}.',
        exitCode: CavernoCliExitCode.unavailable,
      );
    }
    if (snapshot.status == RoadmapSnapshotStatus.failed) {
      throw CavernoCliFailure(
        code: 'roadmap_extraction_failed',
        message: 'Roadmap extraction failed: ${snapshot.error ?? 'unknown'}',
        exitCode: CavernoCliExitCode.unavailable,
      );
    }
    final item = selectFarmRoadmapItem(snapshot, roadmapItemId);
    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    final conversationId = _conversationId = startProjectTask(
      conversations: conversations,
      projectId: project.id,
      item: item,
      roadmapPath: snapshot.roadmapPath,
      autoReview: true,
    );
    conversations.selectConversation(conversationId);

    Map<String, Object?>? lastDecision;
    final outcome = await _session.run(
      read: container.read,
      conversationId: conversationId,
      languageCode: 'en',
      isActive: () => !_ended,
      onDecision: (decision) {
        lastDecision = decision;
        runtime.publishSessionEvent(
          (sequence, timestamp) => CavernoRuntimeProjectTaskDecision(
            sequence: sequence,
            timestamp: timestamp,
            turnId: cavernoCliFarmSessionTurnId,
            conversationId: conversationId,
            decision: decision,
          ),
        );
      },
    );
    final heading = projectTaskHeading(item);
    switch (outcome) {
      case ProjectTaskWorkflowFinished(
        result: ProjectTaskReviewResult.committed,
      ):
        _complete('Committed roadmap task $heading.');
      case ProjectTaskWorkflowFinished(:final result):
        final reason = lastDecision?['reason'] ?? lastDecision?['gapCodes'];
        _fail(
          code: result == ProjectTaskReviewResult.findingsRemain
              ? 'review_findings_remain'
              : 'workflow_stopped',
          message:
              'Roadmap task $heading did not complete'
              '${reason == null ? '' : ': $reason'}.',
          exitCode: CavernoCliExitCode.blocked,
        );
      case ProjectTaskWorkflowUnavailable():
        _fail(
          code: 'code_review_route_required',
          message: 'A code-review endpoint and model must be configured.',
          exitCode: CavernoCliExitCode.unavailable,
        );
      case ProjectTaskWorkflowSkipped():
        _fail(
          code: 'workflow_not_started',
          message: 'The task thread was not eligible for the workflow.',
          exitCode: CavernoCliExitCode.blocked,
        );
      case ProjectTaskWorkflowFailed(:final error):
        _fail(
          code: 'workflow_failed',
          message: '$error',
          exitCode: CavernoCliExitCode.blocked,
        );
    }
  }

  /// Ends the run early, as when an approval is refused or the user cancels.
  /// The workflow sees the frontend as gone and stops sending turns.
  void stop({
    required String code,
    required String message,
    required int exitCode,
  }) => _fail(code: code, message: message, exitCode: exitCode);

  void _complete(String content) {
    if (_ended) return;
    _ended = true;
    runtime.publishSessionEvent(
      (sequence, timestamp) => CavernoRuntimeRunCompleted(
        sequence: sequence,
        timestamp: timestamp,
        turnId: cavernoCliFarmSessionTurnId,
        conversationId: _conversationId,
        content: content,
      ),
    );
  }

  void _fail({
    required String code,
    required String message,
    required int exitCode,
  }) {
    if (_ended) return;
    _ended = true;
    runtime.publishSessionEvent(
      (sequence, timestamp) => CavernoRuntimeRunFailed(
        sequence: sequence,
        timestamp: timestamp,
        turnId: cavernoCliFarmSessionTurnId,
        conversationId: _conversationId,
        code: code,
        message: message,
        exitCode: exitCode,
      ),
    );
  }
}
