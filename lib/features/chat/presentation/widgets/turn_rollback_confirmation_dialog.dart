import 'package:flutter/material.dart';

final class TurnRollbackConfirmationDialog extends StatelessWidget {
  const TurnRollbackConfirmationDialog({
    required this.summary,
    required this.paths,
    super.key,
  });

  final String summary;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visiblePaths = paths.take(8).toList(growable: false);
    final hiddenCount = paths.length - visiblePaths.length;

    return AlertDialog(
      title: const Text('Revert last agent turn?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary),
            const SizedBox(height: 12),
            Text(
              'This restores the file contents captured before that turn.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final path in visiblePaths)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (hiddenCount > 0)
              Text(
                '+$hiddenCount more',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.restore_rounded),
          label: const Text('Revert'),
        ),
      ],
    );
  }
}
