import '../../data/datasources/python_script_runtime_contract.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'tool_approval_cache.dart';

typedef PythonOwnerCurrentPredicate = bool Function(ChatTurnOwner owner);
typedef PythonOwnerApprovalCacheResolver =
    OwnerToolApprovalCache Function(ChatTurnOwner owner);

/// Adapts owner-scoped approval cache operations to the Python runtime contract.
final class PythonScriptApprovalCacheRuntimeAdapter {
  const PythonScriptApprovalCacheRuntimeAdapter({
    required PythonOwnerCurrentPredicate ownerIsCurrent,
    required PythonOwnerApprovalCacheResolver cacheForOwner,
  }) : _ownerIsCurrent = ownerIsCurrent,
       _cacheForOwner = cacheForOwner;

  final PythonOwnerCurrentPredicate _ownerIsCurrent;
  final PythonOwnerApprovalCacheResolver _cacheForOwner;

  OwnerToolApprovalCache? currentCache(ChatTurnOwner owner) =>
      _ownerIsCurrent(owner) ? _cacheForOwner(owner) : null;

  PythonRuntimeAcknowledgement<PythonScriptRuntimeIdentity, Object?>
  acknowledgeLifecycle(PythonScriptRuntimeIdentity identity) =>
      acknowledge(identity, current: _ownerIsCurrent(identity.owner));

  PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, McpToolResult?>
  lookupDenial(PythonRuntimeCacheRequest request) {
    final identity = request.identity;
    final cache = currentCache(identity.runtime.owner);
    return acknowledge(
      identity,
      current: cache != null,
      value: cache?.lookupDenial(
        identity.runtime.toolName,
        request.cacheArguments,
      ),
    );
  }

  PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, Object?>
  rememberDenial(PythonRuntimeCacheWriteRequest request) =>
      _remember(request, denial: true);

  PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, Object?>
  rememberResult(PythonRuntimeCacheWriteRequest request) =>
      _remember(request, denial: false);

  PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, Object?>
  _remember(PythonRuntimeCacheWriteRequest request, {required bool denial}) {
    final identity = request.identity;
    final cache = currentCache(identity.runtime.owner);
    if (cache == null) {
      return acknowledge(identity, current: false);
    }
    final toolName = identity.runtime.toolName;
    if (denial) {
      cache.rememberDenial(
        toolName,
        request.cacheRequest.cacheArguments,
        request.result,
      );
    } else {
      cache.rememberResult(
        toolName,
        request.cacheRequest.cacheArguments,
        request.result,
      );
    }
    return acknowledge(identity, current: true);
  }

  PythonRuntimeAcknowledgement<I, T> acknowledge<I, T>(
    I identity, {
    required bool current,
    T? value,
  }) => PythonRuntimeAcknowledgement(
    identity: identity,
    disposition: current
        ? PythonRuntimeAcknowledgementDisposition.completed
        : PythonRuntimeAcknowledgementDisposition.ownerExpired,
    value: current ? value : null,
  );
}
