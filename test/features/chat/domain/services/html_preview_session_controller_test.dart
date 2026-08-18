import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/html_preview_session.dart';
import 'package:caverno/features/chat/domain/services/html_preview_session_controller.dart';
import 'package:caverno/features/chat/domain/services/html_preview_static_server.dart';
import 'package:caverno/features/chat/domain/services/html_project_detector.dart';

void main() {
  test('opens a detected html entry in the built-in browser', () async {
    final panel = _FakePanel();
    final server = _FakeServer();
    late Uri opened;
    final controller = HtmlPreviewSessionController(
      openPreview: (url) async {
        opened = url;
        panel.open = true;
        panel.notifyListeners();
      },
      closePreview: () async {
        panel.open = false;
        panel.notifyListeners();
      },
      panel: panel,
      isPanelOpen: () => panel.open,
      isPlatformSupported: () => true,
      createServer: () => server,
      detector: _FixedDetector(
        const HtmlProjectEntry(
          absolutePath: '/work/sea/index.html',
          relativePath: 'index.html',
        ),
      ),
    );

    await controller.start(projectRoot: '/work/sea');

    expect(controller.state.status, HtmlPreviewStatus.running);
    expect(controller.state.entryRelativePath, 'index.html');
    expect(opened.toString(), 'http://127.0.0.1:4321/index.html');
    expect(server.startedRoot, '/work/sea');
    await controller.dispose();
  });

  test('stop closes the preview and the server', () async {
    final panel = _FakePanel();
    final server = _FakeServer();
    final controller = HtmlPreviewSessionController(
      openPreview: (url) async {
        panel.open = true;
        panel.notifyListeners();
      },
      closePreview: () async {
        panel.open = false;
        panel.notifyListeners();
      },
      panel: panel,
      isPanelOpen: () => panel.open,
      isPlatformSupported: () => true,
      createServer: () => server,
      detector: _FixedDetector(
        const HtmlProjectEntry(
          absolutePath: '/work/sea/index.html',
          relativePath: 'index.html',
        ),
      ),
    );
    await controller.start(projectRoot: '/work/sea');

    await controller.stop();

    expect(controller.state.status, HtmlPreviewStatus.idle);
    expect(server.stopped, isTrue);
    expect(panel.open, isFalse);
    await controller.dispose();
  });

  test('fails when the built-in browser is unavailable', () async {
    final panel = _FakePanel();
    final controller = HtmlPreviewSessionController(
      openPreview: (url) async {},
      closePreview: () async {},
      panel: panel,
      isPanelOpen: () => panel.open,
      isPlatformSupported: () => false,
      detector: _FixedDetector(
        const HtmlProjectEntry(
          absolutePath: '/work/sea/index.html',
          relativePath: 'index.html',
        ),
      ),
    );

    await controller.start(projectRoot: '/work/sea');

    expect(controller.state.status, HtmlPreviewStatus.failed);
    expect(
      controller.state.failure,
      HtmlPreviewSessionController.unavailableFailure,
    );
    await controller.dispose();
  });

  test('closing the browser pane stops a running preview', () async {
    final panel = _FakePanel();
    final server = _FakeServer();
    final controller = HtmlPreviewSessionController(
      openPreview: (url) async {
        panel.open = true;
        panel.notifyListeners();
      },
      closePreview: () async {
        panel.open = false;
        panel.notifyListeners();
      },
      panel: panel,
      isPanelOpen: () => panel.open,
      isPlatformSupported: () => true,
      createServer: () => server,
      detector: _FixedDetector(
        const HtmlProjectEntry(
          absolutePath: '/work/sea/index.html',
          relativePath: 'index.html',
        ),
      ),
    );
    await controller.start(projectRoot: '/work/sea');

    panel.open = false;
    panel.notifyListeners();
    await pumpEventQueue();

    expect(controller.state.status, HtmlPreviewStatus.idle);
    expect(server.stopped, isTrue);
    await controller.dispose();
  });

  test('reload is a no-op until the preview is running', () async {
    var reloads = 0;
    final panel = _FakePanel();
    final controller = HtmlPreviewSessionController(
      openPreview: (url) async {
        panel.open = true;
        panel.notifyListeners();
      },
      closePreview: () async {},
      reloadPreview: () async {
        reloads += 1;
      },
      panel: panel,
      isPanelOpen: () => panel.open,
      isPlatformSupported: () => true,
      createServer: () => _FakeServer(),
      detector: _FixedDetector(
        const HtmlProjectEntry(
          absolutePath: '/work/sea/index.html',
          relativePath: 'index.html',
        ),
      ),
    );

    await controller.reload();
    expect(reloads, 0);

    await controller.start(projectRoot: '/work/sea');
    await controller.reload();
    expect(reloads, 1);
    await controller.dispose();
  });
}

class _FakePanel extends ChangeNotifier {
  bool open = false;
}

class _FixedDetector extends HtmlProjectDetector {
  const _FixedDetector(this.entry);

  final HtmlProjectEntry? entry;

  @override
  HtmlProjectEntry? detect(String projectRoot) => entry;
}

class _FakeServer implements HtmlPreviewStaticServer {
  String? startedRoot;
  bool stopped = false;

  @override
  Uri? get origin =>
      startedRoot == null ? null : Uri.parse('http://127.0.0.1:4321');

  @override
  bool get isRunning => startedRoot != null && !stopped;

  @override
  Future<Uri> start({required String projectRoot}) async {
    startedRoot = projectRoot;
    stopped = false;
    return origin!;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
