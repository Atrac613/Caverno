import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/flutter_run_session.dart';
import '../providers/flutter_run_provider.dart';

/// Scrollback for the running app, as one pane of the bottom dock.
///
/// Follows the tail as lines arrive, which is what a run log is read for.
class FlutterRunLogView extends ConsumerStatefulWidget {
  const FlutterRunLogView({super.key, required this.projectRoot});

  final String projectRoot;

  @override
  ConsumerState<FlutterRunLogView> createState() => _FlutterRunLogViewState();
}

class _FlutterRunLogViewState extends ConsumerState<FlutterRunLogView> {
  final _scrollController = ScrollController();
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
    final state =
        ref.watch(flutterRunSessionProvider(widget.projectRoot)).value ??
        ref.read(flutterRunControllerProvider(widget.projectRoot)).state;
    _followTail(state.logs.length);

    if (!state.hasLogs) {
      return Center(
        child: Text(
          'chat.flutter_run_log_empty'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('flutter-run-log-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.command,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const ValueKey('flutter-run-log-clear'),
                onPressed: () => ref
                    .read(flutterRunControllerProvider(widget.projectRoot))
                    .clearLogs(),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                tooltip: 'chat.flutter_run_clear_logs'.tr(),
              ),
            ],
          ),
        ),
        Expanded(
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
