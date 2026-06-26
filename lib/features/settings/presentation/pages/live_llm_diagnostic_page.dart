import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/live_llm_diagnostic.dart';
import '../../domain/services/live_llm_diagnostic_service.dart';
import '../providers/live_llm_diagnostic_notifier.dart';
import '../providers/settings_notifier.dart';
import '../../../../core/theme/app_tokens.dart';

const _foundationModelsCanaryCommand =
    'tool/run_foundation_models_live_canary.sh';
const _foundationModelsCanaryReportPath =
    'build/integration_test_reports/foundation_models_live_canary_<timestamp>/canary_summary.json';

class LiveLlmDiagnosticPage extends ConsumerWidget {
  const LiveLlmDiagnosticPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveLlmDiagnosticNotifierProvider);
    final report = state.report;
    final settings = ref.watch(settingsNotifierProvider);
    final showFoundationModelsCanary =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        settings.llmProvider == LlmProvider.appleFoundationModels;

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.live_llm_diagnostics'.tr()),
        actions: [
          if (report != null)
            IconButton(
              tooltip: 'settings.live_llm_diag_copy'.tr(),
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => _copyReport(context, report),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DiagnosticHeader(
            isRunning: state.isRunning,
            report: report,
            onRun: () =>
                ref.read(liveLlmDiagnosticNotifierProvider.notifier).run(),
          ),
          if (showFoundationModelsCanary) ...[
            const SizedBox(height: 12),
            const _FoundationModelsCanaryCard(),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(error: state.error!),
          ],
          const SizedBox(height: 16),
          if (report == null)
            _EmptyState(isRunning: state.isRunning)
          else ...[
            _SummarySection(report: report),
            const SizedBox(height: 16),
            _ToolCatalogSection(report: report),
            if (report.samplerCalibrationSummaries.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SamplerCalibrationSection(report: report),
            ],
            const SizedBox(height: 16),
            _ProbeResultsSection(report: report),
          ],
          const SizedBox(height: 16),
          _ProfileHistorySection(
            revisions: settings.effectiveModelProfileRevisions,
          ),
        ],
      ),
    );
  }

  Future<void> _copyReport(
    BuildContext context,
    LiveLlmDiagnosticReport report,
  ) async {
    final json = const JsonEncoder.withIndent('  ').convert(report.toJson());
    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('settings.live_llm_diag_copied'.tr())),
    );
  }
}

class _FoundationModelsCanaryCard extends StatelessWidget {
  const _FoundationModelsCanaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.science_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'settings.foundation_models_live_canary_title'.tr(),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'settings.foundation_models_live_canary_desc'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CopyableDiagnosticText(
              label: 'settings.foundation_models_live_canary_command'.tr(),
              value: _foundationModelsCanaryCommand,
              copyKey: const ValueKey(
                'foundation-models-live-canary-copy-command',
              ),
              copiedMessageKey:
                  'settings.foundation_models_live_canary_command_copied',
            ),
            const SizedBox(height: 8),
            _CopyableDiagnosticText(
              label: 'settings.foundation_models_live_canary_report'.tr(),
              value: _foundationModelsCanaryReportPath,
              copyKey: const ValueKey(
                'foundation-models-live-canary-copy-report-path',
              ),
              copiedMessageKey:
                  'settings.foundation_models_live_canary_report_copied',
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyableDiagnosticText extends StatelessWidget {
  const _CopyableDiagnosticText({
    required this.label,
    required this.value,
    required this.copyKey,
    required this.copiedMessageKey,
  });

  final String label;
  final String value;
  final Key copyKey;
  final String copiedMessageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kMonoFontFamily,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: copyKey,
          tooltip: 'settings.live_llm_diag_copy'.tr(),
          icon: const Icon(Icons.copy_outlined),
          onPressed: () => _copyText(context, value, copiedMessageKey),
        ),
      ],
    );
  }

  Future<void> _copyText(
    BuildContext context,
    String value,
    String copiedMessageKey,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(copiedMessageKey.tr())));
  }
}

class _DiagnosticHeader extends StatelessWidget {
  const _DiagnosticHeader({
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isRunning});

  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Text(
          isRunning
              ? 'settings.live_llm_diag_preparing'.tr()
              : 'settings.live_llm_diag_no_run'.tr(),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.report});

  final LiveLlmDiagnosticReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'settings.live_llm_diag_summary'.tr()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricTile(
              icon: _statusIcon(report.overallStatus),
              label: 'settings.live_llm_diag_overall'.tr(),
              value: _statusLabel(report.overallStatus),
              color: _statusColor(context, report.overallStatus),
            ),
            _MetricTile(
              icon: Icons.grade_outlined,
              label: 'settings.live_llm_diag_score'.tr(),
              value: '${(report.score * 100).round()}%',
            ),
            _MetricTile(
              icon: Icons.timer_outlined,
              label: 'settings.live_llm_diag_elapsed'.tr(),
              value: _formatDuration(report.elapsed),
            ),
            _MetricTile(
              icon: Icons.check_circle_outline,
              label: 'settings.live_llm_diag_completed'.tr(),
              value: '${report.completedProbeCount}/${report.results.length}',
            ),
          ],
        ),
      ],
    );
  }
}

class _ToolCatalogSection extends StatelessWidget {
  const _ToolCatalogSection({required this.report});

  final LiveLlmDiagnosticReport report;

  @override
  Widget build(BuildContext context) {
    final catalog = report.toolCatalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'settings.live_llm_diag_tool_catalog'.tr()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricTile(
              icon: Icons.construction_outlined,
              label: 'settings.live_llm_diag_tools_total'.tr(),
              value: '${catalog.totalToolCount}',
            ),
            _MetricTile(
              icon: Icons.start_outlined,
              label: 'settings.live_llm_diag_initial_tools'.tr(),
              value: '${catalog.initialToolCount}',
            ),
            _MetricTile(
              icon: Icons.dns_outlined,
              label: 'settings.live_llm_diag_remote_tools'.tr(),
              value: '${catalog.remoteToolCount}',
            ),
            _MetricTile(
              icon: Icons.search_outlined,
              label: 'settings.live_llm_diag_tool_search'.tr(),
              value: catalog.toolSearchEnabled
                  ? 'settings.live_llm_diag_enabled'.tr()
                  : 'settings.live_llm_diag_disabled'.tr(),
            ),
          ],
        ),
        if (catalog.mcpConnectionSummary.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(
            catalog.mcpConnectionSummary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _SamplerCalibrationSection extends StatelessWidget {
  const _SamplerCalibrationSection({required this.report});

  final LiveLlmDiagnosticReport report;

  @override
  Widget build(BuildContext context) {
    final summaries = report.samplerCalibrationSummaries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'settings.live_llm_diag_sampler_calibration'.tr()),
        const SizedBox(height: 8),
        for (final summary in summaries)
          _SamplerCalibrationSummaryCard(summary: summary),
      ],
    );
  }
}

class _SamplerCalibrationSummaryCard extends StatelessWidget {
  const _SamplerCalibrationSummaryCard({required this.summary});

  final LiveLlmDiagnosticSamplerTrialSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidateTemperatures = summary.sortedCandidateTemperatures;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary.requestClass,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _SamplerInfoChip(
                  label: 'settings.live_llm_diag_sampler_trials'.tr(),
                  value: '${summary.trialCount}',
                ),
                _SamplerInfoChip(
                  label: 'settings.live_llm_diag_sampler_passed'.tr(),
                  value: '${summary.passedCount}/${summary.trialCount}',
                ),
                _SamplerInfoChip(
                  label: 'settings.live_llm_diag_sampler_candidates'.tr(),
                  value: candidateTemperatures
                      .map((temperature) => temperature.toString())
                      .join(', '),
                ),
              ],
            ),
            if (summary.hasQualityFlags) ...[
              const SizedBox(height: 8),
              Text(
                [
                  '${'settings.live_llm_diag_sampler_json_repairs'.tr()}: ${summary.jsonRepairEventCount}',
                  '${'settings.live_llm_diag_sampler_malformed'.tr()}: ${summary.malformedToolCallCount}',
                  '${'settings.live_llm_diag_sampler_edit_failures'.tr()}: ${summary.editApplyFailureCount}',
                  '${'settings.live_llm_diag_sampler_repetitions'.tr()}: ${summary.repetitionCount}',
                ].join(' • '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SamplerInfoChip extends StatelessWidget {
  const _SamplerInfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value'),
    );
  }
}

/// LL21: shows the recorded capability-profile revisions for the active model,
/// newest first, so the user can see when the last (idle) re-probe ran and
/// whether a capability change (possible model swap) was detected.
class _ProfileHistorySection extends StatelessWidget {
  const _ProfileHistorySection({required this.revisions});

  final List<ModelCapabilityProfileRevision> revisions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'settings.live_llm_diag_profile_history'.tr()),
        const SizedBox(height: 8),
        if (revisions.isEmpty)
          Text(
            'settings.live_llm_diag_profile_history_empty'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final revision in revisions)
            _ProfileRevisionCard(revision: revision),
      ],
    );
  }
}

class _ProfileRevisionCard extends StatelessWidget {
  const _ProfileRevisionCard({required this.revision});

  final ModelCapabilityProfileRevision revision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _profileSourceLabel(revision.source),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  _formatTimestamp(revision.probedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (revision.capabilityChangeDetected) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'settings.live_llm_diag_profile_capability_change'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _SamplerInfoChip(
                  label: 'settings.live_llm_diag_profile_tool_call_style'.tr(),
                  value: _enumName(revision.toolCallStyle),
                ),
                _SamplerInfoChip(
                  label: 'settings.live_llm_diag_profile_structured_output'.tr(),
                  value: _enumName(revision.structuredOutputSupport),
                ),
                _SamplerInfoChip(
                  label: 'settings.live_llm_diag_profile_edit_format'.tr(),
                  value: _enumName(revision.editFormatPreference),
                ),
                if (revision.usableContextTokens > 0)
                  _SamplerInfoChip(
                    label:
                        'settings.live_llm_diag_profile_context_tokens'.tr(),
                    value: '${revision.usableContextTokens}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _profileSourceLabel(String source) {
  return switch (source) {
    'initial' => 'settings.live_llm_diag_profile_source_initial'.tr(),
    'idle_re_probe' => 'settings.live_llm_diag_profile_source_idle_re_probe'.tr(),
    'calibrate' => 'settings.live_llm_diag_profile_source_calibrate'.tr(),
    'manual' => 'settings.live_llm_diag_profile_source_manual'.tr(),
    _ => 'settings.live_llm_diag_profile_source_probe'.tr(),
  };
}

String _enumName(Enum value) => value.name;

String _formatTimestamp(DateTime time) {
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _ProbeResultsSection extends StatelessWidget {
  const _ProbeResultsSection({required this.report});

  final LiveLlmDiagnosticReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'settings.live_llm_diag_probe_results'.tr()),
        const SizedBox(height: 8),
        for (final definition in LiveLlmDiagnosticService.probeDefinitions)
          _ProbeResultTile(
            definition: definition,
            result: _resultFor(definition.id),
          ),
      ],
    );
  }

  LiveLlmDiagnosticProbeResult? _resultFor(String id) {
    for (final result in report.results) {
      if (result.id == id) {
        return result;
      }
    }
    return null;
  }
}

class _ProbeResultTile extends StatelessWidget {
  const _ProbeResultTile({required this.definition, required this.result});

  final LiveLlmDiagnosticProbeDefinition definition;
  final LiveLlmDiagnosticProbeResult? result;

  @override
  Widget build(BuildContext context) {
    final probeResult = result;
    final status = probeResult?.status ?? LiveLlmDiagnosticStatus.pending;
    final theme = Theme.of(context);
    final details = probeResult?.details ?? '';
    final modelContent = probeResult?.modelContent ?? '';
    final toolCalls = probeResult?.toolCalls ?? const <String>[];

    return Card(
      child: ExpansionTile(
        leading: Icon(
          _statusIcon(status),
          color: _statusColor(context, status),
        ),
        title: Text(definition.titleKey.tr()),
        subtitle: Text(probeResult?.summary ?? definition.descriptionKey.tr()),
        trailing: status == LiveLlmDiagnosticStatus.running
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              definition.descriptionKey.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (probeResult != null)
            _ProbeMetaRow(
              status: status,
              elapsed: probeResult.elapsed,
              usage: probeResult.usage,
            ),
          if (toolCalls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final call in toolCalls)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(call),
                    ),
                ],
              ),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(details, style: theme.textTheme.bodySmall),
            ),
          ],
          if (modelContent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                modelContent,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kMonoFontFamily,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProbeMetaRow extends StatelessWidget {
  const _ProbeMetaRow({
    required this.status,
    required this.elapsed,
    required this.usage,
  });

  final LiveLlmDiagnosticStatus status;
  final Duration elapsed;
  final LiveLlmDiagnosticTokenUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '${_statusLabel(status)} • ${_formatDuration(elapsed)} • '
        '↑${usage.promptTokens} ↓${usage.completionTokens} Σ${usage.totalTokens}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 184,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color ?? theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _statusIcon(LiveLlmDiagnosticStatus status) {
  return switch (status) {
    LiveLlmDiagnosticStatus.pending => Icons.radio_button_unchecked,
    LiveLlmDiagnosticStatus.running => Icons.sync_outlined,
    LiveLlmDiagnosticStatus.passed => Icons.check_circle_outline,
    LiveLlmDiagnosticStatus.warning => Icons.warning_amber_outlined,
    LiveLlmDiagnosticStatus.failed => Icons.error_outline,
    LiveLlmDiagnosticStatus.skipped => Icons.remove_circle_outline,
  };
}

Color _statusColor(BuildContext context, LiveLlmDiagnosticStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    LiveLlmDiagnosticStatus.pending => scheme.outline,
    LiveLlmDiagnosticStatus.running => scheme.primary,
    LiveLlmDiagnosticStatus.passed => Colors.green.shade700,
    LiveLlmDiagnosticStatus.warning => Colors.orange.shade800,
    LiveLlmDiagnosticStatus.failed => scheme.error,
    LiveLlmDiagnosticStatus.skipped => scheme.onSurfaceVariant,
  };
}

String _statusLabel(LiveLlmDiagnosticStatus status) {
  return switch (status) {
    LiveLlmDiagnosticStatus.pending =>
      'settings.live_llm_diag_status_pending'.tr(),
    LiveLlmDiagnosticStatus.running =>
      'settings.live_llm_diag_status_running'.tr(),
    LiveLlmDiagnosticStatus.passed =>
      'settings.live_llm_diag_status_passed'.tr(),
    LiveLlmDiagnosticStatus.warning =>
      'settings.live_llm_diag_status_warning'.tr(),
    LiveLlmDiagnosticStatus.failed =>
      'settings.live_llm_diag_status_failed'.tr(),
    LiveLlmDiagnosticStatus.skipped =>
      'settings.live_llm_diag_status_skipped'.tr(),
  };
}

String _formatDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) {
    return '${milliseconds}ms';
  }
  return '${(milliseconds / 1000).toStringAsFixed(1)}s';
}
