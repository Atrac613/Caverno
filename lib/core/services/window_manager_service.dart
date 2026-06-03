import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../utils/debouncer.dart';
import 'window_settings_service.dart';

class WindowManagerService with WindowListener {
  WindowManagerService(this._settingsService);

  final WindowSettingsService _settingsService;
  final Debouncer _saveDebouncer = Debouncer(
    duration: const Duration(seconds: 1),
  );
  bool _isQuitting = false;

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);

    final geometry = _settingsService.load();

    final windowOptions = WindowOptions(
      size: Size(geometry.width, geometry.height),
      minimumSize: const Size(
        WindowSettingsService.minWidth,
        WindowSettingsService.minHeight,
      ),
      center: !geometry.hasPosition,
    );

    unawaited(_showWhenReady(windowOptions, geometry));

    windowManager.addListener(this);
  }

  Future<void> _showWhenReady(
    WindowOptions windowOptions,
    WindowGeometry geometry,
  ) async {
    try {
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        if (geometry.hasPosition &&
            _isPositionOnScreen(geometry.x!, geometry.y!)) {
          await windowManager.setPosition(Offset(geometry.x!, geometry.y!));
        }
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  @override
  void onWindowResized() {
    _saveCurrentGeometry();
  }

  @override
  void onWindowMoved() {
    _saveCurrentGeometry();
  }

  @override
  void onWindowClose() {
    if (_isQuitting) {
      return;
    }

    unawaited(_moveToBackground());
  }

  Future<void> _moveToBackground() async {
    await _saveCurrentGeometryNow();
    if (Platform.isWindows || Platform.isLinux) {
      await windowManager.minimize();
      return;
    }

    await windowManager.hide();
  }

  Future<void> quitApplication() async {
    _isQuitting = true;
    await _saveCurrentGeometryNow();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  void _saveCurrentGeometry() {
    _saveDebouncer.run(() async {
      await _saveCurrentGeometryNow();
    });
  }

  Future<void> _saveCurrentGeometryNow() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    await _settingsService.save(
      WindowGeometry(
        width: size.width,
        height: size.height,
        x: position.dx,
        y: position.dy,
      ),
    );
  }

  /// Rejects saved positions that are clearly off-screen
  /// (e.g. disconnected external monitor).
  bool _isPositionOnScreen(double x, double y) {
    return x > -200 && y > -200 && x < 10000 && y < 10000;
  }

  void dispose() {
    windowManager.removeListener(this);
    _saveDebouncer.dispose();
  }
}
