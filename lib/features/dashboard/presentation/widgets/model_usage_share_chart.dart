import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/model_usage_stats.dart';
import 'model_usage_theme.dart';

/// A 100%-stacked bar of token share across models, with a legend beneath.
///
/// Hand-painted rather than pulling in a chart package: the shape is a single
/// row of rectangles, and the repo already draws its activity heatmap this way.
class ModelUsageShareChart extends StatelessWidget {
  const ModelUsageShareChart({super.key, required this.stats});

  final ModelUsageStats stats;

  static const double _barHeight = 14;

  @override
  Widget build(BuildContext context) {
    final total = stats.totalTokens;
    if (total <= 0) return const SizedBox.shrink();

    final segments = <_ShareSegment>[
      for (var index = 0; index < stats.models.length; index++)
        _ShareSegment(
          entry: stats.models[index],
          color: ModelUsageTheme.seriesColor(context, index),
          share: stats.shareOf(stats.models[index]),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(context.radii.xs),
          child: CustomPaint(
            size: const Size(double.infinity, _barHeight),
            painter: _ShareBarPainter(
              segments: segments,
              background: context.appColors.surface3,
            ),
          ),
        ),
        SizedBox(height: context.space.lg),
        Wrap(
          spacing: context.space.xl,
          runSpacing: context.space.md,
          children: [
            for (final segment in segments) _LegendItem(segment: segment),
          ],
        ),
      ],
    );
  }
}

class _ShareSegment {
  const _ShareSegment({
    required this.entry,
    required this.color,
    required this.share,
  });

  final ModelUsageEntry entry;
  final Color color;
  final double share;
}

class _ShareBarPainter extends CustomPainter {
  const _ShareBarPainter({required this.segments, required this.background});

  final List<_ShareSegment> segments;
  final Color background;

  /// Minimum width so a fraction-of-a-percent model stays visible as a sliver
  /// rather than collapsing into nothing.
  static const double _minSegmentWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    var x = 0.0;
    for (final segment in segments) {
      if (x >= size.width) break;
      final width = (segment.share * size.width).clamp(
        _minSegmentWidth,
        size.width - x,
      );
      canvas.drawRect(
        Rect.fromLTWH(x, 0, width, size.height),
        Paint()..color = segment.color,
      );
      x += width;
    }
  }

  @override
  bool shouldRepaint(_ShareBarPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.background != background;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.segment});

  final _ShareSegment segment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: segment.color,
            borderRadius: BorderRadius.circular(context.radii.xs),
          ),
        ),
        SizedBox(width: context.space.md),
        Text(segment.entry.label, style: theme.textTheme.bodySmall),
        SizedBox(width: context.space.sm),
        Text(
          ModelUsageTheme.percent(segment.share),
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
      ],
    );
  }
}
