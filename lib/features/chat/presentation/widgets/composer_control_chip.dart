import 'package:flutter/material.dart';

/// Pill-shaped control in the composer's action bar (assistant mode, approval
/// mode, worktree mode, model). Shared so every chip keeps the same padding,
/// radius and chevron, whichever widget owns the control behind it.
///
/// [maxLabelWidth] bounds labels that come from data rather than a fixed
/// vocabulary — a model id can be arbitrarily long — and ellipsizes past it.
///
/// [secondaryLabel] renders a second, de-emphasised value after the label, for
/// a chip that carries two settings at once (model + reasoning effort).
Widget buildComposerControlChip({
  required ThemeData theme,
  required IconData icon,
  required String label,
  String? secondaryLabel,
  Key? key,
  bool showChevron = true,
  double? maxLabelWidth,
}) {
  final labelText = Text(
    label,
    style: theme.textTheme.labelLarge,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
  return Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: theme.colorScheme.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        if (maxLabelWidth == null)
          labelText
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxLabelWidth),
            child: labelText,
          ),
        if (secondaryLabel != null) ...[
          const SizedBox(width: 6),
          Text(
            secondaryLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (showChevron) ...[
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ],
    ),
  );
}
