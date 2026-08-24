import 'dart:io';

/// Applies owner-only POSIX modes to local files that contain sensitive data.
final class SensitiveFilePermissions {
  const SensitiveFilePermissions._();

  static bool get isSupported =>
      Platform.isMacOS || Platform.isLinux || Platform.isAndroid;

  static Future<void> ownerOnlyDirectory(Directory directory) async {
    if (!isSupported) return;
    await _setMode(directory.path, '700');
  }

  static Future<void> ownerOnlyFile(File file) async {
    if (!isSupported) return;
    await _setMode(file.path, '600');
  }

  static void ownerOnlyDirectorySync(Directory directory) {
    if (!isSupported) return;
    _setModeSync(directory.path, '700');
  }

  static void ownerOnlyFileSync(File file) {
    if (!isSupported) return;
    _setModeSync(file.path, '600');
  }

  static Future<void> _setMode(String path, String mode) async {
    final result = await Process.run('chmod', <String>[mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Failed to set owner-only permissions: ${result.stderr}',
        path,
      );
    }
  }

  static void _setModeSync(String path, String mode) {
    final result = Process.runSync('chmod', <String>[mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Failed to set owner-only permissions: ${result.stderr}',
        path,
      );
    }
  }
}
