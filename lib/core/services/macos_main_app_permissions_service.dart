import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/logger.dart';

/// Query-only helper for TCC grants that the Caverno main app process holds.
///
/// Computer Use grants are owned by the Caverno Computer Use helper (see
/// [macos_computer_use_service.dart]). The main app, however, still relies
/// on Screen Recording for the Flutter chat input's clipboard-image paste
/// and any drag-related operations that go through `super_clipboard` /
/// `super_native_extensions`, which internally call
/// `CGWindowListCreate(Image)`. When the user revokes that grant, those
/// operations fail silently. This service exposes a cheap preflight check
/// the UI can call to detect that case and offer to open System Settings.
class MacosMainAppPermissions {
  const MacosMainAppPermissions._();

  static const _channel = MethodChannel('com.caverno/macos_computer_use');

  /// Whether the main app currently holds Screen Recording (Screen & System
  /// Audio Recording in macOS Sonoma+). Returns `true` on non-macOS hosts
  /// where the grant model does not apply. Returns `false` if the platform
  /// call fails for any reason, on the principle that the UI should err on
  /// the side of surfacing a recovery affordance.
  static Future<bool> isScreenCaptureGranted() async {
    if (!Platform.isMacOS) {
      return true;
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'mainAppScreenCapturePreflight',
      );
      return result?['screenCaptureGranted'] == true;
    } on PlatformException catch (error) {
      appLog('[MainAppPermissions] preflight failed: $error');
      return false;
    } on MissingPluginException {
      // The macOS plugin is not registered (running headless or in tests).
      return false;
    }
  }

  /// Open the macOS System Settings pane that owns the Screen Recording
  /// grant for the main app. No-op on non-macOS hosts.
  static Future<void> openScreenRecordingSettings() async {
    if (!Platform.isMacOS) {
      return;
    }
    final uri = Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
    );
    try {
      await launchUrl(uri);
    } catch (error) {
      appLog('[MainAppPermissions] failed to open settings: $error');
    }
  }
}
