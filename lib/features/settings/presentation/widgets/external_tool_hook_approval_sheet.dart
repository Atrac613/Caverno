import 'package:flutter/material.dart';

import '../../domain/entities/app_settings.dart';

class ExternalToolHookApprovalSheet extends StatelessWidget {
  const ExternalToolHookApprovalSheet({super.key, required this.hook});

  final ExternalToolHook hook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final environmentKeys = hook.normalizedEnv.keys.toList()..sort();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review external hook',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enabling this exact configuration allows Caverno to start the command for the selected event for 30 days.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text('Source ID: ${hook.sourceId.trim()}'),
            const SizedBox(height: 4),
            Text('Event: ${hook.normalizedEvent}'),
            const SizedBox(height: 4),
            Text('Command: ${hook.normalizedCommand}'),
            const SizedBox(height: 4),
            Text(
              hook.args.isEmpty
                  ? 'Arguments: none'
                  : 'Arguments: ${hook.args.join(' ')}',
            ),
            const SizedBox(height: 4),
            Text(
              environmentKeys.isEmpty
                  ? 'Environment keys: none'
                  : 'Environment keys: ${environmentKeys.join(', ')}',
            ),
            if (environmentKeys.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Environment values are hidden.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (hook.reviewedAt != null) ...[
              const SizedBox(height: 8),
              Text('Previously reviewed at: ${hook.reviewedAt}'),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep disabled'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Enable reviewed hook'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
