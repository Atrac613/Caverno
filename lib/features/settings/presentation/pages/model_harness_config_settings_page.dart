import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../providers/settings_notifier.dart';

/// Per-model harness tuning (LL23, docs/local_llm_agent_roadmap.md).
///
/// Edits the declared harness config for the active model: instruction
/// surfaces, the tool-loop iteration cap, and the recovery / exploration
/// toggles. Empty fields and a zero cap keep the built-in behaviour, so a
/// model with no overrides behaves exactly as before. This is the manual
/// counterpart to the LL17 self-improving loop that will mutate the same
/// config automatically.
class ModelHarnessConfigSettingsPage extends ConsumerStatefulWidget {
  const ModelHarnessConfigSettingsPage({super.key});

  @override
  ConsumerState<ModelHarnessConfigSettingsPage> createState() =>
      _ModelHarnessConfigSettingsPageState();
}

class _ModelHarnessConfigSettingsPageState
    extends ConsumerState<ModelHarnessConfigSettingsPage> {
  late final TextEditingController _bootstrap;
  late final TextEditingController _execution;
  late final TextEditingController _verification;
  late final TextEditingController _failureRecovery;
  late final TextEditingController _toolLoopCap;
  bool _recoveryMiddlewareEnabled = false;
  bool _explorationToEditNudgeEnabled = false;

  @override
  void initState() {
    super.initState();
    final config =
        ref.read(settingsNotifierProvider).effectiveModelHarnessConfig ??
        const ModelHarnessConfig(id: '', model: '');
    _bootstrap = TextEditingController(text: config.bootstrapInstruction);
    _execution = TextEditingController(text: config.executionInstruction);
    _verification = TextEditingController(text: config.verificationInstruction);
    _failureRecovery = TextEditingController(
      text: config.failureRecoveryInstruction,
    );
    _toolLoopCap = TextEditingController(
      text: config.toolLoopMaxIterations > 0
          ? config.toolLoopMaxIterations.toString()
          : '',
    );
    _recoveryMiddlewareEnabled = config.recoveryMiddlewareEnabled;
    _explorationToEditNudgeEnabled = config.explorationToEditNudgeEnabled;
  }

  @override
  void dispose() {
    _bootstrap.dispose();
    _execution.dispose();
    _verification.dispose();
    _failureRecovery.dispose();
    _toolLoopCap.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = ref.read(settingsNotifierProvider);
    final config = ModelHarnessConfig(
      id: '',
      provider: settings.llmProvider,
      baseUrl: settings.baseUrl,
      model: settings.effectiveModel,
      bootstrapInstruction: _bootstrap.text,
      executionInstruction: _execution.text,
      verificationInstruction: _verification.text,
      failureRecoveryInstruction: _failureRecovery.text,
      toolLoopMaxIterations: int.tryParse(_toolLoopCap.text.trim()) ?? 0,
      recoveryMiddlewareEnabled: _recoveryMiddlewareEnabled,
      explorationToEditNudgeEnabled: _explorationToEditNudgeEnabled,
    );
    await ref
        .read(settingsNotifierProvider.notifier)
        .upsertModelHarnessConfig(config);
    if (!mounted) {
      return;
    }
    final messageKey = config.normalizedForPersistence().isEmpty
        ? 'settings.harness_config_cleared'
        : 'settings.harness_config_saved';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(messageKey.tr())));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('settings.harness_config_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'settings.harness_config_intro'.tr(),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'settings.harness_config_active_model'.tr(
              args: [settings.effectiveModel],
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _HarnessTextField(
            fieldKey: const ValueKey('harness-bootstrap'),
            controller: _bootstrap,
            label: 'settings.harness_config_bootstrap_label'.tr(),
            helper: 'settings.harness_config_bootstrap_helper'.tr(),
          ),
          const SizedBox(height: 16),
          _HarnessTextField(
            fieldKey: const ValueKey('harness-execution'),
            controller: _execution,
            label: 'settings.harness_config_execution_label'.tr(),
            helper: 'settings.harness_config_execution_helper'.tr(),
          ),
          const SizedBox(height: 16),
          _HarnessTextField(
            fieldKey: const ValueKey('harness-verification'),
            controller: _verification,
            label: 'settings.harness_config_verification_label'.tr(),
            helper: 'settings.harness_config_verification_helper'.tr(),
          ),
          const SizedBox(height: 16),
          _HarnessTextField(
            fieldKey: const ValueKey('harness-failure-recovery'),
            controller: _failureRecovery,
            label: 'settings.harness_config_failure_recovery_label'.tr(),
            helper: 'settings.harness_config_failure_recovery_helper'.tr(),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('harness-tool-loop-cap'),
            controller: _toolLoopCap,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'settings.harness_config_tool_loop_cap_label'.tr(),
              helperText: 'settings.harness_config_tool_loop_cap_helper'.tr(),
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey('harness-recovery-toggle'),
            value: _recoveryMiddlewareEnabled,
            onChanged: (value) =>
                setState(() => _recoveryMiddlewareEnabled = value),
            title: Text('settings.harness_config_recovery_toggle_label'.tr()),
            subtitle: Text(
              'settings.harness_config_recovery_toggle_helper'.tr(),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('harness-exploration-toggle'),
            value: _explorationToEditNudgeEnabled,
            onChanged: (value) =>
                setState(() => _explorationToEditNudgeEnabled = value),
            title: Text(
              'settings.harness_config_exploration_toggle_label'.tr(),
            ),
            subtitle: Text(
              'settings.harness_config_exploration_toggle_helper'.tr(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('harness-save'),
            onPressed: _save,
            child: Text('settings.harness_config_save'.tr()),
          ),
        ],
      ),
    );
  }
}

class _HarnessTextField extends StatelessWidget {
  const _HarnessTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.helper,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
