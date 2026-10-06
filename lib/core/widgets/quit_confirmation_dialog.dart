import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Confirmation prompt shown before Caverno quits.
///
/// Modeled on editor-style quit prompts (Cursor, VS Code): the dialog is fully
/// keyboard operable and advertises it. Enter confirms, Escape cancels, and Tab
/// or the arrow keys move between the actions. The shortcut hint is rendered
/// inside each button so the affordance is discoverable without a mouse, and
/// the destructive action holds initial focus so a bare Enter quits.
///
/// Confirming does not close the dialog. Teardown -- closing the drift
/// database, stopping maintenance, saving window geometry -- can take seconds,
/// and popping the dialog first left the app painting its ordinary UI with no
/// sign that anything was happening, which is exactly how a hang looks. The
/// dialog instead swaps its body for a progress state and stays up until the
/// process goes away, so the last thing on screen explains the wait.
class QuitConfirmationDialog extends StatefulWidget {
  const QuitConfirmationDialog({super.key, this.onConfirmed});

  /// Teardown to run while the dialog shows its progress state.
  ///
  /// On desktop this normally never returns: it ends with the process
  /// terminating. If it does return, the dialog pops and [show] resolves to
  /// `true`. When null the dialog pops immediately on confirm, which is the
  /// behaviour a caller that does its own teardown gets.
  final Future<void> Function()? onConfirmed;

  /// Shows the dialog and resolves to whether the user confirmed the quit.
  ///
  /// Dismissing the dialog by any route (Escape, barrier tap, back gesture)
  /// counts as a cancel. An [onConfirmed] failure is rethrown here, once the
  /// route is gone, so the caller still sees it.
  static Future<bool> show(
    BuildContext context, {
    Future<void> Function()? onConfirmed,
  }) async {
    Object? failure;
    StackTrace? failureStackTrace;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => QuitConfirmationDialog(
        onConfirmed: onConfirmed == null
            ? null
            : () async {
                // The dialog must not unwind a failed teardown while it is the
                // only thing on screen, so the error is held until the route
                // has closed.
                try {
                  await onConfirmed();
                } catch (error, stackTrace) {
                  failure = error;
                  failureStackTrace = stackTrace;
                }
              },
      ),
    );
    final error = failure;
    if (error != null) {
      Error.throwWithStackTrace(error, failureStackTrace ?? StackTrace.current);
    }
    return confirmed ?? false;
  }

  @override
  State<QuitConfirmationDialog> createState() => _QuitConfirmationDialogState();
}

class _QuitConfirmationDialogState extends State<QuitConfirmationDialog> {
  bool _shuttingDown = false;

  @override
  Widget build(BuildContext context) {
    // Teardown is not cancelable, so once it starts the dialog refuses every
    // dismissal route that would drop the user back into an app whose database
    // is already closing.
    return PopScope(
      canPop: !_shuttingDown,
      child: CallbackShortcuts(
        // Enter deliberately has no binding here: the framework already routes
        // it to the focused button, so binding it at this level would override
        // the focus and confirm the quit even when the user tabbed to Cancel.
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: AlertDialog(
          title: Text(_shuttingDown ? 'Quitting Caverno…' : 'Quit Caverno?'),
          content: _shuttingDown
              ? const _ShutdownProgress()
              : const Text(
                  'Caverno will stop background routines and active tasks.',
                ),
          actions: _shuttingDown
              ? null
              : [
                  TextButton(
                    onPressed: _cancel,
                    child: const _ActionLabel(label: 'Cancel', shortcut: 'Esc'),
                  ),
                  FilledButton(
                    autofocus: true,
                    onPressed: _confirm,
                    child: const _ActionLabel(label: 'Quit', shortcut: '⏎'),
                  ),
                ],
        ),
      ),
    );
  }

  void _cancel() {
    if (_shuttingDown) {
      return;
    }
    _close(false);
  }

  Future<void> _confirm() async {
    if (_shuttingDown) {
      return;
    }
    final runner = widget.onConfirmed;
    if (runner == null) {
      _close(true);
      return;
    }

    setState(() => _shuttingDown = true);
    // Let the progress state reach the screen before teardown starts. The
    // point of the state is that the wait is visible, and a synchronous first
    // step in the runner would otherwise consume the frame that shows it.
    await WidgetsBinding.instance.endOfFrame;
    await runner();
    if (!mounted) {
      return;
    }
    _close(true);
  }

  /// Pops the dialog route once.
  ///
  /// A repeated key event or a double tap can deliver two closes for what the
  /// user experienced as one action, so the route check keeps the second call
  /// from popping whatever sits underneath the dialog.
  void _close(bool confirmed) {
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    Navigator.of(context).pop(confirmed);
  }
}

/// Body shown while the confirmed quit tears the app down.
class _ShutdownProgress extends StatelessWidget {
  const _ShutdownProgress();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 16),
        Flexible(
          child: Text('Closing the database and stopping background work.'),
        ),
      ],
    );
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
