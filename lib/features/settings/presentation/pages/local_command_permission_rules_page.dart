import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../providers/settings_notifier.dart';

class LocalCommandPermissionRulesPage extends ConsumerWidget {
  const LocalCommandPermissionRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final rules = settings.localCommandPermissionRules;

    return Scaffold(
      appBar: AppBar(title: const Text('Local Command Rules')),
      body: rules.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved local command rules. Use Always Allow or Always Deny from a command approval dialog to add one.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rules.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _RuleTile(rule: rules[index]);
              },
            ),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.rule});

  final LocalCommandPermissionRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actionColor = switch (rule.action) {
      LocalCommandPermissionAction.allow => theme.colorScheme.primary,
      LocalCommandPermissionAction.deny => theme.colorScheme.error,
      LocalCommandPermissionAction.ask => theme.colorScheme.secondary,
    };
    final actionLabel = switch (rule.action) {
      LocalCommandPermissionAction.allow => 'Allow',
      LocalCommandPermissionAction.deny => 'Deny',
      LocalCommandPermissionAction.ask => 'Ask',
    };
    final matchLabel = switch (rule.match) {
      LocalCommandPermissionMatch.exact => 'exact',
      LocalCommandPermissionMatch.prefix => 'prefix',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                rule.action == LocalCommandPermissionAction.allow
                    ? Icons.verified_user_outlined
                    : Icons.block_rounded,
                color: actionColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    rule.pattern,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$actionLabel when command is an $matchLabel match',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (rule.normalizedWorkingDirectory.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      rule.normalizedWorkingDirectory,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: rule.enabled,
              onChanged: (value) => ref
                  .read(settingsNotifierProvider.notifier)
                  .toggleLocalCommandPermissionRule(rule.id, value),
            ),
            IconButton(
              tooltip: 'Delete rule',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => ref
                  .read(settingsNotifierProvider.notifier)
                  .removeLocalCommandPermissionRule(rule.id),
            ),
          ],
        ),
      ),
    );
  }
}
