import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final macosAppMenuServiceProvider = Provider<MacosAppMenuService>((ref) {
  return const MacosAppMenuService();
});

/// Receives one-way commands from the native macOS application menu
/// (Caverno > Settings…). The native side invokes Dart methods on the
/// `com.caverno/app_menu` channel; this service routes them to callbacks.
class MacosAppMenuService {
  const MacosAppMenuService({MethodChannel channel = _defaultChannel})
    : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.caverno/app_menu',
  );

  final MethodChannel _channel;

  bool get isAvailable => Platform.isMacOS;

  /// Registers the handler for native menu commands. Only the `openSettings`
  /// command is wired today. No-op off macOS.
  void setOnOpenSettings(Future<void> Function() onOpenSettings) {
    if (!isAvailable) {
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openSettings':
          await onOpenSettings();
          return null;
        default:
          throw MissingPluginException(
            'Unknown app menu command: ${call.method}',
          );
      }
    });
  }

  /// Removes the registered handler. Call from `dispose`.
  void clear() {
    if (!isAvailable) {
      return;
    }
    _channel.setMethodCallHandler(null);
  }
}
