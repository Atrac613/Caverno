import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/datasources/llm_session_log_store.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../domain/entities/personal_eval_case.dart';
import '../providers/personal_eval_cases_notifier.dart';

/// LL19: records the current session as a personal eval case
/// (docs/local_llm_agent_roadmap.md).
///
/// Recording captures the user's real prompt and repo state, so explicit
/// consent is mandatory and the Record action stays disabled until it is
/// granted alongside the required task fields.
class PersonalEvalRecordPage extends ConsumerStatefulWidget {
  const PersonalEvalRecordPage({
    super.key,
    required this.sessionContext,
    this.initialPrompt = '',
    this.initialTitle = '',
  });

  final LlmSessionLogContext sessionContext;
  final String initialPrompt;
  final String initialTitle;

  @override
  ConsumerState<PersonalEvalRecordPage> createState() =>
      _PersonalEvalRecordPageState();
}

class _PersonalEvalRecordPageState
    extends ConsumerState<PersonalEvalRecordPage> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late final TextEditingController _repoStateRef;
  late final TextEditingController _verificationCommand;
  var _consentGranted = false;
  var _verificationResult = PersonalEvalVerificationResult.inconclusive;
  var _split = PersonalEvalCaseSplit.heldIn;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle);
    _prompt = TextEditingController(text: widget.initialPrompt);
    _repoStateRef = TextEditingController();
    _verificationCommand = TextEditingController();
    _prefillRepoStateRefFromGit();
  }

  Future<void> _prefillRepoStateRefFromGit() async {
    final projectRoot = ref
        .read(codingProjectsNotifierProvider)
        .selectedProject
        ?.normalizedRootPath
        .trim();
    if (projectRoot == null || projectRoot.isEmpty) {
      return;
    }

    try {
      final result = await Process.run(
        'git',
        const ['rev-parse', 'HEAD'],
        workingDirectory: projectRoot,
      );
      if (!mounted || result.exitCode != 0) {
        return;
      }

      final repoRef = result.stdout.toString().trim();
      if (repoRef.isEmpty || _repoStateRef.text.trim().isNotEmpty) {
        return;
      }

      setState(() {
        if (_repoStateRef.text.trim().isEmpty) {
          _repoStateRef.text = repoRef;
        }
      });
    } catch (_) {
      return;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _repoStateRef.dispose();
    _verificationCommand.dispose();
    super.dispose();
  }

  bool get _canRecord =>
      _consentGranted &&
      !_submitting &&
      _prompt.text.trim().isNotEmpty &&
      _repoStateRef.text.trim().isNotEmpty;

  Future<void> _record() async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(personalEvalCasesNotifierProvider.notifier)
          .recordFromSession(
            context: widget.sessionContext,
            consentGranted: _consentGranted,
            prompt: _prompt.text,
            repoStateRef: _repoStateRef.text,
            title: _title.text,
            verificationCommand: _verificationCommand.text.trim().isEmpty
                ? null
                : _verificationCommand.text,
            verificationResult: _verificationResult,
            split: _split,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.personal_eval_record_success'.tr())),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.personal_eval_record_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CheckboxListTile(
            key: const ValueKey('personal-eval-record-consent'),
            contentPadding: EdgeInsets.zero,
            value: _consentGranted,
            onChanged: (value) =>
                setState(() => _consentGranted = value ?? false),
            title: Text('settings.personal_eval_record_consent_label'.tr()),
            subtitle: Text('settings.personal_eval_record_consent_helper'.tr()),
          ),
          const SizedBox(height: 8),
          _field(
            key: const ValueKey('personal-eval-record-title'),
            controller: _title,
            label: 'settings.personal_eval_record_title_label'.tr(),
          ),
          const SizedBox(height: 16),
          _field(
            key: const ValueKey('personal-eval-record-prompt'),
            controller: _prompt,
            label: 'settings.personal_eval_record_prompt_label'.tr(),
            minLines: 2,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _field(
            key: const ValueKey('personal-eval-record-repo-ref'),
            controller: _repoStateRef,
            label: 'settings.personal_eval_record_repo_ref_label'.tr(),
            helper: 'settings.personal_eval_record_repo_ref_helper'.tr(),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _field(
            key: const ValueKey('personal-eval-record-verification'),
            controller: _verificationCommand,
            label: 'settings.personal_eval_record_verification_label'.tr(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<PersonalEvalVerificationResult>(
            key: const ValueKey('personal-eval-record-result'),
            initialValue: _verificationResult,
            decoration: InputDecoration(
              labelText: 'settings.personal_eval_record_result_label'.tr(),
              border: const OutlineInputBorder(),
            ),
            items: PersonalEvalVerificationResult.values
                .map(
                  (result) => DropdownMenuItem(
                    value: result,
                    child: Text(
                      'settings.personal_eval_cases_verification_${result.name}'
                          .tr(),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(
              () => _verificationResult = value ?? _verificationResult,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<PersonalEvalCaseSplit>(
            segments: [
              ButtonSegment(
                value: PersonalEvalCaseSplit.heldIn,
                label: Text('settings.personal_eval_record_split_held_in'.tr()),
              ),
              ButtonSegment(
                value: PersonalEvalCaseSplit.heldOut,
                label: Text(
                  'settings.personal_eval_record_split_held_out'.tr(),
                ),
              ),
            ],
            selected: {_split},
            onSelectionChanged: (selection) =>
                setState(() => _split = selection.first),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('personal-eval-record-submit'),
            onPressed: _canRecord ? _record : null,
            child: Text('settings.personal_eval_record_action'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? helper,
    int minLines = 1,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      key: key,
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
