import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/services/live_llm_diagnostic_request_shape.dart';
import '../providers/live_llm_diagnostic_notifier.dart';
import '../providers/settings_notifier.dart';

/// The thinking mode and reasoning effort the next diagnostic run sends.
///
/// These are the diagnostic's own controls, independent of the chat composer:
/// a score is only comparable with runs made under the same conditions, so
/// the conditions are chosen here and recorded in the report.
class LiveLlmDiagnosticRunConditions extends ConsumerWidget {
  const LiveLlmDiagnosticRunConditions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(liveLlmDiagnosticNotifierProvider);
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(liveLlmDiagnosticNotifierProvider.notifier);
    final canControlThinking = LiveLlmDiagnosticRequestShape.canControlThinking(
      settings,
    );
    final defaultEffort = LiveLlmDiagnosticRequestShape.defaultEffortFor(
      settings,
      state.thinkingMode,
    );
    final enabled = !state.isRunning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<LiveLlmDiagnosticThinkingMode>(
                key: const ValueKey('live-llm-diag-thinking-mode'),
                initialValue: state.thinkingMode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'settings.live_llm_diag_thinking_mode'.tr(),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final mode in LiveLlmDiagnosticThinkingMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(
                        'settings.live_llm_diag_thinking_${mode.name}'.tr(),
                      ),
                    ),
                ],
                onChanged: enabled && canControlThinking
                    ? (mode) {
                        if (mode != null) notifier.setThinkingMode(mode);
                      }
                    : null,
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<ReasoningEffortPreference?>(
                key: const ValueKey('live-llm-diag-reasoning-effort'),
                initialValue: state.reasoningEffort,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'settings.reasoning_effort_label'.tr(),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      'settings.live_llm_diag_effort_default'.tr(
                        namedArgs: {'effort': _effortLabel(defaultEffort)},
                      ),
                    ),
                  ),
                  for (final effort in ReasoningEffortPreference.values)
                    DropdownMenuItem(
                      value: effort,
                      child: Text(_effortLabel(effort)),
                    ),
                ],
                onChanged: enabled ? notifier.setReasoningEffort : null,
              ),
            ),
          ],
        ),
        if (!canControlThinking) ...[
          const SizedBox(height: 4),
          Text(
            key: const ValueKey('live-llm-diag-thinking-uncontrollable'),
            'settings.live_llm_diag_thinking_uncontrollable'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  static String _effortLabel(ReasoningEffortPreference effort) =>
      'settings.reasoning_effort_${effort.name}'.tr();
}
