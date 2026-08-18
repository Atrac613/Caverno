import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/browser_session_service.dart';
import '../../domain/entities/html_preview_session.dart';
import '../../domain/services/html_preview_session_controller.dart';
import '../../domain/services/html_project_detector.dart';
import 'coding_environment_snapshot_provider.dart';
import 'flutter_run_provider.dart';

class HtmlPreviewWorkspaceEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Bumped when the coding worktree may have gained or lost HTML files.
final htmlPreviewWorkspaceEpochProvider =
    NotifierProvider<HtmlPreviewWorkspaceEpoch, int>(
      HtmlPreviewWorkspaceEpoch.new,
    );

/// One preview at a time: the built-in browser has a single pane.
final htmlPreviewControllerProvider = Provider<HtmlPreviewSessionController>((
  ref,
) {
  final browser = ref.watch(browserSessionServiceProvider);
  final controller = HtmlPreviewSessionController(
    openPreview: browser.openLocalPreview,
    closePreview: browser.clearLocalPreview,
    reloadPreview: browser.reloadLocalPreview,
    panel: browser,
    isPanelOpen: () => browser.isPanelOpen,
    isPlatformSupported: () => BrowserSessionService.isPlatformSupported,
  );
  ref.listen<int>(htmlPreviewWorkspaceEpochProvider, (previous, next) {
    if (previous == next) return;
    unawaited(controller.reload());
  });
  ref.onDispose(controller.dispose);
  return controller;
});

final htmlPreviewSessionProvider = StreamProvider<HtmlPreviewSessionState>((
  ref,
) {
  final controller = ref.watch(htmlPreviewControllerProvider);
  return controller.states;
});

/// Whether the companion Run section can preview HTML for [projectRoot].
///
/// Flutter projects keep the existing `flutter run` control instead. The
/// workspace epoch and worktree diff watches re-scan after file changes.
final htmlPreviewSupportedProvider = Provider.family<bool, String>((
  ref,
  projectRoot,
) {
  ref.watch(htmlPreviewWorkspaceEpochProvider);
  ref.watch(codingWorktreeDiffProvider(projectRoot));
  if (projectRoot.trim().isEmpty) return false;
  if (!BrowserSessionService.isPlatformSupported) return false;
  if (ref.watch(flutterRunSupportedProvider(projectRoot))) return false;
  return const HtmlProjectDetector().detect(projectRoot) != null;
});
