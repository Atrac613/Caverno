import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/flutter_run_issue.dart';
import '../../domain/entities/flutter_run_session.dart';
import '../providers/flutter_run_provider.dart';
import 'flutter_run_issue_list.dart';
import 'flutter_run_log_panel_header.dart';

/// Bottom log panel for the running app.
///
/// Collapsed to its header until there is something to read, so a workspace
/// that never runs the app keeps its full height. Deliberately a plain
/// scrollback for now: the planned reader that turns these lines into an issue
/// list consumes [FlutterRunSessionState.logs], not this widget.
class FlutterRunLogPanel extends ConsumerStatefulWidget {
  const FlutterRunLogPanel({
    super.key,
    required this.projectRoot,
    required this.onSendIssueToChat,
  });

  final String projectRoot;

  /// Hands an issue to the conversation as a prefilled prompt.
  final void Function(FlutterRunIssue issue) onSendIssueToChat;

  @override
  ConsumerState<FlutterRunLogPanel> createState() => _FlutterRunLogPanelState();
}

class _FlutterRunLogPanelState extends ConsumerState<FlutterRunLogPanel> {
  final _scrollController = ScrollController();
  bool _expanded = true;
  bool _showIssues = false;
  int _renderedLineCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _followTail(int lineCount) {
    if (lineCount == _renderedLineCount) return;
    _renderedLineCount = lineCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(flutterRunSessionProvider(widget.projectRoot));
    final state =
        async.value ??
        ref.read(flutterRunControllerProvider(widget.projectRoot)).state;
    if (state.status == FlutterRunStatus.idle && !state.hasLogs) {
      return const SizedBox.shrink();
    }
    final issueCount =
        ref.watch(flutterRunIssuesProvider(widget.projectRoot)).value?.length ??
        ref
            .read(flutterRunIssueCollectorProvider(widget.projectRoot))
            .issues
            .length;
    _followTail(state.logs.length);

    return DecoratedBox(
      key: const ValueKey('flutter-run-log-panel'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlutterRunLogPanelHeader(
            state: state,
            expanded: _expanded,
            showIssues: _showIssues,
            issueCount: issueCount,
            onSelectTab: (issues) => setState(() {
              _showIssues = issues;
              _expanded = true;
            }),
            onToggle: () => setState(() => _expanded = !_expanded),
            onClear: () => _showIssues
                ? ref
                      .read(
                        flutterRunIssueCollectorProvider(widget.projectRoot),
                      )
                      .clear()
                : ref
                      .read(flutterRunControllerProvider(widget.projectRoot))
                      .clearLogs(),
          ),
          if (_expanded)
            SizedBox(
              height: 200,
              child: _showIssues
                  ? FlutterRunIssueList(
                      projectRoot: widget.projectRoot,
                      onSendToChat: widget.onSendIssueToChat,
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: state.logs.length,
                        itemBuilder: (_, index) =>
                            _LogLine(line: state.logs[index]),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.line});

  final FlutterRunLogLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (line.source) {
      FlutterRunLogSource.stderr => theme.colorScheme.error,
      FlutterRunLogSource.harness => theme.colorScheme.primary,
      FlutterRunLogSource.stdout => theme.colorScheme.onSurface,
    };
    return SelectableText(
      line.text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        color: color,
        height: 1.35,
      ),
    );
  }
}
