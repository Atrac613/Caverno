import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/dashboard_stats.dart';
import '../providers/dashboard_providers.dart';

class DashboardRangeSelector extends ConsumerWidget {
  const DashboardRangeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRange = ref.watch(dashboardRangeProvider);
    return SegmentedButton<DashboardRange>(
      key: const ValueKey('dashboard-range-selector'),
      showSelectedIcon: false,
      selected: {selectedRange},
      segments: [
        ButtonSegment(
          value: DashboardRange.all,
          label: Text('dashboard.range_all'.tr()),
        ),
        ButtonSegment(
          value: DashboardRange.last30Days,
          label: Text('dashboard.range_30d'.tr()),
        ),
        ButtonSegment(
          value: DashboardRange.last7Days,
          label: Text('dashboard.range_7d'.tr()),
        ),
      ],
      onSelectionChanged: (selection) {
        ref.read(dashboardRangeProvider.notifier).setRange(selection.single);
      },
    );
  }
}
