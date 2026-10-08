import 'package:caverno_content_protocol/caverno_content_protocol.dart';

/// Advisory log diagnostics; never used to authorize task continuation.
final class IncompleteCodingWorkDetector {
  const IncompleteCodingWorkDetector();

  static final _incomplete = RegExp(
    r'\b(?:task|work|implementation|feature)\s+'
    r'(?:(?:is|remains|is still|still)\s+)?'
    r'(?:incomplete|unfinished|not (?:yet )?(?:complete|finished|implemented)|'
    r'partially (?:complete|implemented))\b|'
    r'(?:\u30bf\u30b9\u30af|\u5b9f\u88c5|\u4f5c\u696d|\u6a5f\u80fd)'
    r'(?:\u306f|\u304c)?(?:\u307e\u3060)?'
    r'(?:\u672a\u5b8c(?:\u4e86|\u6210)?|\u4e0d\u5b8c\u5168|\u90e8\u5206\u7684\u306b\u5b8c\u4e86)',
    caseSensitive: false,
  );
  static final _pendingVerification = RegExp(
    r'\b(?:unexecuted|pending) verification commands?\b|'
    r'\u672a\u5b9f\u884c\u306e\u691c\u8a3c\u30b3\u30de\u30f3\u30c9',
    caseSensitive: false,
  );

  bool hasIncompleteTask(String content) {
    final visible = ContentParser.stripModelHistoryArtifacts(
      content,
    ).replaceAll('*', '');
    return _incomplete.hasMatch(visible) ||
        _pendingVerification.hasMatch(visible);
  }
}
