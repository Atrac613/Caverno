import 'package:flutter/material.dart';

/// Current value of a composer submenu row. No chevron of its own:
/// SubmenuButton already appends the submenu arrow after this trailing widget,
/// and drawing a second one reads as two separate affordances.
Widget buildComposerSubmenuValue(ThemeData theme, String value) {
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 160),
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Leading check for the selected entry of a composer submenu. The icon is
/// always laid out, so selecting a different row does not shift the menu.
Widget buildComposerMenuCheckIcon(ThemeData theme, bool checked) {
  return Icon(
    checked ? Icons.check : null,
    size: 18,
    color: theme.colorScheme.primary,
  );
}

/// A composer submenu offering mutually exclusive values for one setting.
///
/// The selected value is named on the parent row and checked in the list, so
/// the current setting is readable without opening the submenu. Every such menu
/// in the composer is this widget: the reasoning-effort and thinking rows were
/// two copies of the same twenty lines, and the second one drifted in first.
class ComposerChoiceSubmenu<T> extends StatelessWidget {
  const ComposerChoiceSubmenu({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    super.key,
  });

  final Widget title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final void Function(T value) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SubmenuButton(
      trailingIcon: buildComposerSubmenuValue(theme, labelOf(selected)),
      menuChildren: [
        for (final value in values)
          MenuItemButton(
            leadingIcon: buildComposerMenuCheckIcon(theme, value == selected),
            onPressed: () => onSelected(value),
            child: Text(labelOf(value)),
          ),
      ],
      child: title,
    );
  }
}
