import 'dart:convert';

/// Builds actionable diagnostics when an edit anchor no longer exists.
final class EditAnchorFailureBuilder {
  const EditAnchorFailureBuilder._();

  static const int _inlineContentMaxBytes = 4096;

  static Map<String, dynamic> build({
    required String path,
    required String content,
    required String newText,
  }) {
    final error = <String, dynamic>{
      'error': 'old_text was not found in the target file',
      'path': path,
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
      error['hint'] = newTextOffset >= 0
          ? 'new_text is already present at line ${error['new_text_line']}, so '
                'this edit may have been applied already. Confirm that line '
                'before editing again; do not re-read the file in small '
                'windows looking for it.'
          : 'Re-read the file and copy old_text verbatim from its current '
                'content; do not guess and do not pass the desired new value '
                'as old_text.';
    }
    return error;
  }

  static int _lineNumberForOffset(String content, int offset) {
    var line = 1;
    for (var index = 0; index < offset && index < content.length; index++) {
      if (content.codeUnitAt(index) == 0x0a) line += 1;
    }
    return line;
  }
}
