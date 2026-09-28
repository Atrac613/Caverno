import 'dart:io';

/// Runs a foreground Python shell command with writes confined by macOS.
/// The approval gate may relax its host-write rule only for this exact route.
abstract final class PythonWorkspaceContainment {
  static const executable = '/usr/bin/sandbox-exec';
  static final _pythonCommand = RegExp(
    r'^(?:cd\s+(?:\x27[^\x27]+\x27|"[^"]+"|[^\s;&|]+)\s*&&\s*)?'
    r'(?:[^\s;&|]*/)?python(?:3(?:\.\d+)?)?(?:\s|$)',
  );

  static bool eligible({required String command, required String? root}) {
    if (!Platform.isMacOS || !File(executable).existsSync()) return false;
    if (!_pythonCommand.hasMatch(command.trim())) return false;
    if (root == null || root.trim().isEmpty) return false;
    try {
      return Directory(root).resolveSymbolicLinksSync().isNotEmpty;
    } on FileSystemException {
      return false;
    }
  }

  static String profile({required String root, required String scratch}) {
    String literal(String value) =>
        '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    return '(version 1)(allow default)'
        '(deny file-write*)'
        '(allow file-write* (subpath ${literal(root)}))'
        '(allow file-write* (subpath ${literal(scratch)}))'
        '(allow file-write* (subpath "/dev"))'
        '(deny file-write* (subpath ${literal('$root/.git')}))'
        '(deny appleevent-send)(deny mach-lookup)(deny network*)';
  }

  static Future<PythonWorkspaceSandbox?> prepare({
    required String command,
    required String root,
  }) async {
    if (!eligible(command: command, root: root)) return null;
    try {
      final canonicalRoot = Directory(root).resolveSymbolicLinksSync();
      final scratch = await Directory.systemTemp.createTemp('caverno-python-');
      return PythonWorkspaceSandbox(
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

final class PythonWorkspaceSandbox {
  const PythonWorkspaceSandbox({required this.profile, required this.scratch});

  final String profile;
  final Directory scratch;

  Future<void> dispose() async {
    try {
      await scratch.delete(recursive: true);
    } on FileSystemException {
      // A failed cleanup must not change the command's recorded outcome.
    }
  }
}
