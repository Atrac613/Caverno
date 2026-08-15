import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/flutter_run_session.dart';

/// Tab strip and actions above the run log.
class FlutterRunLogPanelHeader extends StatelessWidget {
  const FlutterRunLogPanelHeader({
    super.key,
    required this.state,
    required this.expanded,
    required this.showIssues,
    required this.issueCount,
    required this.onSelectTab,
    required this.onToggle,
    required this.onClear,
  });

  final FlutterRunSessionState state;
  final bool expanded;
  final bool showIssues;
  final int issueCount;
  final ValueChanged<bool> onSelectTab;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 4),
      child: Row(
        children: [
          Icon(
            Icons.terminal_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          _Tab(
            label: 'chat.flutter_run_log_title'.tr(),
            selected: !showIssues,
            onTap: () => onSelectTab(false),
          ),
          const SizedBox(width: 4),
          _Tab(
            key: const ValueKey('flutter-run-issues-tab'),
            label: issueCount == 0
                ? 'chat.flutter_run_issues_title'.tr()
                : '${'chat.flutter_run_issues_title'.tr()} ($issueCount)',
            selected: showIssues,
            onTap: () => onSelectTab(true),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              state.command,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (state.hasLogs)
            IconButton(
              key: const ValueKey('flutter-run-log-clear'),
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              tooltip: 'chat.flutter_run_clear_logs'.tr(),
            ),
          IconButton(
            key: const ValueKey('flutter-run-log-toggle'),
            onPressed: onToggle,
            icon: Icon(
              expanded ? Icons.expand_more : Icons.expand_less,
              size: 20,
            ),
            tooltip: expanded
                ? 'chat.flutter_run_collapse_logs'.tr()
                : 'chat.flutter_run_expand_logs'.tr(),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
