// Same-library extension on [ChatNotifier]: formatting helpers that turn a raw
// tool result into the compact <tool_result> payload/tag shown inline (map
// summarization, value compaction, truncation). Pure relocation from
// chat_notifier.dart (F5), no behavior change.
part of 'chat_notifier.dart';

extension ChatNotifierContentToolResultFormat on ChatNotifier {
  String _buildContentToolResultTag(String toolName, String result) {
    final payload = _buildContentToolResultPayload(toolName, result);
    return '<tool_result>${jsonEncode(payload)}</tool_result>';
  }

  Map<String, dynamic> _buildContentToolResultPayload(
    String toolName,
    String result,
  ) {
    final details = <String>[];
    String? summary;

    try {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) {
        summary = _summarizeToolResultMap(decoded, details);
      } else if (decoded is List) {
        summary = '${decoded.length} item(s)';
        details.addAll(
          decoded.take(3).map((item) => _compactToolResultValue(item)),
        );
      }
    } catch (_) {
      final lines = result
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        summary = _truncateToolResultText(lines.first, maxLength: 72);
        details.addAll(
          lines
              .skip(1)
              .take(2)
              .map((line) => _truncateToolResultText(line, maxLength: 96)),
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

  String _summarizeToolResultMap(
    Map<String, dynamic> data,
    List<String> details,
  ) {
    final path = data['path'];
    final entries = data['entries'];
    final matches = data['matches'];
    final content = data['content'];

    if (entries is List) {
      details.addAll(
        entries
            .take(3)
            .map((entry) => _truncateToolResultText(entry.toString())),
      );
      final count = data['entry_count'] ?? entries.length;
      return '$count item(s) in ${_compactToolResultValue(path)}';
    }

    if (matches is List) {
      details.addAll(
        matches
            .take(3)
            .map((match) => _truncateToolResultText(match.toString())),
      );
      final count = data['match_count'] ?? matches.length;
      if (data.containsKey('query')) {
        return '$count match(es) for ${_compactToolResultValue(data['query'])}';
      }
      if (data.containsKey('pattern')) {
        return '$count file(s) for ${_compactToolResultValue(data['pattern'])}';
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
        lines
            .take(2)
            .map((line) => _truncateToolResultText(line, maxLength: 96)),
      );
      return _compactToolResultValue(path);
    }

    if (data.containsKey('bytes_written')) {
      details.add('bytes: ${data['bytes_written']}');
      if (data['created'] == true) {
        details.add('created');
      }
      return _compactToolResultValue(path);
    }

    if (data.containsKey('replacements')) {
      details.add('replacements: ${data['replacements']}');
      if (data['replace_all'] == true) {
        details.add('replace all');
      }
      return _compactToolResultValue(path);
    }

    final prioritizedEntries = data.entries
        .where(
          (entry) => entry.value != null && entry.value.toString().isNotEmpty,
        )
        .take(3);
    details.addAll(
      prioritizedEntries.map(
        (entry) =>
            '${entry.key}: ${_truncateToolResultText(_compactToolResultValue(entry.value), maxLength: 72)}',
      ),
    );
    return _compactToolResultValue(
      path ?? data['query'] ?? data['pattern'] ?? 'Completed',
    );
  }

  String _compactToolResultValue(dynamic value) {
    if (value == null) return 'unknown';
    if (value is String) return value;
    return jsonEncode(value);
  }

  String _truncateToolResultText(String value, {int maxLength = 88}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 1)}...';
  }
}
