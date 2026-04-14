import 'package:shared_preferences/shared_preferences.dart';

class WindowGeometry {
  const WindowGeometry({
    required this.width,
    required this.height,
    this.x,
    this.y,
  });

  final double width;
  final double height;
  final double? x;
  final double? y;

  bool get hasPosition => x != null && y != null;
}

class WindowSettingsService {
  WindowSettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _keyWidth = 'window_width';
  static const _keyHeight = 'window_height';
  static const _keyX = 'window_x';
  static const _keyY = 'window_y';

  static const double defaultWidth = 1280;
  static const double defaultHeight = 800;
  static const double minWidth = 480;
  static const double minHeight = 600;

  WindowGeometry load() {
    final width = _prefs.getDouble(_keyWidth) ?? defaultWidth;
    final height = _prefs.getDouble(_keyHeight) ?? defaultHeight;
    final x = _prefs.getDouble(_keyX);
    final y = _prefs.getDouble(_keyY);

    return WindowGeometry(
      width: width.clamp(minWidth, double.infinity),
      height: height.clamp(minHeight, double.infinity),
      x: x,
      y: y,
    );
  }

  Future<void> save(WindowGeometry geometry) async {
    await Future.wait([
      _prefs.setDouble(_keyWidth, geometry.width),
      _prefs.setDouble(_keyHeight, geometry.height),
      if (geometry.x != null) _prefs.setDouble(_keyX, geometry.x!),
      if (geometry.y != null) _prefs.setDouble(_keyY, geometry.y!),
    ]);
  }
}
