import Foundation

/// Reduces the small amount of Markdown a model emits to plain text.
///
/// Applied at render and speech time on the watch, deliberately not in the
/// phone's projection: `ParseResult.text` is documented as a pure
/// concatenation of the text segments, and the stream deltas depend on that
/// prefix stability. Stripping mid-stream is not prefix-stable — `*a` becomes
/// `*a` while `*ab*` becomes `ab` — so doing it upstream would make the phone
/// resend the whole answer and the speaker re-read it.
///
/// Scope is what a watch label and a spoken sentence need: emphasis markers,
/// heading hashes, list bullets, and code fences. Anything richer belongs in a
/// renderer, and the watch has no room for one.
enum PlainText {
  static func from(_ markdown: String) -> String {
    var text = markdown

    // Fenced code blocks keep their contents but lose the fence line.
    text = text.replacingOccurrences(
      of: "^```[^\n]*\n?",
      with: "",
      options: [.regularExpression]
    )
    text = text.replacingOccurrences(
      of: "\n```[^\n]*",
      with: "",
      options: [.regularExpression]
    )

    // Emphasis and inline code, innermost first so ** is not left half-eaten.
    for pattern in ["\\*\\*\\*", "\\*\\*", "__", "`"] {
      text = text.replacingOccurrences(
        of: pattern,
        with: "",
        options: [.regularExpression]
      )
    }

    // Leading heading hashes and list bullets, per line.
    text = text.replacingOccurrences(
      of: "(?m)^\\s{0,3}#{1,6}\\s+",
      with: "",
      options: [.regularExpression]
    )
    text = text.replacingOccurrences(
      of: "(?m)^\\s{0,3}[-*+]\\s+",
      with: "",
      options: [.regularExpression]
    )

    // Links keep their label and drop the target: a spoken URL is noise and a
    // watch cannot follow one anyway.
    text = text.replacingOccurrences(
      of: "\\[([^\\]]*)\\]\\([^)]*\\)",
      with: "$1",
      options: [.regularExpression]
    )

    return text
  }
}
