class MarkdownRenderSanitizer {
  MarkdownRenderSanitizer._();

  static final _htmlLikeTagPattern = RegExp(r'<(/?[a-zA-Z][^>]*)>');
  static final _fenceLinePattern = RegExp(r'^\s*```');
  static final _unorderedListMarkerPattern = RegExp(r'[-+*][ \t]+');
  static final _orderedListMarkerPattern = RegExp(r'\d{1,9}[.)][ \t]+');

  /// Normalizes markdown text before it reaches the renderer.
  ///
  /// This keeps two known parser edge cases from crashing the UI:
  /// 1. Stray HTML-like tags outside code spans.
  /// 2. Malformed lines that start like a link reference definition.
  static String sanitize(String text) {
    final buffer = StringBuffer();
    var insideFence = false;
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_fenceLinePattern.hasMatch(line)) {
        insideFence = !insideFence;
        buffer.write(line);
      } else if (insideFence) {
        buffer.write(line);
      } else {
        buffer.write(_sanitizeLine(line));
      }

      if (i != lines.length - 1) {
        buffer.write('\n');
      }
    }

    return buffer.toString();
  }

  static String _sanitizeLine(String line) {
    return _escapeOutsideInlineCode(_escapeMalformedReferenceStart(line));
  }

  static String _escapeMalformedReferenceStart(String line) {
    final openingBracketIndex = _findLeadingReferenceBracketIndex(line);
    if (openingBracketIndex == null) {
      return line;
    }

    if (!_hasMalformedLeadingReferenceLabel(line, openingBracketIndex)) {
      return line;
    }

    return '${line.substring(0, openingBracketIndex)}\\${line.substring(openingBracketIndex)}';
  }

  static int? _findLeadingReferenceBracketIndex(String line) {
    var index = 0;

    while (index < line.length) {
      index += _countLeadingSpaces(line, index, maxSpaces: 3);
      if (index >= line.length) {
        return null;
      }

      if (line[index] == '[') {
        return index;
      }

      if (line[index] == '>') {
        index++;
        if (index < line.length && line[index] == ' ') {
          index++;
        }
        continue;
      }

      final unorderedListMarker = _unorderedListMarkerPattern.matchAsPrefix(
        line,
        index,
      );
      if (unorderedListMarker != null) {
        index = unorderedListMarker.end;
        continue;
      }

      final orderedListMarker = _orderedListMarkerPattern.matchAsPrefix(
        line,
        index,
      );
      if (orderedListMarker != null) {
        index = orderedListMarker.end;
        continue;
      }

      return null;
    }

    return null;
  }

  static int _countLeadingSpaces(
    String line,
    int startIndex, {
    required int maxSpaces,
  }) {
    var count = 0;
    while (count < maxSpaces && startIndex + count < line.length) {
      if (line[startIndex + count] != ' ') {
        break;
      }
      count++;
    }
    return count;
  }

  static bool _hasMalformedLeadingReferenceLabel(
    String line,
    int openingBracketIndex,
  ) {
    var index = openingBracketIndex + 1;
    while (index < line.length) {
      final character = line[index];
      if (character == '\\') {
        if (index == line.length - 1) {
          return true;
        }
        index += 2;
        continue;
      }
      if (character == '[') {
        return true;
      }
      if (character == ']') {
        return false;
      }
      index++;
    }
    return true;
  }

  /// Escapes HTML-like tags in a single line while leaving inline
  /// backtick-delimited spans untouched.
  static String _escapeOutsideInlineCode(String line) {
    final buffer = StringBuffer();
    var inCode = false;
    var i = 0;
    while (i < line.length) {
      final ch = line[i];
      if (ch == '`') {
        inCode = !inCode;
        buffer.write(ch);
        i++;
        continue;
      }
      if (inCode) {
        buffer.write(ch);
        i++;
        continue;
      }

      final match = _htmlLikeTagPattern.matchAsPrefix(line, i);
      if (match != null) {
        buffer.write('&lt;${match.group(1)}&gt;');
        i = match.end;
        continue;
      }

      buffer.write(ch);
      i++;
    }
    return buffer.toString();
  }
}
