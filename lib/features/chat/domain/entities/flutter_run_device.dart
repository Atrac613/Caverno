/// One target reported by `flutter devices --machine`.
class FlutterRunDevice {
  const FlutterRunDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    this.isEmulator = false,
    this.isSupported = true,
    this.sdk,
  });

  final String id;
  final String name;
  final String targetPlatform;
  final bool isEmulator;

  /// False for a device the toolchain lists but cannot build for. Kept rather
  /// than filtered so the picker can explain the absence instead of showing a
  /// shorter list than `flutter devices` did.
  final bool isSupported;
  final String? sdk;

  /// Name plus the platform, because "iPhone 16" and "iPhone 16" differ only by
  /// simulator vs device on a normal developer machine.
  String get displayName {
    final platform = targetPlatform.trim();
    return platform.isEmpty ? name : '$name ($platform)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FlutterRunDevice &&
            id == other.id &&
            name == other.name &&
            targetPlatform == other.targetPlatform &&
            isEmulator == other.isEmulator &&
            isSupported == other.isSupported &&
            sdk == other.sdk;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, targetPlatform, isEmulator, isSupported, sdk);

  @override
  String toString() => 'FlutterRunDevice($id, $name, $targetPlatform)';
}
