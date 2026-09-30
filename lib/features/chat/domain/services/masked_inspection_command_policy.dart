import 'literal_shell_words.dart';

/// Recognizes environment inspection whose optional lookup may be absent.
/// Unknown commands retain the masked-status failure diagnostic.
abstract final class MaskedInspectionCommandPolicy {
  static bool applies(String command) {
    final match = RegExp(r'^(.+)\s*\|\|\s*true\s*$').firstMatch(command.trim());
    if (match == null) return false;
    final segments = match[1]!.split('&&');
    for (final segment in segments) {
      final words = LiteralShellWords.parse(
        segment.trim().replaceFirst(RegExp(r'\s+2>\s*/dev/null\s*$'), ''),
      );
      if (words == null) return false;
      final executable = words.first;
      final args = words.skip(1).toList();
      final valid = switch (executable) {
        'ls' => true,
        'pwd' => args.isEmpty,
        'which' =>
          args.isNotEmpty &&
              args.every(
                (arg) =>
                    RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(arg) &&
                    !arg.startsWith('-'),
              ),
        'cd' =>
          args.length == 1 &&
              args.single.isNotEmpty &&
              !args.single.startsWith('-'),
        _ =>
          RegExp(r'^python(?:\d+(?:\.\d+)*)?$').hasMatch(executable) &&
              args.length == 1 &&
              const {'--version', '-V'}.contains(args.single),
      };
      if (!valid) return false;
    }
    return true;
  }
}
