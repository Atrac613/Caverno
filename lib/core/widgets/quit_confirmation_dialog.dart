import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Confirmation prompt shown before Caverno quits.
///
/// Modeled on editor-style quit prompts (Cursor, VS Code): the dialog is fully
/// keyboard operable and advertises it. Enter confirms, Escape cancels, and Tab
/// or the arrow keys move between the actions. The shortcut hint is rendered
/// inside each button so the affordance is discoverable without a mouse, and
/// the destructive action holds initial focus so a bare Enter quits.
class QuitConfirmationDialog extends StatelessWidget {
  const QuitConfirmationDialog({super.key});

  /// Shows the dialog and resolves to whether the user confirmed the quit.
  ///
  /// Dismissing the dialog by any route (Escape, barrier tap, back gesture)
  /// counts as a cancel.
  static Future<bool> show(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const QuitConfirmationDialog(),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Enter deliberately has no binding here: the framework already routes
      // it to the focused button, so binding it at this level would override
      // the focus and confirm the quit even when the user tabbed to Cancel.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _close(context, false),
      },
      child: AlertDialog(
        title: const Text('Quit Caverno?'),
        content: const Text(
          'Caverno will stop background routines and active tasks.',
        ),
        actions: [
          TextButton(
            onPressed: () => _close(context, false),
            child: const _ActionLabel(label: 'Cancel', shortcut: 'Esc'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => _close(context, true),
            child: const _ActionLabel(label: 'Quit', shortcut: '⏎'),
          ),
        ],
      ),
    );
  }

  /// Pops the dialog route once.
  ///
  /// A repeated key event or a double tap can deliver two closes for what the
  /// user experienced as one action, so the route check keeps the second call
  /// from popping whatever sits underneath the dialog.
  void _close(BuildContext context, bool confirmed) {
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    Navigator.of(context).pop(confirmed);
  }
}

/// Button content pairing an action label with its keyboard shortcut hint.
class _ActionLabel extends StatelessWidget {
  const _ActionLabel({required this.label, required this.shortcut});

  final String label;
  final String shortcut;

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 8),
        Text(
          shortcut,
          style: textStyle.copyWith(
            fontSize: (textStyle.fontSize ?? 14) - 2,
            color: textStyle.color?.withValues(alpha: 0.7),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
