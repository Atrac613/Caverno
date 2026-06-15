import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/personal_eval_bake_off_report.dart';
import '../../domain/entities/personal_eval_case.dart';
import '../providers/personal_eval_cases_notifier.dart';

/// LL19: lists recorded personal eval cases, manages their held-in / held-out
/// split, and runs replays / bake-offs (docs/local_llm_agent_roadmap.md).
class PersonalEvalCasesPage extends ConsumerWidget {
  const PersonalEvalCasesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final casesAsync = ref.watch(personalEvalCasesNotifierProvider);
    final caseCount = casesAsync.value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.personal_eval_cases_title'.tr()),
        actions: [
          IconButton(
            key: const ValueKey('personal-eval-bake-off'),
            tooltip: 'settings.personal_eval_bake_off_action'.tr(),
            icon: const Icon(Icons.compare_arrows),
            onPressed: caseCount == 0 ? null : () => _runBakeOff(context, ref),
          ),
        ],
      ),
      body: casesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$error', textAlign: TextAlign.center),
          ),
        ),
        data: (cases) => _CasesList(cases: cases),
      ),
    );
  }

  /// Prompts for a candidate model, runs the bake-off across the whole suite,
  /// and shows the verdict. The run replays the suite twice (incumbent +
  /// candidate), so it can take a while; a blocking progress dialog guards it.
  Future<void> _runBakeOff(BuildContext context, WidgetRef ref) async {
    final candidateModel = await _promptCandidateModel(context);
    if (candidateModel == null || candidateModel.trim().isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(personalEvalCasesNotifierProvider.notifier);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text('settings.personal_eval_bake_off_running'.tr()),
            ),
          ],
        ),
      ),
    );

    try {
      final report = await notifier.runBakeOff(
        candidateModel: candidateModel.trim(),
      );
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop(); // dismiss the progress dialog
      await showDialog<void>(
        context: context,
        builder: (_) => _BakeOffReportDialog(report: report),
      );
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'settings.personal_eval_bake_off_failed'.tr(args: ['$error']),
          ),
        ),
      );
    }
  }

  Future<String?> _promptCandidateModel(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('settings.personal_eval_bake_off_input_title'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'settings.personal_eval_bake_off_input_label'.tr(),
            hintText: 'settings.personal_eval_bake_off_input_hint'.tr(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('settings.personal_eval_bake_off_cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('settings.personal_eval_bake_off_run'.tr()),
          ),
        ],
      ),
    );
  }
}

class _CasesList extends StatelessWidget {
  const _CasesList({required this.cases});

  final List<PersonalEvalCase> cases;

  @override
  Widget build(BuildContext context) {
    final heldIn = cases
        .where((item) => item.split == PersonalEvalCaseSplit.heldIn)
        .toList(growable: false);
    final heldOut = cases
        .where((item) => item.split == PersonalEvalCaseSplit.heldOut)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'settings.personal_eval_cases_intro'.tr(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (cases.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'settings.personal_eval_cases_empty'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (heldIn.isNotEmpty) ...[
          _SectionHeader(
            label: 'settings.personal_eval_cases_section_held_in'.tr(
              args: ['${heldIn.length}'],
            ),
          ),
          for (final evalCase in heldIn) _CaseTile(evalCase: evalCase),
        ],
        if (heldOut.isNotEmpty) ...[
          _SectionHeader(
            label: 'settings.personal_eval_cases_section_held_out'.tr(
              args: ['${heldOut.length}'],
            ),
          ),
          for (final evalCase in heldOut) _CaseTile(evalCase: evalCase),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _CaseTile extends ConsumerWidget {
  const _CaseTile({required this.evalCase});

  final PersonalEvalCase evalCase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(personalEvalCasesNotifierProvider.notifier);
    final title = evalCase.title.trim().isNotEmpty
        ? evalCase.title.trim()
        : evalCase.normalizedPrompt;
    final isHeldIn = evalCase.split == PersonalEvalCaseSplit.heldIn;

    return ListTile(
      key: ValueKey('personal-eval-case-${evalCase.caseId}'),
      contentPadding: EdgeInsets.zero,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${'settings.personal_eval_cases_readiness_${evalCase.readiness.name}'.tr()}'
        ' · ${evalCase.verificationResult.name}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('personal-eval-case-menu-${evalCase.caseId}'),
        onSelected: (action) {
          switch (action) {
            case 'replay':
              _runReplay(context, notifier);
            case 'move':
              notifier.setSplit(
                evalCase.caseId,
                isHeldIn
                    ? PersonalEvalCaseSplit.heldOut
                    : PersonalEvalCaseSplit.heldIn,
              );
            case 'delete':
              notifier.delete(evalCase.caseId);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'replay',
            child: Text('settings.personal_eval_cases_run_replay'.tr()),
          ),
          PopupMenuItem<String>(
            value: 'move',
            child: Text(
              isHeldIn
                  ? 'settings.personal_eval_cases_move_to_held_out'.tr()
                  : 'settings.personal_eval_cases_move_to_held_in'.tr(),
            ),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text('settings.personal_eval_cases_delete'.tr()),
          ),
        ],
      ),
    );
  }

  /// Replays the case through the candidate model and reports the verdict via a
  /// snackbar. The replay runs an LLM turn, so it can take a while; the running
  /// snackbar stays until the result replaces it.
  Future<void> _runReplay(
    BuildContext context,
    PersonalEvalCasesNotifier notifier,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('settings.personal_eval_cases_replay_running'.tr()),
      ),
    );
    try {
      final run = await notifier.replayCase(evalCase.caseId);
      final result = run.cases.isEmpty ? null : run.cases.first;
      final verdict = result == null
          ? 'settings.personal_eval_cases_verification_inconclusive'.tr()
          : 'settings.personal_eval_cases_verification_'
                    '${result.verificationResult.name}'
                .tr();
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'settings.personal_eval_cases_replay_done'.tr(
              args: [verdict, '${result?.durationMs ?? 0}'],
            ),
          ),
        ),
      );
    } catch (error) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'settings.personal_eval_cases_replay_failed'.tr(args: ['$error']),
          ),
        ),
      );
    }
  }
}

/// Shows a bake-off verdict: the swap recommendation, per-split pass rates, and
/// the regression / watch / improvement tallies.
class _BakeOffReportDialog extends StatelessWidget {
  const _BakeOffReportDialog({required this.report});

  final PersonalEvalBakeOffReport report;

  @override
  Widget build(BuildContext context) {
    final recommended =
        report.recommendation ==
        PersonalEvalBakeOffRecommendation.candidateReady;
    final theme = Theme.of(context);

    return AlertDialog(
      key: const ValueKey('personal-eval-bake-off-report'),
      title: Text(
        recommended
            ? 'settings.personal_eval_bake_off_recommendation_candidateReady'
                  .tr()
            : 'settings.personal_eval_bake_off_recommendation_rejectCandidate'
                  .tr(),
        style: theme.textTheme.titleMedium?.copyWith(
          color: recommended ? Colors.green : theme.colorScheme.error,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'settings.personal_eval_bake_off_models'.tr(
              args: [
                report.incumbentModel ?? '?',
                report.candidateModel ?? '?',
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'settings.personal_eval_bake_off_split_held_in'.tr(
              args: [
                _percent(report.heldIn.incumbentPassRate),
                _percent(report.heldIn.candidatePassRate),
              ],
            ),
          ),
          Text(
            'settings.personal_eval_bake_off_split_held_out'.tr(
              args: [
                _percent(report.heldOut.incumbentPassRate),
                _percent(report.heldOut.candidatePassRate),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'settings.personal_eval_bake_off_summary'.tr(
              args: [
                '${report.hardRegressionCount}',
                '${report.watchSignalCount}',
                '${report.improvementCount}',
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('settings.personal_eval_bake_off_close'.tr()),
        ),
      ],
    );
  }

  static String _percent(double rate) => '${(rate * 100).round()}%';
}
