import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/dashboard_stats.dart';

class ActivityHeatmapView extends StatelessWidget {
  const ActivityHeatmapView({super.key, required this.heatmap});

  final ActivityHeatmap heatmap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appColors.surface2,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: appColors.hairline, width: 0.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(context.space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'dashboard.activity'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: context.space.xl),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WeekdayLabels(cellSize: _cellSize, gap: context.space.xs),
                  SizedBox(width: context.space.md),
                  _HeatmapGrid(
                    heatmap: heatmap,
                    cellSize: _cellSize,
                    gap: context.space.xs,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const double _cellSize = 11;
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels({required this.cellSize, required this.gap});

  final double cellSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final labels = _weekdayLabels(context);
    return Column(
      children: [
        for (var row = 0; row < labels.length; row++)
          SizedBox(
            height: cellSize + (row == labels.length - 1 ? 0 : gap),
            width: 24,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                labels[row],
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.appColors.textMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<String> _weekdayLabels(BuildContext context) {
    final formatter = DateFormat.E(context.locale.toString());
    return [
      for (var offset = 0; offset < DateTime.daysPerWeek; offset++)
        formatter.format(DateTime(2026, 1, 4 + offset)).characters.first,
    ];
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({
    required this.heatmap,
    required this.cellSize,
    required this.gap,
  });

  final ActivityHeatmap heatmap;
  final double cellSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final dayCount = heatmap.dailyCounts.length;
    final columnCount = (dayCount / DateTime.daysPerWeek)
        .ceil()
        .clamp(1, 80)
        .toInt();
    return Row(
      children: [
        for (var column = 0; column < columnCount; column++) ...[
          Column(
            children: [
              for (var row = 0; row < DateTime.daysPerWeek; row++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: row == DateTime.daysPerWeek - 1 ? 0 : gap,
                  ),
                  child: _HeatmapCell(
                    heatmap: heatmap,
                    index: column * DateTime.daysPerWeek + row,
                    cellSize: cellSize,
                  ),
                ),
            ],
          ),
          if (column != columnCount - 1) SizedBox(width: gap),
        ],
      ],
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.heatmap,
    required this.index,
    required this.cellSize,
  });

  final ActivityHeatmap heatmap;
  final int index;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    if (index >= heatmap.dailyCounts.length) {
      return SizedBox(width: cellSize, height: cellSize);
    }
    final count = heatmap.dailyCounts[index];
    final bucket = heatmap.dailyBuckets[index];
    final day = DateTime(
      heatmap.startDay.year,
      heatmap.startDay.month,
      heatmap.startDay.day + index,
    );
    return Tooltip(
      message: 'dashboard.activity_tooltip'.tr(
        namedArgs: {
          'date': DateFormat.yMMMd(context.locale.toString()).format(day),
          'count': count.toString(),
        },
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _bucketColor(context, bucket),
          borderRadius: BorderRadius.circular(context.radii.xs),
        ),
        child: SizedBox(width: cellSize, height: cellSize),
      ),
    );
  }

  Color _bucketColor(BuildContext context, int bucket) {
    if (bucket <= 0) {
      return context.appColors.surface3;
    }
    final alpha = switch (bucket) {
      1 => 0.25,
      2 => 0.45,
      3 => 0.7,
      _ => 1.0,
    };
    return Theme.of(context).colorScheme.primary.withValues(alpha: alpha);
  }
}
