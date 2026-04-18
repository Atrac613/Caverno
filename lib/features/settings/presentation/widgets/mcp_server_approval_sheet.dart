import 'package:flutter/material.dart';

import '../../domain/entities/app_settings.dart';

class McpServerApprovalSheet extends StatelessWidget {
  const McpServerApprovalSheet({
    super.key,
    required this.server,
    required this.toolNames,
    this.connectionError,
  });

  final McpServerConfig server;
  final List<String> toolNames;
  final String? connectionError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canApprove = connectionError == null;
    final reviewPendingLabel = server.isBlocked ? 'Move to pending' : 'Keep pending';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review MCP server trust',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Approve this server before Caverno exposes its tools to the model.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text('Source: ${server.trustSourceLabel}'),
            const SizedBox(height: 4),
            Text('Transport: ${server.type.name}'),
            const SizedBox(height: 4),
            Text('Endpoint: ${server.displayLabel}'),
            if (server.trustedAt != null) ...[
              const SizedBox(height: 4),
              Text('Previously trusted at: ${server.trustedAt}'),
            ],
            const SizedBox(height: 16),
            if (connectionError != null) ...[
              Text(
                'Connection error: $connectionError',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ] else if (toolNames.isEmpty) ...[
              const Text('No remote MCP tools were reported by this server.'),
            ] else ...[
              Text(
                'Reported tools',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'These tool names will be exposed to the model after trust is granted.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ...toolNames.map(
                (toolName) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $toolName'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(McpServerTrustState.pending);
                    },
                    child: Text(reviewPendingLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(McpServerTrustState.blocked);
                    },
                    child: const Text('Block'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: canApprove
                        ? () {
                            Navigator.of(
                              context,
                            ).pop(McpServerTrustState.trusted);
                          }
                        : null,
                    child: const Text('Trust server'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Keep current state'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
