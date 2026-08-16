import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'built_in_filesystem_tool_handler.dart';
import 'built_in_local_command_tool_handler.dart';
import 'mcp_tool_result_normalizer.dart';

/// Name dispatch for the owner-bound entry points.
///
/// The generic `executeTool` surface picks a handler by `handles(name)`, but the
/// owner-bound entry points delegate to a single handler, so a wrongly bound
/// tool name lands on a handler that rejects it by throwing. A throw raised out
/// of tool dispatch ends the whole turn and leaves the call unexecuted, which is
/// how a `process_wait` bound to the filesystem path cost a release turn and
/// stranded the background job it was supposed to be watching. Routing here
/// keeps the rejection an ordinary failed result, scoped to the one tool call.
extension OwnerBoundFilesystemRouting on BuiltInFilesystemToolHandler {
  Future<McpToolResult> executeOwned({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) async => handles(name)
      ? execute(name: name, arguments: arguments, owner: owner)
      : misroutedOwnerToolResult(name: name, entryPoint: 'file');
}

extension OwnerBoundLocalCommandRouting on BuiltInLocalCommandToolHandler {
  Future<McpToolResult> executeOwned({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) async => handles(name)
      ? execute(owner: owner, name: name, arguments: arguments)
      : misroutedOwnerToolResult(name: name, entryPoint: 'process');
}

McpToolResult misroutedOwnerToolResult({
  required String name,
  required String entryPoint,
}) {
  final message =
      'Tool "$name" was dispatched to the owner-bound $entryPoint entry point, '
      'which does not handle it';
  return McpToolResultNormalizer.structuredFailure(
    toolName: name,
    payload: {
      'ok': false,
      'code': 'tool_misrouted',
      'error': message,
      'entry_point': entryPoint,
    },
    errorMessage: message,
  );
}
