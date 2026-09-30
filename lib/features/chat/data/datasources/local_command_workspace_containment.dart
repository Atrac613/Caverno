import 'dart:io';

import 'shell_write_observation.dart';

/// Runs foreground shell commands with writes confined by macOS.
/// The approval gate may relax its host-write rule only for this exact route.
abstract final class LocalCommandWorkspaceContainment {
  static const executable = '/usr/bin/sandbox-exec';
  static final _backgroundOperator = RegExp(r'(?<!&)&(?!&)');

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

  Future<void> dispose() async {
    try {
      await scratch.delete(recursive: true);
    } on FileSystemException {
      // A failed cleanup must not change the command's recorded outcome.
    }
  }
}
