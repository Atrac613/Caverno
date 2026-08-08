import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/model_usage_stats.dart';
import 'model_usage_theme.dart';

/// One row per model+endpoint: share, tokens, and an input/output split bar.
///
/// Rows with named recovery paths expand to show what those retries cost.
class ModelUsageList extends StatelessWidget {
  const ModelUsageList({super.key, required this.stats});

  final ModelUsageStats stats;

  /// Below this, a truncation rate is noise rather than a signal worth a badge.
  static const double _truncationWarningThreshold = 0.05;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < stats.models.length; index++)
          _ModelRow(
            entry: stats.models[index],
            share: stats.shareOf(stats.models[index]),
            color: ModelUsageTheme.seriesColor(context, index),
            labels: stats.labelsByModelKey[stats.models[index].key] ?? const [],
            showTruncationWarning:
                (stats.models[index].truncationRate ?? 0) >=
                _truncationWarningThreshold,
          ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.entry,
    required this.share,
    required this.color,
    required this.labels,
    required this.showTruncationWarning,
  });

  final ModelUsageEntry entry;
  final double share;
  final Color color;
  final List<ModelUsageEntry> labels;
  final bool showTruncationWarning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final endpoint = entry.endpointId;
    final latency = entry.averageLatencyMs;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(context.radii.xs),
          ),
        ),
        SizedBox(width: context.space.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      entry.label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (showTruncationWarning) ...[
                    SizedBox(width: context.space.md),
                    _TruncationBadge(entry: entry),
                  ],
                ],
              ),
              if (endpoint.isNotEmpty)
                Text(
                  endpoint,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: appColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(width: context.space.lg),
        _MetricColumn(
          value: ModelUsageTheme.compactTokens(entry.totalTokens),
          caption: 'dashboard.model_usage.tokens'.tr(),
        ),
        SizedBox(width: context.space.xl),
        _MetricColumn(
          value: ModelUsageTheme.percent(share),
          caption: 'dashboard.model_usage.share'.tr(),
        ),
        SizedBox(width: context.space.xl),
        _MetricColumn(
          value: '${entry.requestCount}',
          caption: 'dashboard.model_usage.requests'.tr(),
        ),
        SizedBox(width: context.space.xl),
        _MetricColumn(
          value: latency == null ? '—' : ModelUsageTheme.duration(latency),
          caption: 'dashboard.model_usage.latency'.tr(),
        ),
      ],
    );

    final body = Padding(
      padding: EdgeInsets.symmetric(vertical: context.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          SizedBox(height: context.space.md),
          _InputOutputBar(entry: entry, color: color),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: appColors.hairline, width: 0.5),
        ),
      ),
      child: labels.isEmpty
          ? body
          : Theme(
              // The default divider would double up with the row's own border.
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.only(
                  left: context.space.xxl,
                  bottom: context.space.lg,
                ),
                title: body,
                children: [for (final label in labels) _LabelRow(entry: label)],
              ),
            ),
    );
  }
}

/// Input vs output split, the two figures the API always reports separately.
class _InputOutputBar extends StatelessWidget {
  const _InputOutputBar({required this.entry, required this.color});

  final ModelUsageEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final total = entry.promptTokens + entry.completionTokens;
    if (total <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final inputFlex = entry.promptTokens;
    final outputFlex = entry.completionTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(context.radii.xs),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                if (inputFlex > 0)
                  Expanded(
                    flex: inputFlex,
                    child: ColoredBox(color: color.withValues(alpha: 0.45)),
                  ),
                if (outputFlex > 0)
                  Expanded(
                    flex: outputFlex,
                    child: ColoredBox(color: color),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: context.space.sm),
        Text(
          '${'dashboard.model_usage.input'.tr()} '
          '${ModelUsageTheme.compactTokens(entry.promptTokens)}'
          '   ·   '
          '${'dashboard.model_usage.output'.tr()} '
          '${ModelUsageTheme.compactTokens(entry.completionTokens)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.entry});

  final ModelUsageEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ),
          Text(
            ModelUsageTheme.compactTokens(entry.totalTokens),
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          SizedBox(width: context.space.lg),
          SizedBox(
            width: 48,
            child: Text(
              '${entry.requestCount}',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TruncationBadge extends StatelessWidget {
  const _TruncationBadge({required this.entry});

  final ModelUsageEntry entry;

  @override
  Widget build(BuildContext context) {
    final rate = entry.truncationRate ?? 0;
    return Tooltip(
      message: 'dashboard.model_usage.truncated_tooltip'.tr(
        namedArgs: {
          'count': '${entry.truncatedCount}',
          'percent': ModelUsageTheme.percent(rate),
        },
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.space.md,
          vertical: context.space.xxs,
        ),
        decoration: BoxDecoration(
          color: context.appColors.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(context.radii.xs),
        ),
        child: Text(
          'dashboard.model_usage.truncated'.tr(),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: context.appColors.warning),
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({required this.value, required this.caption});

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
