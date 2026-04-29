import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_overlay_smoke.dart';

void main() {
  group('Computer Use overlay smoke summary', () {
    test('marks complete foreground overlay diagnostics as ready', () {
      final summary = buildOverlaySmokeSummary(
        accessibilityOverlay: _overlay('accessibility'),
        screenRecordingOverlay: _overlay('screenRecording'),
        runOverlaySmoke: true,
        requireOverlayReady: true,
      );

      expect(summary['status'], 'ready');
      expect(summary['blockers'], isEmpty);
    });

    test('blocks when foreground policy is missing', () {
      final summary = buildOverlaySmokeSummary(
        accessibilityOverlay: _overlay('accessibility')
          ..remove('overlayForegroundPolicy'),
        screenRecordingOverlay: _overlay('screenRecording'),
        runOverlaySmoke: true,
        requireOverlayReady: true,
      );

      expect(summary['status'], 'failed');
      expect(
        summary['blockers'],
        contains('overlay_foreground_policy_missing'),
      );
    });

    test('blocks when the overlay is not a floating panel', () {
      final summary = buildOverlaySmokeSummary(
        accessibilityOverlay: _overlay(
          'accessibility',
          overlayIsFloatingPanel: false,
        ),
        screenRecordingOverlay: _overlay('screenRecording'),
        runOverlaySmoke: true,
        requireOverlayReady: true,
      );

      expect(summary['status'], 'failed');
      expect(summary['blockers'], contains('overlay_not_floating_panel'));
    });

    test('blocks when the overlay hides on deactivate', () {
      final summary = buildOverlaySmokeSummary(
        accessibilityOverlay: _overlay(
          'accessibility',
          overlayHidesOnDeactivate: true,
        ),
        screenRecordingOverlay: _overlay('screenRecording'),
        runOverlaySmoke: true,
        requireOverlayReady: true,
      );

      expect(summary['status'], 'failed');
      expect(summary['blockers'], contains('overlay_hides_on_deactivate'));
    });
  });
}

Map<String, dynamic> _overlay(
  String permission, {
  bool overlayIsFloatingPanel = true,
  bool overlayHidesOnDeactivate = false,
}) {
  return <String, dynamic>{
    'permission': permission,
    'settingsOpened': true,
    'overlayShown': true,
    'draggableTileReady': true,
    'overlayForegroundPolicy': 'accessory_overlay_front',
    'overlayIsFloatingPanel': overlayIsFloatingPanel,
    'overlayHidesOnDeactivate': overlayHidesOnDeactivate,
    'overlayPlacement': 'system_settings_window',
    'overlayMode': 'floating_helper_panel',
    'dragPasteboardTypes': <String>['public.file-url'],
  };
}
