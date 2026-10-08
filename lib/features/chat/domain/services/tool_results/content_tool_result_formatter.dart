import 'dart:convert';

// ChatNotifier decomposition collaborator: content-tool-result-formatter
abstract final class ContentToolResultFormatter {
  static String format(String toolName, String result) {
    final payload = _buildPayload(toolName, result);
    return '<tool_result>${jsonEncode(payload)}</tool_result>';
  }

  static Map<String, dynamic> _buildPayload(String toolName, String result) {
    final details = <String>[];
    String? summary;

    try {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) {
        summary = _summarizeMap(decoded, details);
      } else if (decoded is List) {
        summary = '${decoded.length} item(s)';
        details.addAll(decoded.take(3).map(_compactValue));
      }
    } catch (_) {
      final lines = result
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        summary = _truncateText(lines.first, maxLength: 72);
        details.addAll(
          lines
              .skip(1)
              .take(2)
              .map((line) => _truncateText(line, maxLength: 96)),
        );
      }
    }

    summary ??= 'Completed';
    return {
      'name': toolName,
      'summary': summary,
      if (details.isNotEmpty) 'details': details,
    };
  }

  static String _summarizeMap(Map<String, dynamic> data, List<String> details) {
    final path = data['path'];
    final entries = data['entries'];
    final matches = data['matches'];
    final content = data['content'];

    if (entries is List) {
      details.addAll(
        entries.take(3).map((entry) => _truncateText(entry.toString())),
      );
      final count = data['entry_count'] ?? entries.length;
      return '$count item(s) in ${_compactValue(path)}';
    }

    if (matches is List) {
      details.addAll(
        matches.take(3).map((match) => _truncateText(match.toString())),
      );
      final count = data['match_count'] ?? matches.length;
      if (data.containsKey('query')) {
        return '$count match(es) for ${_compactValue(data['query'])}';
      }
      if (data.containsKey('pattern')) {
        return '$count file(s) for ${_compactValue(data['pattern'])}';
      }
      return '$count match(es)';
    }

    if (content is String) {
      final lines = content
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      details.addAll(
        lines.take(2).map((line) => _truncateText(line, maxLength: 96)),
      );
      return _compactValue(path);
    }

    if (data.containsKey('bytes_written')) {
      details.add('bytes: ${data['bytes_written']}');
      if (data['created'] == true) {
        details.add('created');
      }
      return _compactValue(path);
    }

    if (data.containsKey('replacements')) {
      details.add('replacements: ${data['replacements']}');
      if (data['replace_all'] == true) {
        details.add('replace all');
      }
      return _compactValue(path);
    }

    final prioritizedEntries = data.entries
        .where(
          (entry) => entry.value != null && entry.value.toString().isNotEmpty,
        )
        .take(3);
    details.addAll(
      prioritizedEntries.map(
        (entry) =>
            '${entry.key}: ${_truncateText(_compactValue(entry.value), maxLength: 72)}',
      ),
    );
    return _compactValue(
      path ?? data['query'] ?? data['pattern'] ?? 'Completed',
    );
  }

  static String _compactValue(dynamic value) {
    if (value == null) return 'unknown';
    if (value is String) return value;
    return jsonEncode(value);
  }

  static String _truncateText(String value, {int maxLength = 88}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 1)}...';
  }
}
