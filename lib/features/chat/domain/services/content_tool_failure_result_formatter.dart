import 'dart:convert';

// ChatNotifier decomposition collaborator: content-tool-failure-result-formatter

/// Renders a failed content tool call as a `<tool_result>` block.
///
/// Split from [ContentToolResultFormatter] because that one summarises by
/// recognising success-shaped keys (`path`, `entries`, `matches`, ...). The
/// failure envelope written by `ContentToolFailureFormatter` has none of them,
/// so it fell through to the literal summary `Completed` and a failed call
/// rendered as a successful one.
abstract final class ContentToolFailureResultFormatter {
  static const int _maxSummaryLength = 72;
  static const int _maxDetailLength = 96;
  static const int _maxDetails = 3;

  /// [result] is the failure envelope, normally
  /// `{"toolName": ..., "error": ..., "code": ...}`.
  static String format(String toolName, String result) {
    final details = <String>[];
    final summary = _summarize(result, details);
    return '<tool_result>${jsonEncode({
      'name': toolName,
      // Read back by the transcript to tint the row. Only ever 'error': an
      // absent status means "unknown", never "succeeded".
      'status': 'error',
      'summary': summary,
      if (details.isNotEmpty) 'details': details,
    })}</tool_result>';
  }

  static String _summarize(String result, List<String> details) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final value = entry.value?.toString().trim() ?? '';
          if (value.isEmpty || details.length >= _maxDetails) continue;
          details.add('${entry.key}: ${_clip(value, _maxDetailLength)}');
        }
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return _clip(error.trim(), _maxSummaryLength);
        }
      }
    } catch (_) {
      final lines = result
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        details.addAll(
          lines.skip(1).take(2).map((line) => _clip(line, _maxDetailLength)),
        );
        return _clip(lines.first, _maxSummaryLength);
      }
    }
    return 'Failed';
  }

  static String _clip(String text, int maxLength) =>
      text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';
}
