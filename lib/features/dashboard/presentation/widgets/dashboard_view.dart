import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../providers/dashboard_providers.dart';
import 'activity_heatmap_view.dart';
import 'dashboard_fun_fact.dart';
import 'dashboard_range_selector.dart';
import 'dashboard_stat_grid.dart';

class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final hasAnyActivity =
        stats.messageCount > 0 || stats.longestStreakDays > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(context.space.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DashboardHeader(isCompact: constraints.maxWidth < 640),
                  SizedBox(height: context.space.xxl),
                  if (!hasAnyActivity)
                    const _DashboardEmptyState()
                  else ...[
                    DashboardStatGrid(stats: stats),
                    SizedBox(height: context.space.xl),
                    ActivityHeatmapView(heatmap: stats.heatmap),
                    SizedBox(height: context.space.xl),
                    DashboardFunFact(multiple: stats.funFactMultiple),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      'dashboard.title'.tr(),
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          SizedBox(height: context.space.lg),
          const DashboardRangeSelector(),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        const DashboardRangeSelector(),
      ],
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.space.xxxl * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            SizedBox(height: context.space.xl),
            Text(
              'dashboard.empty'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
