import 'background_process_tool_contract.dart';
import 'dart_project_tooling.dart';

final class BackgroundProcessPathPolicy {
  const BackgroundProcessPathPolicy();

  String? resolveWorkingDirectory(BackgroundProcessToolRequest request) {
    final root = _normalizeAbsolutePath(request.allowedWorkingDirectoryRoot);
    if (root == null) return null;
    var raw = _pathArgument(request, 'working_directory');
    if (raw.isEmpty) raw = _pathArgument(request, 'cwd');
    final fallback = request.defaultWorkingDirectory?.trim() ?? '';
    if (raw.isEmpty) raw = fallback.isEmpty ? root : fallback;
    final resolved = DartProjectPath.resolvePath(raw, projectRoot: root);
    return resolved == null ? null : _normalizeAbsolutePath(resolved);
  }

  String cancelWorkingDirectory(BackgroundProcessToolRequest request) {
    final fallback = request.defaultWorkingDirectory?.trim() ?? '';
    final root = request.allowedWorkingDirectoryRoot.trim();
    return fallback.isNotEmpty ? fallback : (root.isEmpty ? '.' : root);
  }

  bool isAllowedWorkingDirectory(String workingDirectory, String rawRoot) {
    final root = _normalizeAbsolutePath(rawRoot);
    return root != null && DartProjectPath.isInsideRoot(workingDirectory, root);
  }

  String _pathArgument(BackgroundProcessToolRequest request, String name) =>
      (request.arguments[name] as String?)?.trim() ?? '';

  String? _normalizeAbsolutePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || !DartProjectPath.isAbsolutePath(trimmed)) {
      return null;
    }
    return Uri.file(trimmed).normalizePath().toFilePath();
  }
}
