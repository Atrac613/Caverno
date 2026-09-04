/// Someone a message can be addressed to by name.
///
/// One entry today — the Anabasis parent — but a list rather than a special
/// case, because the conversation already has a participant roster and naming
/// one of those is the same gesture. Adding a target should be adding a row.
class MentionTarget {
  const MentionTarget({
    required this.handle,
    required this.displayName,
    required this.descriptionKey,
  });

  /// What the user types after `@`, lowercase.
  final String handle;
  final String displayName;

  /// Translation key for the one line explaining what addressing this does.
  ///
  /// A key rather than the text, so a target can stay `const` while the list
  /// renders it in the reader's language — the slash catalog resolves its
  /// descriptions the same way.
  final String descriptionKey;

  /// What replaces the input when the suggestion is accepted.
  ///
  /// Trailing space because the address is a prefix, not the message: the
  /// caret should land where the request goes.
  String get insertion => '@$handle ';
}

/// The Anabasis parent, the one target that always exists.
const anabasisMentionTarget = MentionTarget(
  handle: 'anabasis',
  displayName: 'Anabasis',
  descriptionKey: 'chat.mention_anabasis_desc',
);

/// Suggestions for [input], or empty when it is not addressing anyone.
///
/// **Only at the start of the message, matching what actually routes.**
/// `AnabasisAddress` treats `@anabasis` as an address only in first position,
/// so completing one mid-sentence would hand the user a mention that looks
/// live and does nothing. Once the handle is followed by a space the address is
/// settled and the list gets out of the way.
List<MentionTarget> filterMentionSuggestions(
  String input,
  List<MentionTarget> targets,
) {
  if (!input.startsWith('@')) return const <MentionTarget>[];
  // Any whitespace at all closes the list, including a trailing space. The
  // handle is one word, so a space after it means the address is settled and
  // the rest is the request — and the space the completion itself inserts must
  // not reopen the list it just closed.
  if (input.contains(RegExp(r'\s'))) return const <MentionTarget>[];

  final query = input.substring(1).toLowerCase();
  if (query.isEmpty) return List<MentionTarget>.unmodifiable(targets);
  return List<MentionTarget>.unmodifiable(
    targets.where(
      (target) =>
          target.handle.startsWith(query) ||
          target.displayName.toLowerCase().startsWith(query),
    ),
  );
}
