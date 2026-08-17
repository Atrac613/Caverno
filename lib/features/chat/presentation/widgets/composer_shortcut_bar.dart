import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/composer_shortcuts_notifier.dart';

/// Chip row shown directly above the composer, offering the next actions the
/// model drafted from the finished turn and the repository state.
///
/// Tapping a chip sends its prompt; long-pressing puts it in the composer so
/// the user can edit it first.
class ComposerShortcutBar extends ConsumerWidget {
  const ComposerShortcutBar({
    super.key,
    required this.onSelected,
    this.onPrefill,
    this.isBusy = false,
  });

  /// Called with the shortcut's prompt: tap sends it, long press prefills it.
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onPrefill;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched for rebuilds; the notifier resolves which thread these belong to.
    ref.watch(composerShortcutsNotifierProvider);
    final notifier = ref.read(composerShortcutsNotifierProvider.notifier);
    final shortcuts = notifier.visibleShortcuts;
    final isGenerating = notifier.isGeneratingForVisibleThread;
    if (shortcuts.isEmpty && !isGenerating) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('composer-shortcut-bar'),
      // Full width so the chips start at the leading edge; the composer's
      // Column centres whatever shrink-wraps.
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: shortcuts.isEmpty
              ? [_buildGeneratingChip(theme)]
              : [
                  for (var index = 0; index < shortcuts.length; index++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: index == shortcuts.length - 1 ? 0 : 8,
                      ),
                      child: _buildShortcutChip(
                        theme,
                        shortcuts[index],
                        index,
                        notifier,
                      ),
                    ),
                ],
        ),
      ),
    );
  }

  Widget _buildGeneratingChip(ThemeData theme) {
    return _ChipSurface(
      key: const ValueKey('composer-shortcut-generating'),
      theme: theme,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'message.composer_shortcuts_generating'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutChip(
    ThemeData theme,
    ComposerShortcut shortcut,
    int index,
    ComposerShortcutsNotifier notifier,
  ) {
    final enabled = !isBusy;
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);

    return Tooltip(
      message: shortcut.prompt,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('composer-shortcut-$index'),
          borderRadius: BorderRadius.circular(12),
          onTap: enabled
              ? () {
                  // The chips describe the finished turn; acting on one ends it.
                  notifier.clear();
                  onSelected(shortcut.prompt);
                }
              : null,
          onLongPress: enabled && onPrefill != null
              ? () => onPrefill!(shortcut.prompt)
              : null,
          child: _ChipSurface(
            theme: theme,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(shortcut.kind), size: 16, color: foreground),
                const SizedBox(width: 6),
                Text(
                  shortcut.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(ComposerShortcutKind kind) {
    switch (kind) {
      case ComposerShortcutKind.git:
        return Icons.commit;
      case ComposerShortcutKind.verify:
        return Icons.fact_check_outlined;
      case ComposerShortcutKind.followUp:
        return Icons.arrow_forward;
    }
  }
}

/// The composer's chip look, matching the control chips inside the input card.
class _ChipSurface extends StatelessWidget {
  const _ChipSurface({super.key, required this.theme, required this.child});

  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}
