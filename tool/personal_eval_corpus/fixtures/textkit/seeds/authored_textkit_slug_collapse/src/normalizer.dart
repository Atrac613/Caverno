/// Normalizes free-form user input before it is stored or compared.
class TextNormalizer {
  const TextNormalizer();

  /// Collapses runs of whitespace to a single space and trims the ends.
  String collapseWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Strips the whole trailing run of punctuation, keeping inner punctuation.
  ///
  /// "done." loses its period and "really?!" loses both marks, while "a,b,c."
  /// keeps its separators and "3.5" is untouched because its punctuation is
  /// not at the end.
  String stripTrailingPunctuation(String input) {
    var end = input.length;
    while (end > 0 && _isPunctuation(input[end - 1])) {
      end -= 1;
    }
    return input.substring(0, end);
  }

  /// Title-cases each whitespace-separated word, leaving other characters as
  /// they are so acronyms inside a word are not destroyed.
  String titleCase(String input) {
    return collapseWhitespace(input)
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Truncates to [maxChars], appending an ellipsis when it had to cut.
  ///
  /// The ellipsis counts toward the budget, so the result is never longer than
  /// [maxChars]. Input at or under the budget is returned untouched.
  String truncate(String input, int maxChars) {
    if (maxChars <= 0) {
      return '';
    }
    if (input.length <= maxChars) {
      return input;
    }
    if (maxChars <= 1) {
      return '\u2026'.substring(0, maxChars);
    }
    return '${input.substring(0, maxChars - 1)}\u2026';
  }

  /// Builds a URL-safe slug: lowercase, words joined by single hyphens, with
  /// no leading or trailing hyphen.
  String slugify(String input) {
    final lowered = collapseWhitespace(input).toLowerCase();
    final buffer = StringBuffer();
    for (final char in lowered.split('')) {
      final isWordChar = RegExp(r'[a-z0-9]').hasMatch(char);
      buffer.write(isWordChar ? char : '-');
    }
    final joined = buffer.toString();
    var start = 0;
    var end = joined.length;
    while (start < end && joined[start] == '-') {
      start += 1;
    }
    while (end > start && joined[end - 1] == '-') {
      end -= 1;
    }
    return joined.substring(start, end);
  }

  bool _isPunctuation(String char) => '.,;:!?'.contains(char);
}
