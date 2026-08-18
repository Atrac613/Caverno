import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/html_preview_session.dart';
import '../../domain/services/html_preview_session_controller.dart';
import '../../domain/services/html_project_detector.dart';
import '../providers/html_preview_provider.dart';
import 'html_preview_entry_sheet.dart';

/// Run/stop control for a static HTML project in the built-in browser.
class HtmlPreviewControlSection extends ConsumerWidget {
  const HtmlPreviewControlSection({super.key, required this.projectRoot});

  final String projectRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(htmlPreviewSessionProvider);
    final controller = ref.read(htmlPreviewControllerProvider);
    final state = async.value ?? controller.state;
    final activeHere = state.isActiveFor(projectRoot);

    return Column(
      key: const ValueKey('html-preview-control-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatusLine(
                state: state,
                projectRoot: projectRoot,
                activeHere: activeHere,
              ),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              state: state,
              activeHere: activeHere,
              onRun: () => _run(context, ref),
              onStop: controller.stop,
            ),
          ],
        ),
        if (activeHere || state.projectRoot == projectRoot)
          if (state.failure case final failure?) ...[
            const SizedBox(height: 6),
            Text(
              _failureText(failure),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
      ],
    );
  }

  String _failureText(String failure) {
    return switch (failure) {
      HtmlPreviewSessionController.unavailableFailure =>
        'chat.html_preview_unavailable'.tr(),
      HtmlPreviewSessionController.noEntryFailure =>
        'chat.html_preview_no_entry'.tr(),
      _ => failure,
    };
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final detector = const HtmlProjectDetector();
    final entries = detector.listEntries(projectRoot);
    var entry = detector.preferredEntry(projectRoot);
    if (entry == null && entries.length > 1) {
      if (!navigator.mounted) return;
      entry = await HtmlPreviewEntrySheet.show(navigator.context, entries);
      if (entry == null) return;
    }
    await ref
        .read(htmlPreviewControllerProvider)
        .start(projectRoot: projectRoot, entry: entry);
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.state,
    required this.projectRoot,
    required this.activeHere,
  });

  final HtmlPreviewSessionState state;
  final String projectRoot;
  final bool activeHere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (state.status) {
      HtmlPreviewStatus.idle when !activeHere => 'chat.flutter_run_idle'.tr(),
      HtmlPreviewStatus.starting when activeHere =>
        'chat.flutter_run_starting'.tr(),
      HtmlPreviewStatus.running when activeHere =>
        'chat.flutter_run_running'.tr(),
      HtmlPreviewStatus.stopping when activeHere =>
        'chat.flutter_run_stopping'.tr(),
      HtmlPreviewStatus.failed when state.projectRoot == projectRoot =>
        'chat.flutter_run_failed'.tr(),
      _ => 'chat.flutter_run_idle'.tr(),
    };
    final entry = activeHere && state.entryRelativePath.isNotEmpty
        ? state.entryRelativePath
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        if (entry != null)
          Text(
            entry,
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
    required this.activeHere,
    required this.onRun,
    required this.onStop,
  });

  final HtmlPreviewSessionState state;
  final bool activeHere;
  final VoidCallback onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (activeHere) {
      return FilledButton.tonalIcon(
        key: const ValueKey('html-preview-stop'),
        onPressed: state.status == HtmlPreviewStatus.stopping ? null : onStop,
        icon: const Icon(Icons.stop, size: 18),
        label: Text('chat.flutter_run_stop'.tr()),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('html-preview-start'),
      onPressed: state.isBusy ? null : onRun,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text('chat.flutter_run_start'.tr()),
    );
  }
}
