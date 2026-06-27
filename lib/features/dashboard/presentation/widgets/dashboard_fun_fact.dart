import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

class DashboardFunFact extends StatelessWidget {
  const DashboardFunFact({super.key, required this.multiple});

  final double? multiple;

  @override
  Widget build(BuildContext context) {
    final value = multiple;
    if (value == null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        SizedBox(width: context.space.md),
        Expanded(
          child: Text(
            'dashboard.fun_fact'.tr(
              namedArgs: {'multiple': _formatMultiple(value)},
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatMultiple(double value) {
    if (value >= 100) {
      return value.round().toString();
    }
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }
}
