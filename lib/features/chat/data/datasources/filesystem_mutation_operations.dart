import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import 'edit_anchor_failure_builder.dart';
import 'filesystem_text_snapshot.dart';
import 'first_party_tool_execution_result.dart';

typedef FilesystemContentHashReader =
    Future<String?> Function(String path, int sizeBytes);

typedef FilesystemErrorBuilder =
    String Function({
      required String path,
      required String operation,
      required FileSystemException error,
    });

/// Owns file-mutation execution while [FilesystemTools] remains the facade.
final class FilesystemMutationOperations {
  const FilesystemMutationOperations({
    required FilesystemContentHashReader contentHash,
    required FilesystemErrorBuilder buildError,
  }) : _contentHash = contentHash,
       _buildError = buildError;

  final FilesystemContentHashReader _contentHash;
  final FilesystemErrorBuilder _buildError;

  Future<FirstPartyToolExecutionResult> deleteFileResult({
    required String path,
  }) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({'error': 'File does not exist: $path'}),
      );
    }
    if (type != FileSystemEntityType.file) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error': 'delete_file supports regular files only.',
          'path': File(path).absolute.path,
        }),
      );
    }
    final snapshot = await FilesystemTextSnapshot.capture(path);
    if (snapshot.error != null) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error':
              'delete_file requires a readable UTF-8 text file so the change can be rolled back.',
          'path': File(path).absolute.path,
        }),
      );
    }
    try {
      final absolutePath = File(path).absolute.path;
      await File(path).delete();
      return FirstPartyToolExecutionResult(
        result: jsonEncode({'deleted': true, 'path': absolutePath}),
        outcome: ToolOutcome(
          fileMutations: [
            ToolFileMutation(path: absolutePath, byteSize: 0, changed: true),
          ],
        ),
      );
    } on FileSystemException catch (error) {
      return FirstPartyToolExecutionResult.payloadOnly(
        _buildError(
          path: File(path).absolute.path,
          operation: 'delete_file',
          error: error,
        ),
      );
    }
  }

  Future<FirstPartyToolExecutionResult> writeFileResult({
    required String path,
    required String content,
    bool createParents = true,
  }) async {
    final file = File(path);
    final existedBefore = file.existsSync();
    try {
      final newBytes = utf8.encode(content);
      var changed = true;
      if (existedBefore) {
        try {
          changed =
              await file.length() != newBytes.length ||
              !_bytesEqual(await file.readAsBytes(), newBytes);
        } on FileSystemException {
          changed = true;
        }
      }
      if (createParents) await file.parent.create(recursive: true);
      await file.writeAsString(content);
      final absolutePath = file.absolute.path;
      return FirstPartyToolExecutionResult(
        result: jsonEncode({
          'path': absolutePath,
          'bytes_written': newBytes.length,
          'created': !existedBefore,
          'changed': changed,
        }),
        outcome: ToolOutcome(
          fileMutations: [
            ToolFileMutation(
              path: absolutePath,
              contentHash: await _contentHash(absolutePath, newBytes.length),
              byteSize: newBytes.length,
              changed: changed,
            ),
          ],
        ),
      );
    } on FileSystemException catch (error) {
      return FirstPartyToolExecutionResult.payloadOnly(
        _buildError(
          path: file.absolute.path,
          operation: 'write_file',
          error: error,
        ),
      );
    }
  }

  Future<FirstPartyToolExecutionResult> editFileResult({
    required String path,
    required String oldText,
    required String newText,
    bool replaceAll = false,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({'error': 'File does not exist: $path'}),
      );
    }
    if (oldText.isEmpty) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({'error': 'old_text must not be empty'}),
      );
    }
    try {
      final content = await file.readAsString();
      final precondition = editPreconditionResult(
        path: file.absolute.path,
        content: content,
        oldText: oldText,
        newText: newText,
        replaceAll: replaceAll,
      );
      if (precondition != null) {
        final changed = precondition['changed'];
        if (changed is! bool) {
          return FirstPartyToolExecutionResult.payloadOnly(
            jsonEncode(precondition),
          );
        }
        final contentBytes = utf8.encode(content).length;
        return FirstPartyToolExecutionResult(
          result: jsonEncode(precondition),
          outcome: ToolOutcome(
            fileMutations: [
              ToolFileMutation(
                path: file.absolute.path,
                contentHash: await _contentHash(
                  file.absolute.path,
                  contentBytes,
                ),
                byteSize: contentBytes,
                changed: changed,
              ),
            ],
          ),
        );
      }
      final occurrences = _occurrenceOffsets(content, oldText).length;
      final updatedContent = replaceAll
          ? content.replaceAll(oldText, newText)
          : content.replaceFirst(oldText, newText);
      await file.writeAsString(updatedContent);
      final updatedBytes = utf8.encode(updatedContent).length;
      return FirstPartyToolExecutionResult(
        result: jsonEncode({
          'path': file.absolute.path,
          'replacements': replaceAll ? occurrences : 1,
          'replace_all': replaceAll,
          'changed': true,
        }),
        outcome: ToolOutcome(
          fileMutations: [
            ToolFileMutation(
              path: file.absolute.path,
              contentHash: await _contentHash(file.absolute.path, updatedBytes),
              byteSize: updatedBytes,
              changed: true,
            ),
          ],
        ),
      );
    } on FileSystemException catch (error) {
      return FirstPartyToolExecutionResult.payloadOnly(
        _buildError(
          path: file.absolute.path,
          operation: 'edit_file',
          error: error,
        ),
      );
    }
  }

  Map<String, dynamic>? editPreconditionResult({
    required String path,
    required String content,
    required String oldText,
    required String newText,
    required bool replaceAll,
  }) {
    final oldTextOffsets = _occurrenceOffsets(content, oldText);
    if (oldTextOffsets.isEmpty) {
      return EditAnchorFailureBuilder.build(
        path: path,
        content: content,
        newText: newText,
      );
    }
    if (oldText == newText) {
      return {
        'error': 'no_change',
        'path': path,
        'message':
            'The edit made no change: new_text is identical to old_text, so '
            'the file is unchanged and your intended fix did not apply. Do '
            'not re-read expecting a change. Provide a new_text that actually '
            'differs from old_text, or use write_file to overwrite the file.',
      };
    }
    final coveredOffsets = _oldTextOffsetsCoveredByNewText(
      content: content,
      oldText: oldText,
      newText: newText,
    );
    if (coveredOffsets.length == oldTextOffsets.length) {
      return {
        'path': path,
        'replacements': 0,
        'replace_all': replaceAll,
        'already_applied': true,
        'changed': false,
        'message':
            'new_text is already present at every old_text match; the file was left unchanged.',
      };
    }
    if (coveredOffsets.isNotEmpty) {
      return {
        'error': 'ambiguous_edit_overlap',
        'path': path,
        'occurrences': oldTextOffsets.length,
        'already_applied_occurrences': coveredOffsets.length,
        'message':
            'Some old_text matches are already contained inside new_text. Re-read the file and use a more specific old_text so an applied edit is not expanded again.',
      };
    }
    if (!replaceAll && oldTextOffsets.length > 1) {
      return {
        'error':
            'old_text matched multiple locations. Set replace_all=true or make the target text more specific.',
        'path': path,
        'occurrences': oldTextOffsets.length,
      };
    }
    return null;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static Set<int> _oldTextOffsetsCoveredByNewText({
    required String content,
    required String oldText,
    required String newText,
  }) {
    if (newText.isEmpty || !newText.contains(oldText)) return const <int>{};
    final relativeOffsets = _occurrenceOffsets(newText, oldText);
    return {
      for (final newTextOffset in _occurrenceOffsets(content, newText))
        for (final relativeOffset in relativeOffsets)
          newTextOffset + relativeOffset,
    };
  }

  static List<int> _occurrenceOffsets(String source, String target) {
    if (target.isEmpty) return const [];
    final offsets = <int>[];
    var start = 0;
    while (true) {
      final index = source.indexOf(target, start);
      if (index == -1) return offsets;
      offsets.add(index);
      start = index + target.length;
    }
  }
}
