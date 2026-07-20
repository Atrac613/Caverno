import 'package:flutter/material.dart';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import '../../../../core/security/tool_perimeter_context.dart';

/// SEC1 (Local Agent Data Perimeter) slice 6: a compact one-line badge that
/// shows a pending tool call's security perimeter — capability class, risk
/// tier, whether it mutates the host or uses the network, and whether it
/// produces untrusted content — inside the approval UI, so the user sees the
/// action's context before approving it (acceptance criterion 1).
///
/// Display-only: it classifies via the pure [ToolPerimeterClassifier]; it does
/// not gate, cache, or re-rank any approval, so it cannot weaken an existing
/// default (criterion 3).
class ToolPerimeterSummary extends StatelessWidget {
  const ToolPerimeterSummary({
    super.key,
    required this.toolName,
    this.arguments = const <String, dynamic>{},
    this.isMcpTool = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final String toolName;
  final Map<String, dynamic> arguments;
  final bool isMcpTool;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perimeter = const ToolPerimeterClassifier().classify(
      toolName,
      arguments: arguments,
      isMcpTool: isMcpTool,
    );
    final color = switch (perimeter.capability.riskTier) {
      ToolRiskTier.high => theme.colorScheme.error,
      ToolRiskTier.medium => theme.colorScheme.tertiary,
      ToolRiskTier.low => theme.colorScheme.onSurfaceVariant,
    };
    final icon = switch (perimeter.capability.riskTier) {
      ToolRiskTier.high => Icons.gpp_maybe_rounded,
      ToolRiskTier.medium => Icons.shield_rounded,
      ToolRiskTier.low => Icons.shield_outlined,
    };
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              perimeter.summary,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
