class MacosComputerUseBackendInfo {
  const MacosComputerUseBackendInfo({
    required this.displayName,
    required this.bundleIdentifier,
    required this.executionMode,
    required this.permissionOwnerName,
    required this.targetHelperName,
    required this.targetHelperBundleIdentifier,
    required this.usesSeparateHelper,
  });

  final String displayName;
  final String bundleIdentifier;
  final String executionMode;
  final String permissionOwnerName;
  final String targetHelperName;
  final String targetHelperBundleIdentifier;
  final bool usesSeparateHelper;

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'bundleIdentifier': bundleIdentifier,
      'executionMode': executionMode,
      'permissionOwnerName': permissionOwnerName,
      'targetHelperName': targetHelperName,
      'targetHelperBundleIdentifier': targetHelperBundleIdentifier,
      'usesSeparateHelper': usesSeparateHelper,
    };
  }
}

class MacosComputerUseBackends {
  const MacosComputerUseBackends._();

  static const mainAppDisplayName = 'Caverno';
  static const mainAppBundleIdentifier = 'com.noguwo.apps.caverno';
  static const helperDisplayName = 'Caverno Computer Use';
  static const helperBundleIdentifier = 'com.noguwo.apps.caverno.computer-use';

  static const inProcessCompatibility = MacosComputerUseBackendInfo(
    displayName: mainAppDisplayName,
    bundleIdentifier: mainAppBundleIdentifier,
    executionMode: 'in_process_compatibility',
    permissionOwnerName: mainAppDisplayName,
    targetHelperName: helperDisplayName,
    targetHelperBundleIdentifier: helperBundleIdentifier,
    usesSeparateHelper: false,
  );
}

class MacosComputerUsePermissionSnapshot {
  const MacosComputerUsePermissionSnapshot({
    required this.accessibilityGranted,
    required this.screenCaptureGranted,
    required this.systemAudioRecordingSupported,
  });

  factory MacosComputerUsePermissionSnapshot.fromMap(
    Map<String, dynamic>? values,
  ) {
    return MacosComputerUsePermissionSnapshot(
      accessibilityGranted: _boolValue(values?['accessibilityGranted']),
      screenCaptureGranted: _boolValue(values?['screenCaptureGranted']),
      systemAudioRecordingSupported: _boolValue(
        values?['systemAudioRecordingSupported'],
      ),
    );
  }

  final bool? accessibilityGranted;
  final bool? screenCaptureGranted;
  final bool? systemAudioRecordingSupported;

  bool get hasRequiredPermissions =>
      accessibilityGranted == true && screenCaptureGranted == true;

  List<String> get missingPermissionLabels {
    return [
      if (accessibilityGranted != true) 'Accessibility',
      if (screenCaptureGranted != true) 'Screen & System Audio Recording',
    ];
  }

  Map<String, dynamic> toJson() {
    return {
      'accessibilityGranted': accessibilityGranted,
      'screenCaptureGranted': screenCaptureGranted,
      'systemAudioRecordingSupported': systemAudioRecordingSupported,
    };
  }

  static bool? _boolValue(Object? value) {
    return value is bool ? value : null;
  }
}

class MacosComputerUseSetupChecklist {
  const MacosComputerUseSetupChecklist({
    required this.backend,
    required this.permissions,
  });

  final MacosComputerUseBackendInfo backend;
  final MacosComputerUsePermissionSnapshot? permissions;

  bool get hasSnapshot => permissions != null;

  bool get isReady => hasSnapshot && permissions!.hasRequiredPermissions;

  List<String> get missingPermissionLabels {
    return permissions?.missingPermissionLabels ??
        const ['Accessibility', 'Screen & System Audio Recording'];
  }

  String get title {
    if (isReady) {
      return 'Ready for visual, input, and audio smoke checks';
    }
    if (hasSnapshot) {
      return 'Action required: ${missingPermissionLabels.join(', ')}';
    }
    return 'Refresh permissions before running smoke checks';
  }

  String get subtitle {
    if (isReady) {
      return 'Run screenshots first, then arm input or audio checks only when needed.';
    }
    if (hasSnapshot) {
      return 'Open System Settings, grant ${backend.permissionOwnerName}, then refresh permissions.';
    }
    return 'Use Refresh to load the current macOS privacy state.';
  }

  Map<String, dynamic> toJson() {
    return {
      'backend': backend.toJson(),
      'hasSnapshot': hasSnapshot,
      'isReady': isReady,
      'missingPermissionLabels': missingPermissionLabels,
      'permissions': permissions?.toJson(),
    };
  }
}
