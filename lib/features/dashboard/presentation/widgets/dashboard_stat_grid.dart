import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/entities/dashboard_stats.dart';
import 'dashboard_stat_card.dart';

class DashboardStatGrid extends StatelessWidget {
  const DashboardStatGrid({super.key, required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final items = _items(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columnCount = width >= 960
            ? 4
            : width >= 560
            ? 2
            : 1;
        final spacing = context.space.lg;
        final itemWidth = (width - spacing * (columnCount - 1)) / columnCount;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth.isFinite ? itemWidth : 240,
                height: 108,
                child: DashboardStatCard(
                  label: item.label,
                  value: item.value,
                  icon: item.icon,
                ),
              ),
          ],
        );
      },
    );
  }

  List<_DashboardStatItem> _items(BuildContext context) {
    return [
      _DashboardStatItem(
        label: 'dashboard.sessions'.tr(),
        value: _formatCompact(context, stats.sessionCount),
        icon: Icons.forum_outlined,
      ),
      _DashboardStatItem(
        label: 'dashboard.messages'.tr(),
        value: _formatCompact(context, stats.messageCount),
        icon: Icons.chat_bubble_outline,
      ),
      _DashboardStatItem(
        label: 'dashboard.total_tokens'.tr(),
        value: _formatCompact(context, stats.totalTokens),
        icon: Icons.generating_tokens_outlined,
      ),
      _DashboardStatItem(
        label: 'dashboard.active_days'.tr(),
        value: _formatCompact(context, stats.activeDays),
        icon: Icons.calendar_today_outlined,
      ),
      _DashboardStatItem(
        label: 'dashboard.current_streak'.tr(),
        value: 'dashboard.streak_days'.tr(
          namedArgs: {'count': stats.currentStreakDays.toString()},
        ),
        icon: Icons.local_fire_department_outlined,
      ),
      _DashboardStatItem(
        label: 'dashboard.longest_streak'.tr(),
        value: 'dashboard.streak_days'.tr(
          namedArgs: {'count': stats.longestStreakDays.toString()},
        ),
        icon: Icons.emoji_events_outlined,
      ),
      _DashboardStatItem(
        label: 'dashboard.peak_hour'.tr(),
        value: _formatPeakHour(context, stats.peakHour),
        icon: Icons.schedule_outlined,
      ),
    ];
  }

  String _formatCompact(BuildContext context, int value) {
    return NumberFormat.compact(
      locale: context.locale.toString(),
    ).format(value);
  }

  String _formatPeakHour(BuildContext context, int? hour) {
    if (hour == null) {
      return '-';
    }
    return DateFormat.j(
      context.locale.toString(),
    ).format(DateTime(2000, 1, 1, hour));
  }
}

class _DashboardStatItem {
  const _DashboardStatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}
