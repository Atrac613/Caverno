import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/model_usage_stats.dart';
import '../providers/dashboard_providers.dart';
import 'model_usage_daily_chart.dart';
import 'model_usage_list.dart';
import 'model_usage_role_breakdown.dart';
import 'model_usage_share_chart.dart';
import 'model_usage_theme.dart';

/// Per-model token usage for the dashboard's selected range.
///
/// Accounting starts when this feature ships, so an existing install shows the
/// empty state until its next request rather than back-filling history.
class ModelUsageSection extends ConsumerWidget {
  const ModelUsageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref
        .watch(modelUsageStatsProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'dashboard.model_usage.title'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: context.space.xl),
          if (stats == null || stats.isEmpty)
            const _EmptyState()
          else
            _Content(stats: stats),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.stats});

  final ModelUsageStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(stats: stats),
        SizedBox(height: context.space.xl),
        ModelUsageShareChart(stats: stats),
        SizedBox(height: context.space.xxl),
        ModelUsageDailyChart(stats: stats),
        SizedBox(height: context.space.xxl),
        ModelUsageRoleBreakdown(stats: stats),
        SizedBox(height: context.space.lg),
        ModelUsageList(stats: stats),
      ],
    );
  }
}

/// Totals across the range. Values the provider never reported render as "—"
/// rather than 0, so a local llama.cpp endpoint is not misread as a 0% cache
/// hit rate.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.stats});

  final ModelUsageStats stats;

  @override
  Widget build(BuildContext context) {
    final cacheHitRate = stats.cacheHitRate;
    final reasoningTokens = stats.totalReasoningTokens;

    return Wrap(
      spacing: context.space.xxl,
      runSpacing: context.space.lg,
      children: [
        _SummaryTile(
          label: 'dashboard.model_usage.input'.tr(),
          value: ModelUsageTheme.compactTokens(stats.totalPromptTokens),
        ),
        _SummaryTile(
          label: 'dashboard.model_usage.output'.tr(),
          value: ModelUsageTheme.compactTokens(stats.totalCompletionTokens),
        ),
        _SummaryTile(
          label: 'dashboard.model_usage.requests'.tr(),
          value: '${stats.totalRequestCount}',
        ),
        _SummaryTile(
          label: 'dashboard.model_usage.cache_hit_rate'.tr(),
          value: cacheHitRate == null
              ? '—'
              : ModelUsageTheme.percent(cacheHitRate),
        ),
        _SummaryTile(
          label: 'dashboard.model_usage.reasoning'.tr(),
          value: reasoningTokens <= 0
              ? '—'
              : ModelUsageTheme.compactTokens(reasoningTokens),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        SizedBox(height: context.space.xxs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Text(
      'dashboard.model_usage.empty'.tr(),
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.appColors.textMuted),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Material(
      color: appColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radii.md),
        side: BorderSide(color: appColors.hairline, width: 0.5),
      ),
      child: Padding(padding: EdgeInsets.all(context.space.xl), child: child),
    );
  }
}
