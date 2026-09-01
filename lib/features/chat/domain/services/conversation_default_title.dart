import '../entities/message.dart';

/// Names a thread from what the person actually said in it.
///
/// Pure string work with no notifier state, kept out of ConversationsNotifier
/// so the rule is testable on its own — it decides what every untitled thread
/// in the drawer is called.
abstract final class ConversationDefaultTitle {
  /// Longest title the drawer shows before eliding.
  static const int maxLength = 30;

  /// The attachment header a composer message appends after the person's text.
  static final RegExp _attachmentBlockPattern = RegExp(
    r'(?:\n\n|^)\[File: (.+?)\]\s*$',
  );

  /// The first user message's subject, or null when nobody has spoken yet.
  static String? deriveFrom(List<Message> messages) {
    for (final message in messages) {
      if (message.role != MessageRole.user) continue;

      final subject = subjectOf(message.content);
      if (subject.isEmpty) continue;

      return subject.length > maxLength
          ? '${subject.substring(0, maxLength)}...'
          : subject;
    }

    return null;
  }

  /// The part of a user message a thread should be named after.
  ///
  /// A message that carries a file ends with an attachment header; the person
  /// asked the question in front of it, so that is the title. When they sent
  /// only the file, its name is the best name the thread has — an untitled
  /// thread named `[File: ...]` says nothing the file chip does not.
  static String subjectOf(String content) {
    final trimmed = content.trim();
    final block = _attachmentBlockPattern.firstMatch(trimmed);
    if (block == null) return trimmed;
    final question = trimmed.substring(0, block.start).trim();
    return question.isEmpty ? block.group(1)!.trim() : question;
  }
}
