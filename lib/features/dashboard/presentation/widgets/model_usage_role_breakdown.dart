import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../chat/domain/entities/model_usage_role.dart';
import '../../domain/entities/model_usage_stats.dart';
import 'model_usage_theme.dart';

/// Where the tokens actually went: chat, memory extraction, planning, and the
/// rest.
///
/// A `unknown` slice here is a defect signal, not a feature the user ran — it
/// means some call site never claimed a role — so it is labelled as such.
class ModelUsageRoleBreakdown extends StatelessWidget {
  const ModelUsageRoleBreakdown({super.key, required this.stats});

  final ModelUsageStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.roles.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final total = stats.totalTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'dashboard.model_usage.by_role'.tr(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.appColors.textSecondary,
          ),
        ),
        SizedBox(height: context.space.lg),
        for (var index = 0; index < stats.roles.length; index++)
          _RoleRow(
            entry: stats.roles[index],
            share: total <= 0 ? 0 : stats.roles[index].totalTokens / total,
            color: ModelUsageTheme.seriesColor(context, index),
          ),
      ],
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.entry,
    required this.share,
    required this.color,
  });

  final ModelUsageEntry entry;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = ModelUsageRole.fromName(entry.key);
    final isUnattributed = role == ModelUsageRole.unknown;

    return Padding(
      padding: EdgeInsets.only(bottom: context.space.md),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'dashboard.model_usage.role.${role.name}'.tr(),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isUnattributed ? context.appColors.warning : null,
                    ),
                  ),
                ),
                if (isUnattributed) ...[
                  SizedBox(width: context.space.xs),
                  Tooltip(
                    message: 'dashboard.model_usage.role_unknown_hint'.tr(),
                    child: Icon(
                      Icons.info_outline,
                      size: 12,
                      color: context.appColors.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: context.space.lg),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(context.radii.xs),
              child: SizedBox(
                height: 8,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    // A share too small to see still gets a visible sliver.
                    widthFactor: share.clamp(0.01, 1.0),
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: context.space.lg),
          SizedBox(
            width: 68,
            child: Text(
              ModelUsageTheme.compactTokens(entry.totalTokens),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.appColors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
