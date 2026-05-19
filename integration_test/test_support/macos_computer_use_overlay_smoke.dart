Map<String, dynamic> buildOverlaySmokeSummary({
  required Map<String, dynamic>? accessibilityOverlay,
  required Map<String, dynamic>? screenRecordingOverlay,
  required bool runOverlaySmoke,
  required bool requireOverlayReady,
}) {
  if (!runOverlaySmoke) {
    return {
      'status': 'not_run',
      'required': requireOverlayReady,
      'blockers': [if (requireOverlayReady) 'overlay_smoke_not_run'],
      'nextAction':
          'Rerun smoke with --overlay-smoke or --require-overlay to validate the permission overlay.',
    };
  }

  final accessibility = buildOverlaySmokeEntry(
    'accessibility',
    accessibilityOverlay,
  );
  final screenRecording = buildOverlaySmokeEntry(
    'screenRecording',
    screenRecordingOverlay,
  );
  final entries = [accessibility, screenRecording];
  final blockers = <String>[
    for (final entry in entries)
      for (final blocker in _stringList(entry['blockers'])) blocker,
  ];
  final ready = blockers.isEmpty;
  return {
    'status': ready ? 'ready' : 'failed',
    'required': requireOverlayReady,
    'accessibility': accessibility,
    'screenRecording': screenRecording,
    'blockers': blockers,
    'nextAction': ready
        ? 'Permission overlays are ready for hands-on drag validation.'
        : 'Inspect overlay response diagnostics and confirm the helper can present its floating panel.',
  };
}

Map<String, dynamic> buildOverlaySmokeEntry(
  String expectedPermission,
  Map<String, dynamic>? response,
) {
  final shown = response?['overlayShown'] == true;
  final tileReady = response?['draggableTileReady'] == true;
  final settingsOpened = response?['settingsOpened'] == true;
  final permission = response?['permission'];
  final permissionMatches = permission == expectedPermission;
  final foregroundPolicy =
      response?['overlayForegroundPolicy'] == 'accessory_overlay_front';
  final floatingPanel = response?['overlayIsFloatingPanel'] == true;
  final staysVisible = response?['overlayHidesOnDeactivate'] == false;
  final blockers = <String>[
    if (response == null) 'overlay_response_missing',
    if (response != null && !settingsOpened) 'overlay_settings_not_opened',
    if (response != null && !shown) 'overlay_window_not_shown',
    if (response != null && !foregroundPolicy)
      'overlay_foreground_policy_missing',
    if (response != null && !floatingPanel) 'overlay_not_floating_panel',
    if (response != null && !staysVisible) 'overlay_hides_on_deactivate',
    if (response != null && !tileReady) 'overlay_tile_not_ready',
    if (response != null && !permissionMatches) 'overlay_permission_mismatch',
  ];
  return {
    'permission': expectedPermission,
    'status': blockers.isEmpty ? 'ready' : 'failed',
    'settingsOpened': settingsOpened,
    'overlayShown': shown,
    'draggableTileReady': tileReady,
    'reportedPermission': permission,
    'overlayPlacement': response?['overlayPlacement'],
    'overlayForegroundPolicy': response?['overlayForegroundPolicy'],
    'overlayWindowLevelName': response?['overlayWindowLevelName'],
    'overlayCollectionBehavior': response?['overlayCollectionBehavior'],
    'overlayHidesOnDeactivate': response?['overlayHidesOnDeactivate'],
    'overlayIsFloatingPanel': response?['overlayIsFloatingPanel'],
    'overlayMode': response?['overlayMode'],
    'helperBundlePath': response?['helperBundlePath'],
    'grantTargetBundlePath': response?['grantTargetBundlePath'],
    'grantTargetDisplayName': response?['grantTargetDisplayName'],
    'grantTargetPermissionLabel': response?['grantTargetPermissionLabel'],
    'dragPasteboardTypes': _stringList(response?['dragPasteboardTypes']),
    'onboardingTransition': response?['lastOnboardingTransition'],
    'blockers': blockers,
  };
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return const <String>[];
}
