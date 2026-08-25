import '../entities/mcp_tool_entity.dart';
import 'background_process_tool_contract.dart';
import 'background_process_tool_results.dart';
import 'local_command_tool_handler.dart';

/// Decides what a background-process result is worth once it comes back.
///
/// Every path through the handler ends by asking the same three questions --
/// does this completion still belong to the turn that asked for it, has the
/// approval expired meanwhile, and may a side effect already have happened --
/// and answering them beside each call site is how a result gets reported for
/// a turn that no longer owns it.
final class BackgroundProcessResultLedger {
  const BackgroundProcessResultLedger({
    required LocalCommandApprovalPort approvalPort,
    required BackgroundProcessToolResults results,
  }) : _approvalPort = approvalPort,
       _results = results;

  final LocalCommandApprovalPort _approvalPort;
  final BackgroundProcessToolResults _results;

  McpToolResult cacheResult(
    BackgroundProcessToolRequest request,
    LocalCommandApprovalRequest? approval,
    McpToolResult result, {
    bool sideEffectMayHaveOccurred = false,
  }) {
    final exactResult = _results.requireToolName(result, request.toolName);
    if (approval == null) {
      return isExpired(request) && sideEffectMayHaveOccurred
          ? _results.effectUncertain(request.toolName)
          : exactResult;
    }
    final acknowledgement = _approvalPort.rememberResult(
      request.owner,
      approval,
      exactResult,
    );
    final accepted =
        belongsToRequest(acknowledgement, request) &&
        acknowledgement.disposition ==
            LocalCommandCompletionDisposition.completed &&
        !isExpired(request);
    if (accepted) return exactResult;
    return sideEffectMayHaveOccurred
        ? _results.effectUncertain(request.toolName)
        : _results.expired(request.toolName);
  }

  bool completionExpired<T>(
    LocalCommandCompletion<T> completion,
    BackgroundProcessToolRequest request,
  ) {
    if (completion.owner != request.owner ||
        completion.toolCallId != request.toolCallId) {
      throw StateError('Background process completion scope mismatch.');
    }
    return completion.disposition ==
        LocalCommandCompletionDisposition.ownerExpired;
  }

  bool belongsToRequest<T>(
    LocalCommandCompletion<T> completion,
    BackgroundProcessToolRequest request,
  ) => completion.belongsTo(request.owner, request.toolCallId);

  bool isExpired(BackgroundProcessToolRequest request) =>
      _approvalPort.isExpired(request.owner, request.toolCallId);
  McpToolResult rememberDenial(
    BackgroundProcessToolRequest request,
    LocalCommandApprovalRequest approval,
    McpToolResult result,
  ) {
    final exactResult = _results.requireToolName(result, request.toolName);
    if (isExpired(request)) return _results.expired(request.toolName);
    final acknowledgement = _approvalPort.rememberDenial(
      request.owner,
      approval,
      exactResult,
    );
    return belongsToRequest(acknowledgement, request) &&
            acknowledgement.disposition ==
                LocalCommandCompletionDisposition.completed &&
            !isExpired(request)
        ? exactResult
        : _results.expired(request.toolName);
  }
}
