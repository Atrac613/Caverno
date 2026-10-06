import 'dart:io';

import 'shell_write_observation.dart';
import 'workspace_command_environment.dart';

/// Runs commands with filesystem, environment and network authority confined.
/// The approval gate may relax its host-write rule only for this exact route.
abstract final class LocalCommandWorkspaceContainment {
  static const executable = '/usr/bin/sandbox-exec';
  // Descriptor duplication (2>&1, <&0) and combined output (&>) are not jobs.
  static final _backgroundOperator = RegExp(r'(?<![&<>])&(?![&>])');

  static bool eligible({required String command, required String? root}) {
    if (!Platform.isMacOS || !File(executable).existsSync()) return false;
    if (command.trim().isEmpty) return false;
    // Visible background syntax and known host toolchains keep fresh approval.
    // Hidden script dependencies stay sandboxed and may fail, without an
    // uncontained retry.
    if (_backgroundOperator.hasMatch(command) ||
        ShellWriteObservation.reachesNestedSandbox(
          command.replaceAll("'", ' ').replaceAll('"', ' '),
        )) {
      return false;
    }
    if (root == null || root.trim().isEmpty) return false;
    try {
      return Directory(root).resolveSymbolicLinksSync().isNotEmpty;
    } on FileSystemException {
      return false;
    }
  }

  /// CPython's `mimetypes.knownfiles`, canonicalized. `mimetypes.init()`
  /// opens each one that exists, and the profile lets `stat` through while
  /// denying the read, so the open raised. pip resolves wheels through
  /// `mimetypes`, so every contained `python3 -m venv` and `ensurepip` failed
  /// on macOS's `/etc/apache2/mime.types` -- in sessions 17398f84, 016d4d5e
  /// and d27e7528 -- and the model fell back to host execution for pip.
  static const _mimeTypeTables = [
    '/private/etc/mime.types',
    '/private/etc/httpd/mime.types',
    '/private/etc/httpd/conf/mime.types',
    '/private/etc/apache/mime.types',
    '/private/etc/apache2/mime.types',
    '/usr/local/etc/httpd/conf/mime.types',
    '/usr/local/lib/netscape/mime.types',
    '/usr/local/etc/mime.types',
  ];

  static String profile({required String root, required String scratch}) {
    String literal(String value) =>
        '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    return '(version 1)(allow default)'
        '(deny file-read-data)'
        // dyld opens the root directory during process startup. A literal
        // grant does not allow reading its descendants.
        '(allow file-read-data (literal "/"))'
        '(allow file-read-data (subpath ${literal(root)}))'
        '(allow file-read-data (subpath ${literal(scratch)}))'
        '(allow file-read-data (regex #"^/dev/(null|zero|random|urandom|fd(/.*)?)\$"))'
        '${WorkspaceCommandEnvironment.readRoots().map((path) => '(allow file-read-data (subpath ${literal(path)}))').join()}'
        '(allow file-read-data (literal "/private/etc/localtime") '
        '(literal "/private/etc/passwd") (literal "/private/etc/group") '
        // xcrun refuses to run a tool until it reads the license acceptance.
        '(literal "/Library/Preferences/com.apple.dt.Xcode.plist")'
        '${_mimeTypeTables.map((path) => ' (literal ${literal(path)})').join()})'
        '(deny file-write*)'
        '(allow file-write* (subpath ${literal(root)}))'
        '(allow file-write* (subpath ${literal(scratch)}))'
        '(allow file-write* (regex #"^/dev/(null|zero|fd(/.*)?)\$"))'
        '(deny file-write* (subpath ${literal('$root/.git')}))'
        '(deny file-write* (subpath ${literal('$root/.caverno')}))'
        '(deny appleevent-send)(deny mach-lookup)(deny network*)'
        '(deny process-info*)(allow process-info* (target same-sandbox))'
        '(deny ipc-posix*)'
        '(deny signal)(allow signal (target same-sandbox))';
  }

  static Future<LocalCommandWorkspaceSandbox?> prepare({
    required String command,
    required String root,
  }) async {
    if (!eligible(command: command, root: root)) return null;
    try {
      final canonicalRoot = Directory(root).resolveSymbolicLinksSync();
      final scratch = await Directory.systemTemp.createTemp('caverno-command-');
      return LocalCommandWorkspaceSandbox(
        profile: profile(
          root: canonicalRoot,
          scratch: scratch.resolveSymbolicLinksSync(),
        ),
        scratch: scratch,
      );
    } on FileSystemException {
      return null;
    }
  }
}

final class LocalCommandWorkspaceSandbox {
  const LocalCommandWorkspaceSandbox({
    required this.profile,
    required this.scratch,
  });

  final String profile;
  final Directory scratch;

  Map<String, String> environment(Map<String, String> source) =>
      WorkspaceCommandEnvironment.isolated(
        source: source,
        scratch: scratch.path,
      );

  Future<void> dispose() async {
    try {
      await scratch.delete(recursive: true);
    } on FileSystemException {
      // A failed cleanup must not change the command's recorded outcome.
    }
  }
}
