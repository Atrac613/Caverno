import 'package:path/path.dart' as path;

import 'pytest_metadata_inspection_policy.dart';

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
                (allowPackageImports &&
                        PytestMetadataInspectionPolicy.applies(args) ||
                    args.length == 1 &&
                        const {'--version', '-V'}.contains(args.single))),
    };
    return valid;
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
