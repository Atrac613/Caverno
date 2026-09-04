/// Reads whether a message is addressed to the Anabasis parent.
///
/// The design names three ways to reach the parent — `@anabasis` from the
/// shared chat, its own workspace, and background orchestration — and requires
/// identical authority in all three. This is the first of them.
///
/// **This parses an address the user typed; it does not judge intent.** The
/// heuristic-removal track's rule is that a pattern may trigger work but never
/// decide a question, and nothing is being decided here: `@anabasis` at the
/// start of a message is the user naming who they are talking to, the same way
/// a slash command names what they are invoking. A message that merely
/// *mentions* Anabasis somewhere in its prose is not addressed to it.
abstract final class AnabasisAddress {
  static const handle = '@anabasis';

  /// Whether [content] is addressed to the parent.
  ///
  /// Only at the start, and only as a whole word: "ask @anabasis about it" is
  /// a message to the assistant about the parent, not a message to the parent.
  static bool isAddressed(String content) => _match(content) != null;

  /// The offset just past the handle, or `null` when [content] is not addressed.
  static int? _match(String content) {
    final trimmed = content.trimLeft();
    final offset = content.length - trimmed.length;
    if (trimmed.length < handle.length) return null;
    if (trimmed.substring(0, handle.length).toLowerCase() != handle) {
      return null;
    }
    final rest = trimmed.substring(handle.length);
    // A whole word: `@anabasistown` is not the parent. An empty rest is an
    // address with no request, which is still an address.
    if (rest.isNotEmpty && !_isBoundary(rest[0])) return null;
    return offset + handle.length;
  }

  static bool _isBoundary(String character) {
    return character.trim().isEmpty ||
        character == ':' ||
        character == ',' ||
        character == '、' ||
        character == '：';
  }
}
