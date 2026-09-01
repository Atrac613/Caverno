import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../../core/services/macos_main_app_permissions_service.dart';

/// Surfaces a recovery snackbar when image paste needs Screen Recording.
///
/// On macOS, super_clipboard / super_native_extensions reads of image
/// clipboard data go through CoreGraphics window APIs that require Screen
/// Recording. When the user has revoked that grant, the read fails silently.
Future<void> surfaceMacOSScreenRecordingHintIfNeeded(
  BuildContext context,
) async {
  if (!Platform.isMacOS) return;
  final granted = await MacosMainAppPermissions.isScreenCaptureGranted();
  if (granted) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: const Text(
        'Image paste requires Screen Recording for Caverno. '
        'Grant it in System Settings to enable clipboard images.',
      ),
      action: SnackBarAction(
        label: 'Open Settings',
        onPressed: MacosMainAppPermissions.openScreenRecordingSettings,
      ),
      duration: const Duration(seconds: 8),
    ),
  );
}
