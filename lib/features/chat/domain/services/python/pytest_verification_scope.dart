import 'dart:convert';

import 'package:path/path.dart' as path;

/// Compares executed checks while retaining exact invocations for output reuse.
abstract final class PytestVerificationScope {
  static String key(String directory, List<String> words) {
    final arguments = words
        .skip(path.basename(words.first) == 'pytest' ? 1 : 3)
        .toList();
    final retained = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--') {
        retained.addAll(arguments.skip(index));
        break;
      }
      if (RegExp(r'^-[vq]+$').hasMatch(argument) ||
          const {'--verbose', '--quiet'}.contains(argument)) {
        continue;
      }
      retained.add(argument);
      // Unknown options may consume the next word, including a quoted -q or
      // -v selection value. Keep both rather than guessing their arity.
      if (argument.startsWith('-') &&
          !argument.contains('=') &&
          index + 1 < arguments.length) {
        retained.add(arguments[++index]);
      }
    }
    return jsonEncode([path.normalize(directory), 'pytest', retained]);
  }
}
