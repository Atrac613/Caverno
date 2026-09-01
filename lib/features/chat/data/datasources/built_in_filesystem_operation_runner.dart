import 'filesystem_tools.dart';
import 'first_party_tool_execution_result.dart';

typedef BuiltInFilesystemOperationRunner =
    Future<String> Function({
      required String name,
      required Map<String, dynamic> arguments,
    });

typedef BuiltInFilesystemOperationResultRunner =
    Future<FirstPartyToolExecutionResult> Function({
      required String name,
      required Map<String, dynamic> arguments,
    });

BuiltInFilesystemOperationResultRunner resolveBuiltInFilesystemOperationRunner({
  BuiltInFilesystemOperationRunner? legacyRunner,
  BuiltInFilesystemOperationResultRunner? resultRunner,
}) =>
    resultRunner ??
    (legacyRunner == null
        ? runBuiltInFilesystemOperation
        : ({required name, required arguments}) async =>
              FirstPartyToolExecutionResult.payloadOnly(
                await legacyRunner(name: name, arguments: arguments),
              ));

Future<FirstPartyToolExecutionResult> runBuiltInFilesystemOperation({
  required String name,
  required Map<String, dynamic> arguments,
}) async => switch (name) {
  'list_directory' => FirstPartyToolExecutionResult.payloadOnly(
    await FilesystemTools.listDirectory(
      path: arguments['path'] as String,
      recursive: arguments['recursive'] as bool,
      maxEntries: arguments['max_entries'] as int,
    ),
  ),
  'read_file' => FilesystemTools.readFileResult(
    path: arguments['path'] as String,
    maxChars: arguments['max_chars'] as int,
    offset: arguments['offset'] as int,
    limit: arguments['limit'] as int?,
    startPage: arguments['start_page'] as int? ?? 1,
  ),
  'inspect_file' => FirstPartyToolExecutionResult.payloadOnly(
    await FilesystemTools.inspectFile(
      path: arguments['path'] as String,
      headLines: arguments['head_lines'] as int,
      tailLines: arguments['tail_lines'] as int,
    ),
  ),
  'find_files' => FirstPartyToolExecutionResult.payloadOnly(
    await FilesystemTools.findFiles(
      path: arguments['path'] as String,
      pattern: arguments['pattern'] as String,
      recursive: arguments['recursive'] as bool,
      maxResults: arguments['max_results'] as int,
    ),
  ),
  'search_files' => FirstPartyToolExecutionResult.payloadOnly(
    await FilesystemTools.searchFiles(
      path: arguments['path'] as String,
      query: arguments['query'] as String,
      filePattern: arguments['file_pattern'] as String?,
      caseSensitive: arguments['case_sensitive'] as bool,
      maxResults: arguments['max_results'] as int,
      offset: arguments['offset'] as int,
      maxLineLength: arguments['max_line_length'] as int,
      maxBytesScanned: arguments['max_bytes_scanned'] as int?,
    ),
  ),
  'write_file' => FilesystemTools.writeFileResult(
    path: arguments['path'] as String,
    content: arguments['content'] as String,
    createParents: arguments['create_parents'] as bool,
  ),
  'edit_file' => FilesystemTools.editFileResult(
    path: arguments['path'] as String,
    oldText: arguments['old_text'] as String,
    newText: arguments['new_text'] as String,
    replaceAll: arguments['replace_all'] as bool,
  ),
  'delete_file' => FilesystemTools.deleteFileResult(
    path: arguments['path'] as String,
  ),
  _ => throw StateError('Unknown filesystem operation: $name'),
};
