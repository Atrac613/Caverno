import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/services/coding_terminal_service.dart';
import '../../../domain/entities/flutter_run_issue.dart';
import '../../providers/bottom_dock_provider.dart';
import '../flutter_run_issue_list.dart';
import '../flutter_run_log_view.dart';
import 'coding_terminal_dock_tabs.dart';
import 'coding_terminal_panel.dart';

/// Height of the draggable splitter between the workspace and the terminal.
const double _resizeHandleHeight = 6;

/// Space the workspace above the terminal must keep — enough for the header
/// and a usable composer, so dragging can never swallow the chat.
const double _workspaceReserveHeight = 220;

/// Docks the workspace's bottom panes under [child]: terminal, run log and
/// the issues found in that log.
///
/// One dock rather than one per pane. They compete for the same edge of the
/// screen, and stacking two of them left the chat squeezed between them with
/// no way to tell which handle resized which.
///
/// Owns only the split geometry: the shell session and the open/closed flag
/// live in [CodingTerminalService] and the selected tab in
/// [bottomDockTabProvider], so the dock can be rebuilt or removed from the tree
/// without disturbing a running shell or a running app.
class CodingTerminalDock extends ConsumerStatefulWidget {
  const CodingTerminalDock({
    super.key,
    required this.workingDirectory,
    required this.threadId,
    required this.runProjectRoot,
    required this.onSendIssueToChat,
    required this.child,
  });

  /// Project the run controls act on, or empty where there is none.
  final String runProjectRoot;

  /// Hands an issue to the conversation as a prefilled prompt.
  final void Function(FlutterRunIssue issue) onSendIssueToChat;

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

    final tab = ref.watch(
      bottomDockTabProvider.select(
        (tabs) => tabs[widget.threadId ?? ''] ?? BottomDockTab.terminal,
      ),
    );

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        // The terminal needs a working directory; the run panes do not, so the
        // dock opens for a run even where no shell can be offered.
        final canShowTerminal = workingDirectory != null;
        final hasRunProject = widget.runProjectRoot.isNotEmpty;
        // Nothing to dock: an empty pane with a close button is worse than no
        // pane at all.
        if (!canShowTerminal && !hasRunProject) return widget.child;
        if (!service.isPanelOpenFor(widget.threadId)) {
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
                  child: Column(
                    children: [
                      CodingTerminalDockTabs(
                        selected: tab,
                        canShowTerminal: canShowTerminal,
                        runProjectRoot: widget.runProjectRoot,
                        onSelected: (next) => ref
                            .read(bottomDockTabProvider.notifier)
                            .select(widget.threadId, next),
                        onClose: () => service.closePanel(widget.threadId),
                      ),
                      Expanded(
                        child: _buildPane(
                          tab: tab,
                          workingDirectory: workingDirectory,
                          canShowTerminal: canShowTerminal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPane({
    required BottomDockTab tab,
    required String? workingDirectory,
    required bool canShowTerminal,
  }) {
    final projectRoot = widget.runProjectRoot;
    return switch (tab) {
      BottomDockTab.terminal when canShowTerminal => CodingTerminalPanel(
        workingDirectory: workingDirectory!,
        onClose: () =>
            ref.read(codingTerminalServiceProvider).closePanel(widget.threadId),
        showHeader: false,
      ),
      BottomDockTab.runLog when projectRoot.isNotEmpty => FlutterRunLogView(
        projectRoot: projectRoot,
      ),
      BottomDockTab.issues when projectRoot.isNotEmpty => FlutterRunIssueList(
        projectRoot: projectRoot,
        onSendToChat: widget.onSendIssueToChat,
      ),
      _ => const SizedBox.shrink(),
    };
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
