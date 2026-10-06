import 'package:caverno_content_protocol/caverno_content_protocol.dart';

/// Keeps legacy recovery markers separate from advisory promise diagnostics.
final class CodingFutureActionDetector {
  const CodingFutureActionDetector();

  static final _fixPromise = RegExp(
    r'\blet me (?:make|apply) (?:the |these )?(?:fixes|changes|edits)\b',
    caseSensitive: false,
  );
  static final _cjkFixPromise = RegExp(
    r'(?:\u8ffd\u52a0|\u4fee\u6b63|\u5909\u66f4|\u66f4\u65b0|\u7de8\u96c6)\u3057\u307e\u3059',
  );
  static final _codingTarget = RegExp(
    r'\b(?:code|source|file|project|dart|python|implementation)\b|'
    r'\.(?:dart|py|js|tsx?|jsx?|rs|go|swift|kt)\b',
    caseSensitive: false,
  );

  /// Diagnostic only; natural-language promises do not authorize recovery.
  bool matchesFixPromise(String content) {
    final visible = ContentParser.stripModelHistoryArtifacts(content);
    return (_fixPromise.hasMatch(visible) ||
            _cjkFixPromise.hasMatch(visible)) &&
        _codingTarget.hasMatch(visible);
  }

  bool matches(String content) {
    content = ContentParser.stripModelHistoryArtifacts(content);
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return _containsAny(normalized, const [
          'i will inspect',
          'i will check',
          'i will read',
          'i will port',
          'i will implement',
          'i will update',
          'i will edit',
          'i will modify',
          'i will write',
          'i will create',
          "i'll inspect",
          "i'll check",
          "i'll read",
          "i'll port",
          "i'll implement",
          "i'll update",
          "i'll edit",
          "i'll modify",
          "i'll write",
          "i'll create",
          'i am going to inspect',
          'i am going to check',
          'i am going to read',
          'i am going to port',
          'i am going to implement',
          'i am going to update',
          'i am going to edit',
          'i am going to modify',
          'i am going to write',
          'i am going to create',
          'next i will',
          'now i will',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059],
          [0x8abf, 0x67fb, 0x3057, 0x307e, 0x3059],
          [0x8aad, 0x307f, 0x307e, 0x3059],
          [
            0x30dd,
            0x30fc,
            0x30c6,
            0x30a3,
            0x30f3,
            0x30b0,
            0x3057,
            0x307e,
            0x3059,
          ],
          [0x79fb, 0x690d, 0x3057, 0x307e, 0x3059],
          [0x5b9f, 0x88c5, 0x3057, 0x307e, 0x3059],
          [0x66f4, 0x65b0, 0x3057, 0x307e, 0x3059],
          [0x7de8, 0x96c6, 0x3057, 0x307e, 0x3059],
          [0x4f5c, 0x6210, 0x3057, 0x307e, 0x3059],
          [0x66f8, 0x304d, 0x307e, 0x3059],
        ]);
  }

  bool _containsAny(String value, List<String> markers) =>
      markers.any(value.contains);

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) =>
      sequences.any(
        (units) =>
            units.isNotEmpty && text.contains(String.fromCharCodes(units)),
      );
}
