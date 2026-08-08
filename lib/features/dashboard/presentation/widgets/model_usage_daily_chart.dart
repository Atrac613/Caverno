import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/model_usage_stats.dart';
import 'model_usage_theme.dart';

/// Stacked columns of tokens per day, one segment per model.
///
/// Days with no activity still occupy a slot, so a gap in usage reads as a gap
/// rather than being silently compressed away.
class ModelUsageDailyChart extends StatelessWidget {
  const ModelUsageDailyChart({super.key, required this.stats});

  final ModelUsageStats stats;

  static const double _height = 132;

  @override
  Widget build(BuildContext context) {
    if (stats.daily.isEmpty) return const SizedBox.shrink();

    final colorByKey = <String, Color>{
      for (var index = 0; index < stats.models.length; index++)
        stats.models[index].key: ModelUsageTheme.seriesColor(context, index),
    };
    final orderedKeys = stats.models
        .map((entry) => entry.key)
        .toList(growable: false);
    final columns = _buildColumns(stats.daily);
    final peak = columns.fold<int>(
      0,
      (max, column) => column.totalTokens > max ? column.totalTokens : max,
    );

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'dashboard.model_usage.daily'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            Text(
              ModelUsageTheme.compactTokens(peak),
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: context.space.md),
        CustomPaint(
          size: const Size(double.infinity, _height),
          painter: _DailyColumnsPainter(
            columns: columns,
            orderedKeys: orderedKeys,
            colorByKey: colorByKey,
            peak: peak,
            baseline: context.appColors.hairline,
          ),
        ),
        SizedBox(height: context.space.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDay(context, columns.first.dayNumber),
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
            Text(
              _formatDay(context, columns.last.dayNumber),
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Fills gaps between the first and last recorded day so the x axis is
  /// linear in time.
  List<ModelUsageDaySlice> _buildColumns(List<ModelUsageDaySlice> slices) {
    final byDay = {for (final slice in slices) slice.dayNumber: slice};
    final first = slices.first.dayNumber;
    final last = slices.last.dayNumber;
    return [
      for (var day = first; day <= last; day++)
        byDay[day] ?? ModelUsageDaySlice(dayNumber: day),
    ];
  }

  String _formatDay(BuildContext context, int dayNumber) {
    final day = DateTime.fromMillisecondsSinceEpoch(
      dayNumber * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return DateFormat.MMMd(
      context.locale.toString(),
    ).format(DateTime(day.year, day.month, day.day));
  }
}

class _DailyColumnsPainter extends CustomPainter {
  const _DailyColumnsPainter({
    required this.columns,
    required this.orderedKeys,
    required this.colorByKey,
    required this.peak,
    required this.baseline,
  });

  final List<ModelUsageDaySlice> columns;
  final List<String> orderedKeys;
  final Map<String, Color> colorByKey;
  final int peak;
  final Color baseline;

  static const double _maxGap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
    if (peak <= 0 || columns.isEmpty) return;

    final slotWidth = size.width / columns.length;
    // Gap shrinks with the slot so a 90-day range still renders solid columns.
    final gap = (slotWidth * 0.2).clamp(0.0, _maxGap);
    final barWidth = (slotWidth - gap).clamp(1.0, slotWidth);

    for (var index = 0; index < columns.length; index++) {
      final column = columns[index];
      if (column.totalTokens <= 0) continue;
      final left = index * slotWidth + gap / 2;
      var bottom = size.height;

      for (final key in orderedKeys) {
        final tokens = column.tokensByModelKey[key] ?? 0;
        if (tokens <= 0) continue;
        final height = (tokens / peak) * size.height;
        canvas.drawRect(
          Rect.fromLTWH(left, bottom - height, barWidth, height),
          Paint()..color = colorByKey[key] ?? baseline,
        );
        bottom -= height;
      }
    }
  }

  @override
  bool shouldRepaint(_DailyColumnsPainter oldDelegate) =>
      oldDelegate.columns != columns ||
      oldDelegate.peak != peak ||
      oldDelegate.colorByKey != colorByKey;
}
