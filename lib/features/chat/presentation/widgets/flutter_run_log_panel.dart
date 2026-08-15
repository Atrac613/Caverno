import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/flutter_run_session.dart';
import '../providers/flutter_run_provider.dart';

/// Bottom log panel for the running app.
///
/// Collapsed to its header until there is something to read, so a workspace
/// that never runs the app keeps its full height. Deliberately a plain
/// scrollback for now: the planned reader that turns these lines into an issue
/// list consumes [FlutterRunSessionState.logs], not this widget.
class FlutterRunLogPanel extends ConsumerStatefulWidget {
  const FlutterRunLogPanel({super.key, required this.projectRoot});

  final String projectRoot;

  @override
  ConsumerState<FlutterRunLogPanel> createState() => _FlutterRunLogPanelState();
}

class _FlutterRunLogPanelState extends ConsumerState<FlutterRunLogPanel> {
  final _scrollController = ScrollController();
  bool _expanded = true;
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
          _Header(
            state: state,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            onClear: () => ref
                .read(flutterRunControllerProvider(widget.projectRoot))
                .clearLogs(),
          ),
          if (_expanded)
            SizedBox(
              height: 200,
              child: Scrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: state.logs.length,
                  itemBuilder: (_, index) => _LogLine(line: state.logs[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.expanded,
    required this.onToggle,
    required this.onClear,
  });

  final FlutterRunSessionState state;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 4),
      child: Row(
        children: [
          Icon(
            Icons.terminal_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'chat.flutter_run_log_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              state.command,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (state.hasLogs)
            IconButton(
              key: const ValueKey('flutter-run-log-clear'),
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              tooltip: 'chat.flutter_run_clear_logs'.tr(),
            ),
          IconButton(
            key: const ValueKey('flutter-run-log-toggle'),
            onPressed: onToggle,
            icon: Icon(
              expanded ? Icons.expand_more : Icons.expand_less,
              size: 20,
            ),
            tooltip: expanded
                ? 'chat.flutter_run_collapse_logs'.tr()
                : 'chat.flutter_run_expand_logs'.tr(),
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
