import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/bottom_dock_provider.dart';
import '../../providers/flutter_run_provider.dart';

/// Tab strip for the workspace's bottom dock.
class CodingTerminalDockTabs extends ConsumerWidget {
  const CodingTerminalDockTabs({
    super.key,
    required this.selected,
    required this.canShowTerminal,
    required this.runProjectRoot,
    required this.onSelected,
    required this.onClose,
  });

  final BottomDockTab selected;
  final bool canShowTerminal;

  /// Project the run panes act on, or empty where there is none.
  final String runProjectRoot;

  bool get hasRunProject => runProjectRoot.isNotEmpty;
  final ValueChanged<BottomDockTab> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
        child: Row(
          children: [
            // Scrolls rather than overflows: a narrow dock still has to show
            // the close action, and three tabs plus a command line do not fit
            // at every width.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (canShowTerminal)
                      _DockTab(
                        tabKey: const ValueKey('bottom-dock-tab-terminal'),
                        label: 'chat.bottom_dock_terminal'.tr(),
                        icon: Icons.terminal_outlined,
                        selected: selected == BottomDockTab.terminal,
                        onTap: () => onSelected(BottomDockTab.terminal),
                      ),
                    if (hasRunProject) ...[
                      _DockTab(
                        tabKey: const ValueKey('bottom-dock-tab-run-log'),
                        label: 'chat.bottom_dock_run_log'.tr(),
                        icon: Icons.play_circle_outline,
                        selected: selected == BottomDockTab.runLog,
                        onTap: () => onSelected(BottomDockTab.runLog),
                      ),
                      _DockTab(
                        tabKey: const ValueKey('bottom-dock-tab-issues'),
                        label: _issueLabel(ref),
                        icon: Icons.error_outline,
                        selected: selected == BottomDockTab.issues,
                        onTap: () => onSelected(BottomDockTab.issues),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('bottom-dock-close'),
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'chat.bottom_dock_close'.tr(),
            ),
          ],
        ),
      ),
    );
  }

  String _issueLabel(WidgetRef ref) {
    final label = 'chat.bottom_dock_issues'.tr();
    if (!hasRunProject) return label;
    final count = ref.watch(
      flutterRunIssuesProvider(
        runProjectRoot,
      ).select((async) => async.value?.length ?? 0),
    );
    return count == 0 ? label : '$label ($count)';
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.tabKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final Key tabKey;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton.icon(
      key: tabKey,
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
