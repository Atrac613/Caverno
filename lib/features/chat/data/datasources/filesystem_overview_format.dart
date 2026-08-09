/// Presentation helpers for the file-overview surfaces (`inspect_file`,
/// `search_files`): clipping a line to a readable width and guessing a file's
/// format for the model.
///
/// Extracted from `FilesystemTools` because none of it touches the filesystem —
/// it is pure string classification over content the caller already read, and
/// keeping it inline mixed formatting decisions in with the streaming and
/// mutation paths that make up the rest of that class.
abstract final class FilesystemOverviewFormat {
  /// Width beyond which an overview line is clipped, so a single very long
  /// line cannot dominate the output.
  static const int maxOverviewLineChars = 1000;

  /// Human-readable byte size for the file listings the tools emit.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String clipLine(String line) => line.length > maxOverviewLineChars
      ? '${line.substring(0, maxOverviewLineChars)}…'
      : line;

  static final RegExp _logLinePrefix = RegExp(
    r'^\[?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}' // 2026-06-05 12:34:56
    r'|^\[?\d{2}:\d{2}:\d{2}' // 12:34:56
    r'|^\[?(ERROR|WARN|WARNING|INFO|DEBUG|TRACE|FATAL)\b', // level prefix
    caseSensitive: false,
  );

  /// Best-effort, cheap format classification from the file extension first,
  /// then the first non-empty line. Used only as a hint for the model.
  static String detectFormatHint(String path, String firstNonEmptyLine) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jsonl') || lower.endsWith('.ndjson')) return 'jsonl';
    if (lower.endsWith('.json')) return 'json';
    if (lower.endsWith('.csv')) return 'csv';
    if (lower.endsWith('.tsv')) return 'tsv';
    if (lower.endsWith('.log')) return 'log';
    if (lower.endsWith('.xml')) return 'xml';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'yaml';
    if (lower.endsWith('.md')) return 'markdown';

    final trimmed = firstNonEmptyLine.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return 'json';
    if (_logLinePrefix.hasMatch(trimmed)) return 'log';
    if (trimmed.contains(',') && firstNonEmptyLine.split(',').length >= 3) {
      return 'csv';
    }
    return 'text';
  }
}
