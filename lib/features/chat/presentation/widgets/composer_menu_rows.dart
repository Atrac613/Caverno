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
