import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../entities/html_preview_session.dart';
import 'html_preview_static_server.dart';
import 'html_project_detector.dart';

/// Drives one HTML preview: detect the entry file, serve it on loopback, and
/// open it in the built-in browser. One preview runs at a time; starting a
/// second project replaces the first.
class HtmlPreviewSessionController {
  HtmlPreviewSessionController({
    required Future<void> Function(Uri url) openPreview,
    required Future<void> Function() closePreview,
    Future<void> Function()? reloadPreview,
    required Listenable panel,
    required bool Function() isPanelOpen,
    bool Function()? isPlatformSupported,
    HtmlPreviewStaticServer Function()? createServer,
    HtmlProjectDetector detector = const HtmlProjectDetector(),
  }) : _openPreview = openPreview,
       _closePreview = closePreview,
       _reloadPreview = reloadPreview ?? (() async {}),
       _panel = panel,
       _isPanelOpen = isPanelOpen,
       _isPlatformSupported =
           isPlatformSupported ??
           (() =>
               !kIsWeb &&
               (Platform.isIOS ||
                   Platform.isAndroid ||
                   Platform.isMacOS ||
                   Platform.isWindows)),
       _createServer = createServer ?? HtmlPreviewStaticServer.new,
       _detector = detector {
    _panel.addListener(_onPanelChanged);
  }

  final Future<void> Function(Uri url) _openPreview;
  final Future<void> Function() _closePreview;
  final Future<void> Function() _reloadPreview;
  final Listenable _panel;
  final bool Function() _isPanelOpen;
  final bool Function() _isPlatformSupported;
  final HtmlPreviewStaticServer Function() _createServer;
  final HtmlProjectDetector _detector;

  static const unavailableFailure = 'unavailable';
  static const noEntryFailure = 'no_entry';

  final _stateController =
      StreamController<HtmlPreviewSessionState>.broadcast();

  HtmlPreviewSessionState _state = const HtmlPreviewSessionState();
  HtmlPreviewStaticServer? _server;
  bool _closingFromStop = false;

  HtmlPreviewSessionState get state => _state;

  Stream<HtmlPreviewSessionState> get states => _stateController.stream;

  Future<void> start({
    required String projectRoot,
    HtmlProjectEntry? entry,
  }) async {
    if (_state.isActiveFor(projectRoot)) return;
    if (_state.isActive) {
      await stop();
    }

    _emit(
      HtmlPreviewSessionState(
        status: HtmlPreviewStatus.starting,
        projectRoot: projectRoot,
      ),
    );

    if (!_isPlatformSupported()) {
      _emit(
        _failed(projectRoot, HtmlPreviewSessionController.unavailableFailure),
      );
      return;
    }

    final resolved = entry ?? _detector.detect(projectRoot);
    if (resolved == null) {
      _emit(_failed(projectRoot, HtmlPreviewSessionController.noEntryFailure));
      return;
    }

    final server = _createServer();
    _server = server;
    try {
      final origin = await server.start(projectRoot: projectRoot);
      final url = origin.replace(path: '/${resolved.relativePath}');
      await _openPreview(url);
      if (_state.status != HtmlPreviewStatus.starting) {
        await server.stop();
        return;
      }
      _emit(
        _state.copyWith(
          status: HtmlPreviewStatus.running,
          entryRelativePath: resolved.relativePath,
          url: url.toString(),
          clearFailure: true,
        ),
      );
    } catch (error) {
      await server.stop();
      _server = null;
      if (_state.status == HtmlPreviewStatus.starting) {
        _emit(_failed(projectRoot, error.toString()));
      }
    }
  }

  /// Reloads the open preview after project files change.
  Future<void> reload() async {
    if (_state.status != HtmlPreviewStatus.running) return;
    await _reloadPreview();
  }

  Future<void> stop() async {
    if (!_state.isActive && _server == null) return;
    final projectRoot = _state.projectRoot;
    _emit(_state.copyWith(status: HtmlPreviewStatus.stopping));
    final server = _server;
    _server = null;
    await server?.stop();
    _closingFromStop = true;
    try {
      await _closePreview();
    } finally {
      _closingFromStop = false;
    }
    if (_state.status == HtmlPreviewStatus.stopping) {
      _emit(
        HtmlPreviewSessionState(
          status: HtmlPreviewStatus.idle,
          projectRoot: projectRoot,
        ),
      );
    }
  }

  Future<void> dispose() async {
    _panel.removeListener(_onPanelChanged);
    await stop();
    await _stateController.close();
  }

  void _onPanelChanged() {
    if (_closingFromStop) return;
    if (_state.status != HtmlPreviewStatus.running) return;
    if (_isPanelOpen()) return;
    unawaited(stop());
  }

  HtmlPreviewSessionState _failed(String projectRoot, String message) {
    return HtmlPreviewSessionState(
      status: HtmlPreviewStatus.failed,
      projectRoot: projectRoot,
      failure: message,
    );
  }

  void _emit(HtmlPreviewSessionState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }
}
