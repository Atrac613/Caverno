import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/dashboard_stats.dart';

class ActivityHeatmapView extends StatefulWidget {
  const ActivityHeatmapView({super.key, required this.heatmap});

  final ActivityHeatmap heatmap;

  @override
  State<ActivityHeatmapView> createState() => _ActivityHeatmapViewState();
}

class _ActivityHeatmapViewState extends State<ActivityHeatmapView> {
  static const double _weekdayLabelWidth = 24;

  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _defaultSelectedIndex(widget.heatmap);
  }

  @override
  void didUpdateWidget(covariant ActivityHeatmapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heatmap != widget.heatmap) {
      final stillValid =
          _selectedIndex >= 0 &&
          _selectedIndex < widget.heatmap.dailyCounts.length;
      if (!stillValid) {
        _selectedIndex = _defaultSelectedIndex(widget.heatmap);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final gap = context.space.xs;
    final heatmap = widget.heatmap;
    final dayCount = heatmap.dailyCounts.length;
    final columnCount = (dayCount / DateTime.daysPerWeek)
        .ceil()
        .clamp(1, 80)
        .toInt();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: appColors.surface2,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: appColors.hairline, width: 0.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(context.space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'dashboard.activity_past_year'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'dashboard.activity_unit'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: appColors.textMuted,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.space.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final labelGap = context.space.md;
                final gridWidth =
                    (constraints.maxWidth - _weekdayLabelWidth - labelGap)
                        .clamp(0.0, double.infinity);
                final gapTotal = gap * (columnCount - 1);
                final cellSize = columnCount <= 0
                    ? 0.0
                    : ((gridWidth - gapTotal) / columnCount).clamp(
                        0.0,
                        double.infinity,
                      );
                // Shared extent so month labels and week columns stay on the
                // same equal-spaced horizontal grid.
                final gridExtent = columnCount * cellSize + gapTotal;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WeekdayLabels(
                      cellSize: cellSize,
                      gap: gap,
                      topInset: _monthLabelHeight(context),
                      width: _weekdayLabelWidth,
                    ),
                    SizedBox(width: labelGap),
                    SizedBox(
                      width: gridExtent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MonthLabels(
                            heatmap: heatmap,
                            columnCount: columnCount,
                            cellSize: cellSize,
                            gap: gap,
                          ),
                          _HeatmapGrid(
                            heatmap: heatmap,
                            columnCount: columnCount,
                            cellSize: cellSize,
                            gap: gap,
                            selectedIndex: _selectedIndex,
                            onSelect: (index) {
                              setState(() => _selectedIndex = index);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: context.space.lg),
            _Footer(
              heatmap: heatmap,
              selectedIndex: _selectedIndex,
              cellSize: 11,
            ),
          ],
        ),
      ),
    );
  }

  static double _monthLabelHeight(BuildContext context) {
    final fontSize = Theme.of(context).textTheme.labelSmall?.fontSize ?? 11;
    return fontSize + context.space.sm;
  }

  static int _defaultSelectedIndex(ActivityHeatmap heatmap) {
    if (heatmap.dailyCounts.isEmpty) {
      return 0;
    }
    for (var index = heatmap.dailyCounts.length - 1; index >= 0; index--) {
      if (heatmap.dailyCounts[index] > 0) {
        return index;
      }
    }
    return heatmap.dailyCounts.length - 1;
  }
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels({
    required this.cellSize,
    required this.gap,
    required this.topInset,
    required this.width,
  });

  final double cellSize;
  final double gap;
  final double topInset;
  final double width;

  @override
  Widget build(BuildContext context) {
    final labels = _weekdayLabels(context);
    return Column(
      children: [
        SizedBox(height: topInset),
        for (var row = 0; row < labels.length; row++)
          SizedBox(
            height: cellSize + (row == labels.length - 1 ? 0 : gap),
            width: width,
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

class _MonthLabels extends StatelessWidget {
  const _MonthLabels({
    required this.heatmap,
    required this.columnCount,
    required this.cellSize,
    required this.gap,
  });

  final ActivityHeatmap heatmap;
  final int columnCount;
  final double cellSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.MMM(context.locale.toString());
    final labels = List<String?>.filled(columnCount, null);
    int? previousMonth;
    for (var column = 0; column < columnCount; column++) {
      final index = column * DateTime.daysPerWeek;
      if (index >= heatmap.dailyCounts.length) {
        continue;
      }
      final day = _dayAt(heatmap, index);
      if (previousMonth == day.month) {
        continue;
      }
      labels[column] = formatter.format(day);
      previousMonth = day.month;
    }

    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: context.appColors.textMuted,
    );
    final step = cellSize + gap;

    // Equal-width week columns (same rhythm as the cells below). Label text
    // may paint into following empty columns up to the next month label.
    return SizedBox(
      height: _ActivityHeatmapViewState._monthLabelHeight(context),
      child: Row(
        children: [
          for (var column = 0; column < columnCount; column++) ...[
            SizedBox(
              width: cellSize,
              child: labels[column] == null
                  ? const SizedBox.shrink()
                  : OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: cellSize,
                      maxWidth: _overflowWidth(
                        labels: labels,
                        startColumn: column,
                        step: step,
                      ),
                      child: Text(
                        labels[column]!,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: style,
                      ),
                    ),
            ),
            if (column != columnCount - 1) SizedBox(width: gap),
          ],
        ],
      ),
    );
  }

  double _overflowWidth({
    required List<String?> labels,
    required int startColumn,
    required double step,
  }) {
    var endColumn = columnCount;
    for (var column = startColumn + 1; column < columnCount; column++) {
      if (labels[column] != null) {
        endColumn = column;
        break;
      }
    }
    final weeks = (endColumn - startColumn).clamp(1, columnCount);
    return weeks * step - gap;
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({
    required this.heatmap,
    required this.columnCount,
    required this.cellSize,
    required this.gap,
    required this.selectedIndex,
    required this.onSelect,
  });

  final ActivityHeatmap heatmap;
  final int columnCount;
  final double cellSize;
  final double gap;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
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
                    selected:
                        selectedIndex == column * DateTime.daysPerWeek + row,
                    onSelect: onSelect,
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
    required this.selected,
    required this.onSelect,
  });

  final ActivityHeatmap heatmap;
  final int index;
  final double cellSize;
  final bool selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (index >= heatmap.dailyCounts.length) {
      return SizedBox(width: cellSize, height: cellSize);
    }
    final count = heatmap.dailyCounts[index];
    final bucket = heatmap.dailyBuckets[index];
    final day = _dayAt(heatmap, index);
    final dateLabel = DateFormat.yMMMd(context.locale.toString()).format(day);

    return Tooltip(
      message: 'dashboard.activity_tooltip'.tr(
        namedArgs: {'date': dateLabel, 'count': count.toString()},
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onSelect(index),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _bucketColor(context, bucket),
              borderRadius: BorderRadius.circular(
                context.radii.xs.clamp(1.0, cellSize / 3),
              ),
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: (cellSize * 0.12).clamp(1.0, 1.5),
                    )
                  : null,
            ),
            child: SizedBox(width: cellSize, height: cellSize),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.heatmap,
    required this.selectedIndex,
    required this.cellSize,
  });

  final ActivityHeatmap heatmap;
  final int selectedIndex;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: context.appColors.textMuted,
    );
    final summary = _selectedSummary(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            summary,
            style: muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text('dashboard.activity_less'.tr(), style: muted),
        SizedBox(width: context.space.sm),
        for (var bucket = 0; bucket <= 4; bucket++) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: _bucketColor(context, bucket),
              borderRadius: BorderRadius.circular(context.radii.xs),
            ),
            child: SizedBox(width: cellSize, height: cellSize),
          ),
          if (bucket != 4) SizedBox(width: context.space.xs),
        ],
        SizedBox(width: context.space.sm),
        Text('dashboard.activity_more'.tr(), style: muted),
      ],
    );
  }

  String _selectedSummary(BuildContext context) {
    if (heatmap.dailyCounts.isEmpty ||
        selectedIndex < 0 ||
        selectedIndex >= heatmap.dailyCounts.length) {
      return '';
    }
    final day = _dayAt(heatmap, selectedIndex);
    final dateLabel = DateFormat.yMMMd(context.locale.toString()).format(day);
    return 'dashboard.activity_selected'.tr(
      namedArgs: {
        'date': dateLabel,
        'count': heatmap.dailyCounts[selectedIndex].toString(),
      },
    );
  }
}

DateTime _dayAt(ActivityHeatmap heatmap, int index) {
  return DateTime(
    heatmap.startDay.year,
    heatmap.startDay.month,
    heatmap.startDay.day + index,
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
