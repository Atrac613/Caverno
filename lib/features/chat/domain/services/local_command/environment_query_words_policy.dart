import 'package:path/path.dart' as path;

import '../python/pytest_metadata_inspection_policy.dart';

/// Recognizes one environment query after shell syntax has been validated.
abstract final class EnvironmentQueryWordsPolicy {
  static bool applies(
    List<String> words, {
    required bool limited,
    required bool allowPackageImports,
  }) {
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
    return switch (executable) {
      'ls' => true,
      'pwd' => args.isEmpty,
      'which' => _names(args.firstOrNull == '-a' ? args.skip(1) : args),
      // POSIX `which`; a failed probe using it blocked session 64bbc516.
      'command' =>
        const {'-v', '-V'}.contains(args.firstOrNull) && _names(args.skip(1)),
      'cd' =>
        args.length == 1 &&
            args.single.isNotEmpty &&
            !args.single.startsWith('-'),
      _ =>
        pipMetadata ||
            (python &&
                (allowPackageImports &&
                        PytestMetadataInspectionPolicy.applies(args) ||
                    args.length == 1 &&
                        const {'--version', '-V'}.contains(args.single))),
    };
  }

  static bool _names(Iterable<String> args) =>
      args.isNotEmpty &&
      args.every(
        (arg) => RegExp(r'^[a-zA-Z0-9_.][a-zA-Z0-9_.-]*$').hasMatch(arg),
      );

  static bool _isPackageQuery(List<String> args) =>
      args.length >= 2 && args.first == 'show' && _names(args.skip(1));
}
