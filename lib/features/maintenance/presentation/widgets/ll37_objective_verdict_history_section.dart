import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../chat/domain/entities/worktree_agent_task.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/ll37_objective_verdict_record.dart';
import '../../domain/services/ll37_approved_repair_task_adapter.dart';
import '../../domain/services/ll37_objective_continuation_policy.dart';
import '../../domain/services/ll37_objective_vote_policy.dart';
import '../../domain/services/ll37_verifier_fidelity_profile.dart';
import '../providers/ll37_approved_repair_task_provider.dart';
import '../providers/ll37_objective_verdict_history_notifier.dart';

class Ll37ObjectiveVerdictHistorySection extends ConsumerWidget {
  const Ll37ObjectiveVerdictHistorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(ll37ObjectiveVerdictHistoryNotifierProvider);
    final cohorts = _cohorts(records);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'settings.idle_maintenance_ll37_history_title'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('settings.idle_maintenance_ll37_history_empty'.tr()),
            ),
          )
        else
          for (final cohort in cohorts)
            _Ll37ObjectiveVerdictCard(
              record: cohort.latest,
              aggregate: cohort.aggregate,
              continuation: cohort.continuation,
            ),
      ],
    );
  }

  List<_Ll37VerdictCohort> _cohorts(List<Ll37ObjectiveVerdictRecord> records) {
    final grouped = <String, List<Ll37ObjectiveVerdictRecord>>{};
    for (final record in records) {
      grouped.putIfAbsent(record.candidateId, () => []).add(record);
    }
    return grouped.values
        .map((votes) {
          final latest = votes.reduce(
            (left, right) =>
                left.recordedAt.isAfter(right.recordedAt) ? left : right,
          );
          final aggregate = const Ll37ObjectiveVotePolicy()
              .plan(
                candidateId: latest.candidateId,
                routes: _routesFor(votes, latest),
                history: votes,
              )
              .aggregate;
          return _Ll37VerdictCohort(
            latest: latest,
            aggregate: aggregate,
            continuation: const Ll37ObjectiveContinuationPolicy().review(
              aggregate,
            ),
          );
        })
        .toList(growable: false);
  }

  List<Ll37ObjectiveVoteRoute> _routesFor(
    List<Ll37ObjectiveVerdictRecord> votes,
    Ll37ObjectiveVerdictRecord latest,
  ) {
    final provider = LlmProvider.values
        .where((item) => item.name == latest.verifierProvider)
        .firstOrNull;
    final profiles = provider == null
        ? const <Ll37VerifierFidelityProfile>[]
        : const Ll37VerifierFidelityRegistry().eligibleProfiles(
            provider: provider,
            baseUrl: latest.verifierBaseUrl,
          );
    if (profiles.isNotEmpty) {
      return profiles
          .map(
            (profile) => Ll37ObjectiveVoteRoute(
              verifierProfileKey: profile.profileKey,
              fidelityReportSha256: profile.reportSha256,
            ),
          )
          .toList(growable: false);
    }
    final fallback = votes.toList(growable: false)
      ..sort((left, right) => left.voteIndex.compareTo(right.voteIndex));
    final identities = <String>{};
    return fallback
        .where(
          (vote) => identities.add(
            '${vote.verifierProfileKey}\u0000'
            '${vote.fidelityReportSha256.toLowerCase()}',
          ),
        )
        .map(
          (vote) => Ll37ObjectiveVoteRoute(
            verifierProfileKey: vote.verifierProfileKey,
            fidelityReportSha256: vote.fidelityReportSha256,
          ),
        )
        .toList(growable: false);
  }
}

class _Ll37VerdictCohort {
  const _Ll37VerdictCohort({
    required this.latest,
    required this.aggregate,
    required this.continuation,
  });

  final Ll37ObjectiveVerdictRecord latest;
  final Ll37ObjectiveVoteAggregate aggregate;
  final Ll37ObjectiveContinuationReview continuation;
}

class _Ll37ObjectiveVerdictCard extends ConsumerStatefulWidget {
  const _Ll37ObjectiveVerdictCard({
    required this.record,
    required this.aggregate,
    required this.continuation,
  });

  final Ll37ObjectiveVerdictRecord record;
  final Ll37ObjectiveVoteAggregate aggregate;
  final Ll37ObjectiveContinuationReview continuation;

  @override
  ConsumerState<_Ll37ObjectiveVerdictCard> createState() =>
      _Ll37ObjectiveVerdictCardState();
}

class _Ll37ObjectiveVerdictCardState
    extends ConsumerState<_Ll37ObjectiveVerdictCard> {
  bool _isQueueing = false;
  String? _queuedAssignmentId;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final aggregate = widget.aggregate;
    final continuation = widget.continuation;
    final tasks = ref.read(ll37ApprovedRepairTaskSourceProvider)();
    final sourceTask = _sourceTask(tasks, continuation.candidateId);
    final existingTaskIds = tasks.map((task) => task.id).toList();
    final queuedAssignmentId = _queuedAssignmentId;
    if (queuedAssignmentId != null) {
      existingTaskIds.add(queuedAssignmentId);
    }
    final repairTaskReview = const Ll37ApprovedRepairTaskAdapter().review(
      continuation: continuation,
      sourceTask: sourceTask,
      existingTaskIds: existingTaskIds,
    );
    return Card(
      key: ValueKey('ll37-verdict-${record.voteId}'),
      child: ExpansionTile(
        leading: Icon(
          _verdictIcon(record.verdict),
          color: _verdictColor(context, record.verdict),
        ),
        title: Text(_verdictLabel(record.verdict)),
        subtitle: Text(
          '${record.sourceSurface} • vote ${record.voteIndex}/'
          '${aggregate.maxVoteCount} • aggregate '
          '${aggregate.status.name}/${aggregate.outcome.name} • '
          '${(record.confidence * 100).toStringAsFixed(0)}% • '
          '${record.recordedAt.toLocal().toIso8601String()}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(
            context,
            'settings.idle_maintenance_ll37_candidate'.tr(),
            record.candidateId,
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_aggregate'.tr(),
            '${aggregate.voteCount}/${aggregate.maxVoteCount} • '
            '${aggregate.status.name}/${aggregate.outcome.name} • '
            '${aggregate.blocking?.name ?? 'pending'}\n'
            '${aggregate.detail}',
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_vote_identities'.tr(),
            _bullets(
              aggregate.votes.map(
                (vote) =>
                    '#${vote.voteIndex} ${vote.verifierModel} '
                    '${vote.voteId} — '
                    '${vote.verdict}/${vote.blocking}',
              ),
            ),
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_continuation_review'.tr(),
            '${continuation.status.name}\n${continuation.detail}',
          ),
          if (continuation.gaps.isNotEmpty)
            _field(
              context,
              'settings.idle_maintenance_ll37_repair_gaps'.tr(),
              _bullets(
                continuation.gaps.map(
                  (gap) =>
                      '[${gap.id}] ${gap.kind} — '
                      '${gap.location}: ${gap.detail}',
                ),
              ),
            ),
          if (continuation.canCopyRepairNudge) ...[
            _field(
              context,
              'settings.idle_maintenance_ll37_repair_nudge'.tr(),
              continuation.repairNudge!,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: ValueKey('ll37-copy-repair-nudge-${record.candidateId}'),
                onPressed: () =>
                    _copyRepairNudge(context, continuation.repairNudge!),
                icon: const Icon(Icons.copy_outlined),
                label: Text(
                  'settings.idle_maintenance_ll37_copy_repair_nudge'.tr(),
                ),
              ),
            ),
            if (repairTaskReview.canQueue) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: ValueKey(
                    'll37-create-repair-task-${record.candidateId}',
                  ),
                  onPressed: _isQueueing
                      ? null
                      : () => _confirmAndQueueRepairTask(
                          repairTaskReview.spec!,
                          continuation,
                        ),
                  icon: _isQueueing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_task_outlined),
                  label: Text(
                    'settings.idle_maintenance_ll37_create_repair_task'.tr(),
                  ),
                ),
              ),
            ] else if (repairTaskReview.status ==
                Ll37ApprovedRepairTaskStatus.alreadyQueued)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'settings.idle_maintenance_ll37_repair_task_already_queued'
                      .tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          _field(
            context,
            'settings.idle_maintenance_ll37_objective'.tr(),
            record.objective,
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_criteria'.tr(),
            _bullets(record.acceptanceCriteria),
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_files'.tr(),
            _bullets(record.changedFilePaths),
          ),
          if (record.implementationEvidence.isNotEmpty)
            _field(
              context,
              'settings.idle_maintenance_ll37_evidence'.tr(),
              _bullets(record.implementationEvidence),
            ),
          _field(
            context,
            'settings.idle_maintenance_ll37_blocking'.tr(),
            record.blocking,
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_findings'.tr(),
            record.findings.isEmpty
                ? 'settings.idle_maintenance_ll37_findings_empty'.tr()
                : _bullets(
                    record.findings.map(
                      (finding) =>
                          '${finding.kind} — ${finding.location}: '
                          '${finding.detail}',
                    ),
                  ),
          ),
          if (record.error != null)
            _field(
              context,
              'settings.idle_maintenance_ll37_error'.tr(),
              record.error!,
            ),
          if (record.detail != null)
            _field(
              context,
              'settings.idle_maintenance_ll37_detail'.tr(),
              record.detail!,
            ),
          _field(
            context,
            'settings.idle_maintenance_ll37_verifier'.tr(),
            '${record.verifierProvider}\n'
            '${record.verifierModel}\n${record.verifierBaseUrl}',
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_report'.tr(),
            'schema ${record.fidelityReportSchemaVersion} • '
            '${record.fidelityReportSha256}',
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_tokens'.tr(),
            '${record.estimatedTotalTokens}',
          ),
          _field(
            context,
            'settings.idle_maintenance_ll37_requests'.tr(),
            '${record.requestCount}',
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontFamily: kMonoFontFamily, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _copyRepairNudge(BuildContext context, String nudge) async {
    await Clipboard.setData(ClipboardData(text: nudge));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'settings.idle_maintenance_ll37_repair_nudge_copied'.tr(),
        ),
      ),
    );
  }

  WorktreeAgentTask? _sourceTask(
    Iterable<WorktreeAgentTask> tasks,
    String candidateId,
  ) {
    const prefix = 'worktree-agent:';
    if (!candidateId.startsWith(prefix)) return null;
    final sourceTaskId = candidateId.substring(prefix.length);
    for (final task in tasks) {
      if (task.id == sourceTaskId) return task;
    }
    return null;
  }

  Future<void> _confirmAndQueueRepairTask(
    Ll37ApprovedRepairTaskSpec spec,
    Ll37ObjectiveContinuationReview continuation,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'settings.idle_maintenance_ll37_repair_task_confirm_title'.tr(),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'settings.idle_maintenance_ll37_repair_task_confirm_body'.tr(),
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Objective: ${continuation.objective}\n'
                'Acceptance criteria:\n'
                '${_bullets(continuation.acceptanceCriteria)}\n'
                'Gap IDs:\n${_bullets(continuation.gaps.map((gap) => gap.id))}\n'
                'Verification: ${spec.verificationCommand}\n'
                'Base branch: ${spec.baseBranch}',
                style: const TextStyle(
                  fontFamily: kMonoFontFamily,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('ll37-repair-task-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const ValueKey('ll37-repair-task-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'settings.idle_maintenance_ll37_create_repair_task'.tr(),
            ),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _isQueueing = true);
    try {
      final currentTasks = ref.read(ll37ApprovedRepairTaskSourceProvider)();
      final currentSource = _sourceTask(currentTasks, continuation.candidateId);
      final currentReview = const Ll37ApprovedRepairTaskAdapter().review(
        continuation: continuation,
        sourceTask: currentSource,
        existingTaskIds: currentTasks.map((task) => task.id),
      );
      if (!currentReview.canQueue ||
          currentReview.spec!.assignmentId != spec.assignmentId) {
        throw StateError(currentReview.detail);
      }
      final task = await ref.read(ll37ApprovedRepairTaskEnqueueProvider)(spec);
      if (!mounted) return;
      setState(() => _queuedAssignmentId = task.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'settings.idle_maintenance_ll37_repair_task_queued'.tr(
              namedArgs: {'branch': task.branchName},
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'settings.idle_maintenance_ll37_repair_task_failed'.tr(
              namedArgs: {'error': '$error'},
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isQueueing = false);
    }
  }

  String _verdictLabel(String verdict) {
    final key = switch (verdict) {
      'notRefuted' => 'not_refuted',
      'refuted' => 'refuted',
      _ => 'unverifiable',
    };
    return 'settings.idle_maintenance_ll37_verdict_$key'.tr();
  }

  IconData _verdictIcon(String verdict) {
    return switch (verdict) {
      'notRefuted' => Icons.check_circle_outline,
      'refuted' => Icons.error_outline,
      _ => Icons.help_outline,
    };
  }

  Color _verdictColor(BuildContext context, String verdict) {
    final scheme = Theme.of(context).colorScheme;
    return switch (verdict) {
      'notRefuted' => scheme.primary,
      'refuted' => scheme.error,
      _ => scheme.tertiary,
    };
  }

  String _bullets(Iterable<String> items) =>
      items.map((item) => '• $item').join('\n');
}
