import 'package:flutter/material.dart';

/// A labelled block of plan prose: the goal, and anything else that is one
/// value rather than a list.
///
/// A pure function of a label and a value, so it had no reason to be a method
/// on the page's state, where it was reached through three builders in two
/// part files.
class WorkflowTextSection extends StatelessWidget {
  const WorkflowTextSection({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
