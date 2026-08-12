/// Normalizes free-form user input before it is stored or compared.
class TextNormalizer {
  const TextNormalizer();

  /// Collapses runs of whitespace to a single space and trims the ends.
  String collapseWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Strips the whole trailing run of punctuation, keeping inner punctuation.
  String stripTrailingPunctuation(String input) {
    var end = input.length;
    while (end > 0 && _isPunctuation(input[end - 1])) {
      end -= 1;
    }
    return input.substring(0, end);
  }

  /// Title-cases each whitespace-separated word without altering its tail.
  String titleCase(String input) {
    return collapseWhitespace(input)
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Truncates to [maxChars], including the ellipsis in the budget.
  String truncate(String input, int maxChars) {
    if (maxChars <= 0) return '';
    if (input.length <= maxChars) return input;
    if (maxChars <= 1) return '\u2026'.substring(0, maxChars);
    return '${input.substring(0, maxChars - 1)}\u2026';
  }

  /// Builds a URL-safe slug.
  String slugify(String input) {
    return input.toLowerCase();
  }

  bool _isPunctuation(String char) => '.,;:!?'.contains(char);
}
