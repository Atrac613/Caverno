enum FileWorkspaceDiffRowKind { header, context, addition, removal }

final class FileWorkspaceDiffRow {
  const FileWorkspaceDiffRow({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final FileWorkspaceDiffRowKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;
}

final class FileWorkspaceDiffParser {
  FileWorkspaceDiffParser._();

  static final RegExp _hunkPattern = RegExp(
    r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@',
  );

  static List<FileWorkspaceDiffRow> parse(String patch) {
    final rows = <FileWorkspaceDiffRow>[];
    var oldLine = 0;
    var newLine = 0;
    for (final line in patch.split('\n')) {
      final hunkMatch = _hunkPattern.firstMatch(line);
      if (hunkMatch != null) {
        oldLine = int.tryParse(hunkMatch.group(1) ?? '') ?? oldLine;
        newLine = int.tryParse(hunkMatch.group(2) ?? '') ?? newLine;
        rows.add(
          FileWorkspaceDiffRow(
            kind: FileWorkspaceDiffRowKind.header,
            text: line,
          ),
        );
        continue;
      }

      final isFileHeader =
          line.startsWith('diff --git') ||
          line.startsWith('index ') ||
          line.startsWith('---') ||
          line.startsWith('+++');
      if (isFileHeader) {
        rows.add(
          FileWorkspaceDiffRow(
            kind: FileWorkspaceDiffRowKind.header,
            text: line,
          ),
        );
        continue;
      }

      if (line.startsWith('+')) {
        rows.add(
          FileWorkspaceDiffRow(
            kind: FileWorkspaceDiffRowKind.addition,
            text: line,
            newLine: newLine,
          ),
        );
        newLine++;
        continue;
      }
      if (line.startsWith('-')) {
        rows.add(
          FileWorkspaceDiffRow(
            kind: FileWorkspaceDiffRowKind.removal,
            text: line,
            oldLine: oldLine,
          ),
        );
        oldLine++;
        continue;
      }

      rows.add(
        FileWorkspaceDiffRow(
          kind: FileWorkspaceDiffRowKind.context,
          text: line,
          oldLine: oldLine > 0 ? oldLine : null,
          newLine: newLine > 0 ? newLine : null,
        ),
      );
      if (oldLine > 0) {
        oldLine++;
      }
      if (newLine > 0) {
        newLine++;
      }
    }
    return rows;
  }
}
