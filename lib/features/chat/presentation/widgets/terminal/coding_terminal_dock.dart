import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/services/coding_terminal_service.dart';
import 'coding_terminal_panel.dart';

/// Height of the draggable splitter between the workspace and the terminal.
const double _resizeHandleHeight = 6;

/// Space the workspace above the terminal must keep — enough for the header
/// and a usable composer, so dragging can never swallow the chat.
const double _workspaceReserveHeight = 220;

/// Docks [CodingTerminalPanel] under [child] when the terminal is open.
///
/// Owns only the split geometry; the session and the open/closed flag live in
/// [CodingTerminalService], so the dock can be rebuilt or removed from the
/// tree without disturbing a running shell.
class CodingTerminalDock extends ConsumerStatefulWidget {
  const CodingTerminalDock({
    super.key,
    required this.workingDirectory,
    required this.threadId,
    required this.child,
  });

  /// Root of the active coding project, or `null` where the terminal is not
  /// offered (no project, non-coding workspace, unsupported platform). The
  /// dock then renders [child] untouched.
  final String? workingDirectory;

  /// Conversation whose open/closed flag decides whether the panel shows.
  /// `null` is the not-yet-saved draft thread.
  final String? threadId;
  final Widget child;

  /// Whether this platform can host the terminal at all.
  static bool get isSupported => CodingTerminalService.isSupported;

  @override
  ConsumerState<CodingTerminalDock> createState() => _CodingTerminalDockState();
}

class _CodingTerminalDockState extends ConsumerState<CodingTerminalDock> {
  double _panelHeight = codingTerminalPanelDefaultHeight;

  @override
  Widget build(BuildContext context) {
    final workingDirectory = widget.workingDirectory;
    final service = ref.watch(codingTerminalServiceProvider);

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (workingDirectory == null ||
            !service.isPanelOpenFor(widget.threadId)) {
          return widget.child;
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height;
            final maxPanelHeight =
                availableHeight - _workspaceReserveHeight - _resizeHandleHeight;
            if (maxPanelHeight < codingTerminalPanelMinHeight) {
              // Too short to split without crushing the chat; the toggle stays
              // on and the panel returns as soon as there is room.
              return widget.child;
            }
            final panelHeight = _panelHeight.clamp(
              codingTerminalPanelMinHeight,
              maxPanelHeight,
            );

            return Column(
              children: [
                Expanded(child: widget.child),
                _buildResizeHandle(
                  context,
                  maxPanelHeight: maxPanelHeight,
                  currentHeight: panelHeight,
                ),
                SizedBox(
                  height: panelHeight,
                  child: CodingTerminalPanel(
                    workingDirectory: workingDirectory,
                    onClose: () => service.closePanel(widget.threadId),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildResizeHandle(
    BuildContext context, {
    required double maxPanelHeight,
    required double currentHeight,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Dragging up grows the terminal, so the delta is subtracted.
        onVerticalDragUpdate: (details) {
          final next = (currentHeight - details.delta.dy).clamp(
            codingTerminalPanelMinHeight,
            maxPanelHeight,
          );
          if (next == _panelHeight) return;
          setState(() {
            _panelHeight = next;
          });
        },
        child: SizedBox(
          height: _resizeHandleHeight,
          width: double.infinity,
          child: Center(
            child: Container(height: 1, color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }
}
