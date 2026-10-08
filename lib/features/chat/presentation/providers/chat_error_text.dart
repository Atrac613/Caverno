import 'dart:math' as math;

/// Bounds and normalizes raw error text before it is shown or logged.
///
/// Session 7171235a: a SQLite failure carried the whole conversation in its
/// message, a digit run in it matched "401", and a local storage failure was
/// shown as a rejected API key above 13,000 pixels of the conversation.
abstract final class ChatErrorText {
  /// Longest error detail shown to the user or written to a log line.
  static const int maxDetailChars = 600;

  /// How much of the error is read to classify it.
  static const int classifiedHeadChars = 300;

  /// The bounded head of [error], for a log line.
  static String head(Object error) => details(error.toString());

  static String details(String error) => error.length <= maxDetailChars
      ? error
      : '${error.substring(0, maxDetailChars)}… '
            '(${error.length - maxDetailChars} more characters omitted)';

  /// The lowercase head a classifier may match against.
  static String classified(String error) => error
      .substring(0, math.min(error.length, classifiedHeadChars))
      .toLowerCase();

  static String clean(String rawError) {
    var cleaned = rawError.trim();
    const prefixes = [
      'Exception: ',
      'Bad state: ',
      'ClientException: ',
      'Invalid argument(s): ',
    ];
    for (final prefix in prefixes) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length);
      }
    }
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
