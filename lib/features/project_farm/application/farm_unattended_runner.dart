import '../../chat/domain/entities/coding_project.dart';
import '../../chat/domain/entities/worktree_agent_task.dart';
import '../data/roadmap_snapshot_repository.dart';
import '../domain/entities/farm_run_record.dart';
import '../domain/entities/project_proposal.dart';
import '../domain/entities/roadmap_snapshot.dart';
import 'background_task_runner.dart';

/// What one unattended pass did.
final class FarmUnattendedSummary {
  const FarmUnattendedSummary({required this.started, required this.skipped});

  final int started;
  final int skipped;

  String get detail => 'started $started, skipped $skipped';
}

/// FARM5: advances each opted-in project by one task during idle maintenance.
///
/// Runs only inside the LL18 idle window (the maintenance scheduler owns that
/// gate). For a project to be advanced, all of these must hold, and every one
/// is mechanical:
/// - the user turned unattended runs on and the daily limit is not spent;
/// - the user declared an allowed unattended verification command; project
///   code runs only through the verification runner's workspace containment;
/// - the Run in background gates pass: a verified task, a proposal naming it
///   `unattended`, and no unfinished background task in the project.
///
/// Every start and every skip of an opted-in project is written to the ledger.
/// The result is a branch for review: nothing merges.
final class FarmUnattendedRunner {
  FarmUnattendedRunner({
    required RoadmapSnapshotRepositoryApi repository,
    required List<CodingProject> Function() projects,
    required Future<RoadmapSnapshot?> Function(CodingProject project)
    refreshSnapshot,
    required Future<ProjectProposal?> Function(
      CodingProject project,
      RoadmapSnapshot? snapshot,
    )
    refreshProposal,
    required List<WorktreeAgentTask> Function() tasks,
    required Future<WorktreeAgentTask> Function({
      required String title,
      required String prompt,
      required String codingProjectId,
      required String projectRootPath,
      required String verificationCommand,
      required List<String> acceptanceCriteria,
    })
    enqueue,
    required Future<bool> Function(
      WorktreeAgentTask task,
      bool Function() canStart,
      void Function() start,
    )
    admit,
    required void Function(String projectRootPath) startReady,
    DateTime Function()? now,
  }) : _repository = repository,
       _projects = projects,
       _refreshSnapshot = refreshSnapshot,
       _refreshProposal = refreshProposal,
       _tasks = tasks,
       _enqueue = enqueue,
       _admit = admit,
       _startReady = startReady,
       _now = now ?? DateTime.now;

  final RoadmapSnapshotRepositoryApi _repository;
  final List<CodingProject> Function() _projects;
  final Future<RoadmapSnapshot?> Function(CodingProject) _refreshSnapshot;
  final Future<ProjectProposal?> Function(CodingProject, RoadmapSnapshot?)
  _refreshProposal;
  final List<WorktreeAgentTask> Function() _tasks;
  final Future<WorktreeAgentTask> Function({
    required String title,
    required String prompt,
    required String codingProjectId,
    required String projectRootPath,
    required String verificationCommand,
    required List<String> acceptanceCriteria,
  })
  _enqueue;
  final Future<bool> Function(
    WorktreeAgentTask,
    bool Function(),
    void Function(),
  )
  _admit;
  final void Function(String projectRootPath) _startReady;
  final DateTime Function() _now;

  /// One pass over every project. [isCancelled] is polled between projects,
  /// so a user returning to the machine stops the pass promptly.
  Future<FarmUnattendedSummary> run({
    required bool Function() isCancelled,
  }) async {
    var started = 0;
    var skipped = 0;
    for (final project in _projects()) {
      if (isCancelled()) break;
      final policy = _repository.policyFor(project.id);
      if (policy == null || !policy.allowsUnattendedRuns) continue;

      Future<void> skip(String detail, {String taskId = ''}) async {
        skipped++;
        await _record(project, 'skipped', detail: detail, taskId: taskId);
      }

      if (_runsToday(project.id) >= policy.dailyRunLimit) {
        await skip('daily_limit');
        continue;
      }
      final snapshot = await _refreshSnapshot(project);
      if (isCancelled()) break;
      final proposal = await _refreshProposal(project, snapshot);
      if (isCancelled()) break;
      // Model calls can outlive settings changes or another recorded run.
      // Recheck authority at dispatch instead of using the pre-call policy.
      final currentPolicy = _repository.policyFor(project.id);
      if (currentPolicy == null || !currentPolicy.allowsUnattendedRuns) {
        await skip('unattended_disabled');
        continue;
      }
      if (_runsToday(project.id) >= currentPolicy.dailyRunLimit) {
        await skip('daily_limit');
        continue;
      }
      final item = startableItem(snapshot, proposal);
      final blocker = backgroundRunBlocker(
        policy: currentPolicy,
        proposal: proposal,
        item: item,
        projectTasks: _tasks().where(
          (task) => task.codingProjectId == project.id,
        ),
      );
      if (blocker != null) {
        await skip(blocker.name, taskId: item?.id ?? '');
        continue;
      }
      final command = currentPolicy.unattendedCommand!;
      final task = await runProjectTaskInBackground(
        enqueue: _enqueue,
        startReady: (_) {},
        project: project,
        policy: currentPolicy,
        item: item!,
        roadmapPath: snapshot!.roadmapPath,
        verificationCommand: command,
      );
      bool canStart() {
        final latest = _repository.policyFor(project.id);
        return !isCancelled() &&
            latest != null &&
            latest.allowsUnattendedRuns &&
            latest.unattendedCommand == command &&
            _runsToday(project.id) < latest.dailyRunLimit &&
            !_tasks().any(
              (other) =>
                  other.id != task.id &&
                  other.codingProjectId == project.id &&
                  !other.isTerminal,
            );
      }

      if (!await _admit(task, canStart, () => _startReady(project.rootPath))) {
        skipped++;
        await _record(
          project,
          'held',
          detail: 'admission_closed',
          taskId: item.id,
          command: command,
          branch: task.branchName,
        );
        continue;
      }
      started++;
      await _record(
        project,
        'enqueued',
        taskId: item.id,
        command: command,
        branch: task.branchName,
      );
    }
    return FarmUnattendedSummary(started: started, skipped: skipped);
  }

  int _runsToday(String projectId) {
    final today = _now();
    return _repository
        .farmRuns()
        .where(
          (run) =>
              run.projectId == projectId &&
              run.trigger == 'unattended' &&
              run.outcome == 'enqueued' &&
              _sameLocalDay(run.at, today),
        )
        .length;
  }

  Future<void> _record(
    CodingProject project,
    String outcome, {
    String detail = '',
    String taskId = '',
    String command = '',
    String branch = '',
  }) {
    final at = _now();
    return _repository.appendFarmRun(
      FarmRunRecord(
        id: '${project.id}-${at.microsecondsSinceEpoch}',
        projectId: project.id,
        trigger: 'unattended',
        at: at,
        outcome: outcome,
        taskId: taskId,
        command: command,
        branch: branch,
        detail: detail,
      ),
    );
  }

  static bool _sameLocalDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }
}
