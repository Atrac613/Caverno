import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/personal_eval_case.dart';
import '../providers/personal_eval_cases_notifier.dart';

/// LL19: lists recorded personal eval cases and manages their held-in /
/// held-out split (docs/local_llm_agent_roadmap.md).
class PersonalEvalCasesPage extends ConsumerWidget {
  const PersonalEvalCasesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final casesAsync = ref.watch(personalEvalCasesNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text('settings.personal_eval_cases_title'.tr())),
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
}
