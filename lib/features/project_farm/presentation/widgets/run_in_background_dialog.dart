import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/roadmap_snapshot.dart';

/// Confirms a background run (FARM4 slice 4b): what runs, which declared
/// command verifies it, and that the result is a branch for review. Completes
/// with the chosen command, or null when the user cancels.
class RunInBackgroundDialog extends StatefulWidget {
  const RunInBackgroundDialog({
    super.key,
    required this.projectName,
    required this.item,
    required this.commands,
  });

  final String projectName;
  final RoadmapItemSnapshot item;

  /// The project policy's allowed commands; the user picks one.
  final List<String> commands;

  @override
  State<RunInBackgroundDialog> createState() => _RunInBackgroundDialogState();
}

class _RunInBackgroundDialogState extends State<RunInBackgroundDialog> {
  late String _command = widget.commands.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return AlertDialog(
      title: Text('project_farm_run.title'.tr()),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.projectName} · '
              '${[item.id, item.title].where((p) => p.isNotEmpty).join(': ')}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text('"${item.quote}"', style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Text(
              'project_farm_run.command'.tr(),
              style: theme.textTheme.labelLarge,
            ),
            DropdownButton<String>(
              key: const ValueKey('project-farm-run-command'),
              isExpanded: true,
              value: _command,
              items: [
                for (final command in widget.commands)
                  DropdownMenuItem(
                    value: command,
                    child: Text(
                      command,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _command = value);
              },
            ),
            const SizedBox(height: 12),
            Text('project_farm_run.explain'.tr()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey('project-farm-run-confirm'),
          onPressed: () => Navigator.of(context).pop(_command),
          child: Text('project_farm_run.confirm'.tr()),
        ),
      ],
    );
  }
}
