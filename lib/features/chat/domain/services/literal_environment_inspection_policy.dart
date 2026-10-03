import 'package:path/path.dart' as path;

import 'literal_shell_words.dart';

/// Recognizes literal environment queries without expansion or writable output.
abstract final class LiteralEnvironmentInspectionPolicy {
  static bool applies(String command) {
    final segments = command.split(RegExp(r'&&|;'));
    for (final segment in segments) {
      final query = segment.trim();
      final limiter = RegExp(r'\s*\|\s*(?:head|tail)\s+-(?:n\s*)?[1-9]\d*\s*$');
      final limited = limiter.hasMatch(query);
      final words = LiteralShellWords.parse(
        query
            .replaceFirst(limiter, '')
            .trim()
            .replaceFirst(RegExp(r'\s+2>\s*/dev/null\s*$'), ''),
      );
      if (words == null) return false;
      final executable = words.first;
      final args = words.skip(1).toList();
      final basename = path.basename(executable);
      final python = RegExp(r'^python(?:\d+(?:\.\d+)*)?$').hasMatch(basename);
      final pipMetadata =
          (python &&
              args.length >= 4 &&
              args[0] == '-m' &&
              args[1] == 'pip' &&
              _isPackageQuery(args.skip(2).toList())) ||
          (RegExp(r'^pip(?:\d+(?:\.\d+)*)?$').hasMatch(basename) &&
              _isPackageQuery(args));
      if (limited && !pipMetadata) return false;
      final valid = switch (executable) {
        'ls' => true,
        'pwd' => args.isEmpty,
        'which' =>
          (args.firstOrNull == '-a' ? args.skip(1) : args).isNotEmpty &&
              (args.firstOrNull == '-a' ? args.skip(1) : args).every(
                (arg) =>
                    RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(arg) &&
                    !arg.startsWith('-'),
              ),
        'cd' =>
          args.length == 1 &&
              args.single.isNotEmpty &&
              !args.single.startsWith('-'),
        _ =>
          pipMetadata ||
              (python &&
                  args.length == 1 &&
                  const {'--version', '-V'}.contains(args.single)),
      };
      if (!valid) return false;
    }
    return true;
  }

  static bool _isPackageQuery(List<String> args) =>
      args.length >= 2 &&
      args.first == 'show' &&
      args
          .skip(1)
          .every(
            (name) => RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$').hasMatch(name),
          );
}
