/// Builds the user-facing notice appended when a final answer was cut off at
/// the model's max-token limit (`finishReason == 'length'`), so a truncated
/// response — and any code/file content inside it — is not presented as if it
/// were complete.
class TruncationNotice {
  TruncationNotice._();

  static const String maxTokenNotice =
      '[Response truncated at the max-token limit. Increase Max Tokens in '
      'Settings for the full answer.]';

  /// Returns [content] with the max-token notice appended. Idempotent (does not
  /// duplicate the notice) and safe on empty content.
  static String withMaxTokenNotice(String content) {
    if (content.contains(maxTokenNotice)) {
      return content;
    }
    final trimmed = content.trimRight();
    return trimmed.isEmpty ? maxTokenNotice : '$trimmed\n\n$maxTokenNotice';
  }
}
