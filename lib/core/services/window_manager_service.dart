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

  Future<void> initialize() async {
    await windowManager.ensureInitialized();

    final geometry = _settingsService.load();

    final windowOptions = WindowOptions(
      size: Size(geometry.width, geometry.height),
      minimumSize: const Size(
        WindowSettingsService.minWidth,
        WindowSettingsService.minHeight,
      ),
      center: !geometry.hasPosition,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (geometry.hasPosition && _isPositionOnScreen(geometry.x!, geometry.y!)) {
        await windowManager.setPosition(Offset(geometry.x!, geometry.y!));
      }
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(this);
  }

  @override
  void onWindowResized() {
    _saveCurrentGeometry();
  }

  @override
  void onWindowMoved() {
    _saveCurrentGeometry();
  }

  void _saveCurrentGeometry() {
    _saveDebouncer.run(() async {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      await _settingsService.save(WindowGeometry(
        width: size.width,
        height: size.height,
        x: position.dx,
        y: position.dy,
      ));
    });
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
