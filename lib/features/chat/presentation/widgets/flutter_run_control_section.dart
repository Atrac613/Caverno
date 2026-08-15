import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/flutter_run_session.dart';
import '../providers/flutter_run_provider.dart';
import 'flutter_run_launcher.dart';

/// Run/stop control for the project's Flutter app.
///
/// Only rendered for a Flutter project; a Dart package or a non-Dart worktree
/// has nothing to run and gets no dead button.
class FlutterRunControlSection extends ConsumerWidget {
  const FlutterRunControlSection({
    super.key,
    required this.projectRoot,
    this.threadId,
  });

  final String projectRoot;

  /// Thread whose bottom dock opens on the run log when a run starts.
  final String? threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(flutterRunSessionProvider(projectRoot));
    final controller = ref.read(flutterRunControllerProvider(projectRoot));
    final state = async.value ?? controller.state;

    return Column(
      key: const ValueKey('flutter-run-control-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _StatusLine(state: state)),
            const SizedBox(width: 8),
            _ActionButton(
              state: state,
              onRun: () => _run(context, ref),
              onStop: controller.stop,
            ),
          ],
        ),
        if (state.failure case final failure?) ...[
          const SizedBox(height: 6),
          Text(
            failure,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) =>
      const FlutterRunLauncher().run(
        context: context,
        ref: ref,
        projectRoot: projectRoot,
        threadId: threadId,
      );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final FlutterRunSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = state.device?.displayName;
    final label = switch (state.status) {
      FlutterRunStatus.idle => 'chat.flutter_run_idle'.tr(),
      FlutterRunStatus.listingDevices => 'chat.flutter_run_listing'.tr(),
      FlutterRunStatus.starting => 'chat.flutter_run_starting'.tr(),
      FlutterRunStatus.running => 'chat.flutter_run_running'.tr(),
      FlutterRunStatus.stopping => 'chat.flutter_run_stopping'.tr(),
      FlutterRunStatus.exited => 'chat.flutter_run_exited'.tr(),
      FlutterRunStatus.failed => 'chat.flutter_run_failed'.tr(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        if (device != null)
          Text(
            device,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.state,
    required this.onRun,
    required this.onStop,
  });

  final FlutterRunSessionState state;
  final VoidCallback onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (state.isActive) {
      return FilledButton.tonalIcon(
        key: const ValueKey('flutter-run-stop'),
        // A stop already in flight must not be asked for twice: the second
        // press would land while the first is still escalating signals.
        onPressed: state.status == FlutterRunStatus.stopping ? null : onStop,
        icon: const Icon(Icons.stop, size: 18),
        label: Text('chat.flutter_run_stop'.tr()),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('flutter-run-start'),
      onPressed: state.isBusy ? null : onRun,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text('chat.flutter_run_start'.tr()),
    );
  }
}
