import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_run_conditions.dart';

/// The diagnostic page's title card: what the run measures, the conditions
/// the next run sends, and the run button.
class LiveLlmDiagnosticHeader extends StatelessWidget {
  const LiveLlmDiagnosticHeader({
    super.key,
    required this.isRunning,
    required this.report,
    required this.onRun,
  });

  final bool isRunning;
  final LiveLlmDiagnosticReport? report;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentReport = report;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'settings.live_llm_diagnostics'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'settings.live_llm_diagnostics_desc'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const LiveLlmDiagnosticRunConditions(),
                  if (currentReport != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${'settings.live_llm_diag_endpoint'.tr()}: ${currentReport.baseUrl}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '${'settings.live_llm_diag_model'.tr()}: ${currentReport.model}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: isRunning ? null : onRun,
              icon: isRunning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_outlined),
              label: Text(
                isRunning
                    ? 'settings.live_llm_diag_running'.tr()
                    : 'settings.live_llm_diag_run'.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
