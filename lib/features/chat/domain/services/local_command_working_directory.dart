import 'dart_project_tooling.dart';
import 'local_command_tool_contract.dart';

/// Resolves and fences the directory a local command runs in.
///
/// Kept apart from the handler because the two answer different questions:
/// the handler decides whether a command may run at all, this decides where
/// it would run and whether that place is inside the selected project.
abstract final class LocalCommandWorkingDirectory {
  static String? resolve(LocalCommandToolRequest request) {
    final allowedRoot = _normalizeAbsolutePath(
      request.allowedWorkingDirectoryRoot,
    );
    // A root that was supplied but is not absolute is a misconfiguration, and
    // still fails. No root at all means no coding project is selected, which
    // is the ordinary chat workspace: take the working directory the call
    // gives, exactly as this handler's callers did before extraction. Failing
    // here instead made every local command outside a coding project fail.
    if (allowedRoot == null &&
        request.allowedWorkingDirectoryRoot.trim().isNotEmpty) {
      return null;
    }
    final rawExplicit =
        (request.arguments['working_directory'] as String?)
                ?.trim()
                .isNotEmpty ==
            true
        ? (request.arguments['working_directory'] as String).trim()
        : (request.arguments['cwd'] as String?)?.trim() ?? '';
    final rawDefault = request.defaultWorkingDirectory?.trim() ?? '';
    if (allowedRoot == null) {
      final raw = rawExplicit.isNotEmpty ? rawExplicit : rawDefault;
      return raw.isEmpty ? null : _normalizeAbsolutePath(raw);
    }
    final rawWorkingDirectory = rawExplicit.isNotEmpty
        ? rawExplicit
        : rawDefault.isNotEmpty
        ? rawDefault
        : allowedRoot;
    final resolved = DartProjectPath.resolvePath(
      rawWorkingDirectory,
      projectRoot: allowedRoot,
    );
    return resolved == null ? null : _normalizeAbsolutePath(resolved);
  }

  static bool isAllowed(String workingDirectory, String rawRoot) {
    // Nothing to fence when no coding project is selected; the fence exists to
    // keep a command inside the project, not to require one.
    if (rawRoot.trim().isEmpty) return true;
    final root = _normalizeAbsolutePath(rawRoot);
    return root != null && DartProjectPath.isInsideRoot(workingDirectory, root);
  }

  static String? _normalizeAbsolutePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || !DartProjectPath.isAbsolutePath(trimmed)) {
      return null;
    }
    try {
      return Uri.file(trimmed).normalizePath().toFilePath();
    } catch (_) {
      return trimmed;
    }
  }
}
