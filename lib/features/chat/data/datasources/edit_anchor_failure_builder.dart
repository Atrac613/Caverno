import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Builds actionable diagnostics when an edit anchor no longer exists.
final class EditAnchorFailureBuilder {
  const EditAnchorFailureBuilder._();

  static const int _inlineContentMaxBytes = 4096;

  static Map<String, dynamic> build({
    required String path,
    required String content,
    required String oldText,
    required String newText,
  }) {
    final error = <String, dynamic>{
      'error': 'old_text was not found in the target file',
      'path': path,
      'content_sha256': sha256.convert(utf8.encode(content)).toString(),
    };
    final newTextOffset = newText.isEmpty ? -1 : content.indexOf(newText);
    if (newTextOffset >= 0) {
      error['new_text_present'] = true;
      error['new_text_line'] = _lineNumberForOffset(content, newTextOffset);
    }
    if (utf8.encode(content).length <= _inlineContentMaxBytes) {
      error['current_content'] = content;
      error['hint'] =
          'old_text must be copied verbatim from current_content; do not pass '
          'the desired new value as old_text. If matching is hard, call '
          'write_file with the full corrected file content instead.';
    } else {
      final contextOffset = newTextOffset >= 0
          ? newTextOffset
          : _uniqueAnchorOffset(content, oldText);
      if (contextOffset != null) {
        final anchorLine = _lineNumberForOffset(content, contextOffset);
        final lines = content.split('\n');
        final start = (anchorLine - 4).clamp(0, lines.length);
        var end = start;
        var bytes = 0;
        while (end < lines.length && end < anchorLine + 7) {
          final nextBytes =
              utf8.encode(lines[end]).length + (end > start ? 1 : 0);
          if (bytes + nextBytes > _inlineContentMaxBytes) break;
          bytes += nextBytes;
          end++;
        }
        if (end > start) {
          error['current_context'] = {
            'start_line': start + 1,
            'line_count': end - start,
            'content': lines.sublist(start, end).join('\n'),
          };
        }
        error['read_more_hint'] = {
          'path': path,
          'offset': anchorLine,
          'limit': 20,
        };
      }
      error['hint'] = newTextOffset >= 0
          ? 'new_text is already present at line ${error['new_text_line']}, so '
                'this edit may have been applied already. Confirm that line '
                'before editing again; do not re-read the file in small '
                'windows looking for it.'
          : 'Copy old_text verbatim from current_context if it covers the '
                'required anchor, or read the missing range with read_file '
                'offset and limit. Context is diagnostic only: no approximate '
                'replacement was applied. Do not guess or use the desired '
                'new value as old_text.';
      if (contextOffset == null) {
        error['hint'] =
            'Re-read the required range with read_file offset and limit, and '
            'copy old_text verbatim from its current content; no unique anchor '
            'was located. Do not guess or use the desired new value as old_text.';
      }
    }
    return error;
  }

  static int? _uniqueAnchorOffset(String content, String oldText) {
    // Exact unchanged lines locate diagnostics; they never authorize a write.
    for (final rawLine in oldText.split('\n').take(32)) {
      final line = rawLine.trim();
      if (line.length < 8) continue;
      final offset = content.indexOf(line);
      if (offset >= 0 && content.indexOf(line, offset + 1) < 0) return offset;
    }
    return null;
  }

  static int _lineNumberForOffset(String content, int offset) {
    var line = 1;
    for (var index = 0; index < offset && index < content.length; index++) {
      if (content.codeUnitAt(index) == 0x0a) line += 1;
    }
    return line;
  }
}
