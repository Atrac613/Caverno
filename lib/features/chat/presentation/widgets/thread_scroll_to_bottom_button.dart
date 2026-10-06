import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A compact affordance for returning to the newest message in a thread.
class ThreadScrollToBottomButton extends StatelessWidget {
  const ThreadScrollToBottomButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = 'chat.scroll_to_latest'.tr();

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          key: const ValueKey('scroll-to-bottom-button'),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.94,
          ),
          elevation: 3,
          shadowColor: theme.shadowColor.withValues(alpha: 0.35),
          shape: CircleBorder(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Icon(
                  Icons.arrow_downward_rounded,
                  color: theme.colorScheme.onSurface,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
