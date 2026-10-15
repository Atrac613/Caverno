/// Splits [command] at top-level `;`, newline, `&&` and `||`, recording in
/// [separators] the operator that ended each segment.
List<String> splitShellSegments(String command, {List<String>? separators}) {
  final segments = <String>[];
  final buffer = StringBuffer();
  String? quoteChar;

  for (var i = 0; i < command.length; i++) {
    final char = command[i];

    if (quoteChar != null) {
      if (char == '\\' && i + 1 < command.length) {
        i += 1;
        buffer.write(command[i]);
        continue;
      }
      if (char == quoteChar) {
        quoteChar = null;
      } else {
        buffer.write(char);
      }
      continue;
    }

    if (char == '"' || char == "'") {
      quoteChar = char;
      continue;
    }

    if (char == '\\' && i + 1 < command.length) {
      i += 1;
      buffer.write(command[i]);
      continue;
    }

    if (char == ';' || char == '\n') {
      final segment = buffer.toString().trim();
      if (segment.isNotEmpty) {
        segments.add(segment);
        separators?.add(';');
      }
      buffer.clear();
      continue;
    }

    if ((char == '&' || char == '|') &&
        i + 1 < command.length &&
        command[i + 1] == char) {
      final segment = buffer.toString().trim();
      if (segment.isNotEmpty) {
        segments.add(segment);
        separators?.add('$char$char');
      }
      buffer.clear();
      i += 1;
      continue;
    }

    buffer.write(char);
  }

  final trailing = buffer.toString().trim();
  if (trailing.isNotEmpty) {
    segments.add(trailing);
  }
  return segments;
}
