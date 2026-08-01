import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/chat_tool_handler_catalog.dart';
import '../../domain/services/subagent_tool_contract.dart';

typedef SubagentChildOwnerCurrentCallback =
    bool Function(SubagentTaskIdentity identity);

/// Dispatches child tools through the owner-bound production catalog.
///
/// The adapter repeats the nested-tool and allowlist checks at the execution
/// boundary so a future caller cannot bypass the domain handler's validation.
final class SubagentCatalogChildToolExecutionAdapter
    implements ChildToolExecutionPort {
  const SubagentCatalogChildToolExecutionAdapter({
    required ChatToolHandlerCatalog catalog,
    required SubagentChildOwnerCurrentCallback isOwnerCurrent,
  }) : _catalog = catalog,
       _isOwnerCurrent = isOwnerCurrent;

  static const _nestedToolNames = <String>{
    spawnSubagentToolName,
    getSubagentResultToolName,
  };
  static const _expiredError =
      'Subagent child execution was cancelled because its exact owner expired';
  static const _uncertainError =
      'Subagent child execution outcome is uncertain; inspect possible '
      'side effects before retrying';

  final ChatToolHandlerCatalog _catalog;
  final SubagentChildOwnerCurrentCallback _isOwnerCurrent;

  @override
  Future<ChildToolExecutionCompletion> execute(
    ChildToolExecutionRequest request,
  ) async {
    final deniedError = _deniedError(request);
    if (deniedError != null) {
      return _completion(request, _failure(request.name, deniedError));
    }
    if (!_isOwnerCurrent(request.taskIdentity)) {
      return _completion(request, _failure(request.name, _expiredError));
    }

    final result = await _catalog.dispatch(
      request.taskIdentity.owner,
      ToolCallInfo(
        id: request.id,
        name: request.name,
        arguments: request.arguments,
      ),
    );
    if (!_isOwnerCurrent(request.taskIdentity)) {
      return _completion(request, _failure(request.name, _uncertainError));
    }
    return _completion(request, result);
  }

  String? _deniedError(ChildToolExecutionRequest request) {
    if (_nestedToolNames.contains(request.name)) {
      return 'Nested subagents are not allowed.';
    }
    if (!request.allowedToolNames.contains(request.name)) {
      return 'Tool ${request.name} is not available to this subagent.';
    }
    return null;
  }

  ChildToolExecutionCompletion _completion(
    ChildToolExecutionRequest request,
    McpToolResult result,
  ) => ChildToolExecutionCompletion(request: request, result: result);

  McpToolResult _failure(String toolName, String error) => McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: error,
  );
}
