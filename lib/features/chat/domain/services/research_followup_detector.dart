/// Detects a chat answer that *announces* a read-only information lookup
/// ("I'll look it up", "調べます") but issues no tool call, so the harness can
/// re-prompt the model to actually perform the lookup with an available web
/// tool (browser / http / search).
///
/// Deliberately narrow: it fires only on read-only research intent, never on
/// responses that pause for confirmation/approval. The worst case is therefore
/// a benign extra web read — not pushing the model past a safety pause (unlike a
/// generic "present-vs-execute" detector, which could override a release
/// approval). Japanese cues are built from code units to keep the source ASCII.
class ResearchFollowupDetector {
  const ResearchFollowupDetector();

  /// English "I'll look it up / search / fetch" intent.
  static final RegExp _enIntent = RegExp(
    r"(i'?ll|i will|i'?m going to|i am going to|i need to|let me)\b[^.\n]{0,48}"
    r'\b(look up|looking up|search|find out|check online|browse|fetch|'
    r'google|investigate|research)\b',
    caseSensitive: false,
  );

  /// English confirmation/approval cues — when present, the model is pausing on
  /// purpose, so the recovery must not fire.
  static final RegExp _enConfirm = RegExp(
    r'\b(shall i|may i|should i|do you want|would you like|are you sure|'
    r'ok to proceed|proceed\?|confirm\b|please confirm)\b',
    caseSensitive: false,
  );

  // Japanese research-intent substrings (code units keep the file ASCII):
  //   調べ (look up), 検索 (search), 調査 (investigate), 探し (find)
  static final List<String> _jaIntent = <String>[
    String.fromCharCodes(const [0x8abf, 0x3079]),
    String.fromCharCodes(const [0x691c, 0x7d22]),
    String.fromCharCodes(const [0x8abf, 0x67fb]),
    String.fromCharCodes(const [0x63a2, 0x3057]),
  ];

  // Japanese confirmation cues:
  //   しますか / ますか (do you want me to?), 承認 (approval),
  //   よろしいですか (is it ok?), いいですか (is it ok?)
  static final List<String> _jaConfirm = <String>[
    String.fromCharCodes(const [0x3057, 0x307e, 0x3059, 0x304b]),
    String.fromCharCodes(const [0x627f, 0x8a8d]),
    String.fromCharCodes(const [
      0x3088,
      0x308d,
      0x3057,
      0x3044,
      0x3067,
      0x3059,
      0x304b,
    ]),
    String.fromCharCodes(const [0x3044, 0x3044, 0x3067, 0x3059, 0x304b]),
  ];

  /// Whether [text] announces a read-only lookup without acting and is safe to
  /// nudge (i.e. it is not pausing for confirmation/approval).
  bool looksLikeUnactionedResearch(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 1600) {
      return false;
    }
    if (_jaConfirm.any(trimmed.contains) || _enConfirm.hasMatch(trimmed)) {
      return false;
    }
    return _jaIntent.any(trimmed.contains) || _enIntent.hasMatch(trimmed);
  }
}
