import '../../data/datasources/file_mutation_runtime_contract.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'chat_state.dart';
import 'tool_approval_cache.dart';

typedef FileMutationOwnerCurrentPredicate = bool Function(ChatTurnOwner owner);
typedef FileMutationOwnerApprovalCacheResolver =
    OwnerToolApprovalCache Function(ChatTurnOwner owner);

/// Adapts exact-owner approval cache operations to the mutation runtime.
final class FileMutationApprovalCacheRuntimeAdapter {
  const FileMutationApprovalCacheRuntimeAdapter({
    required FileMutationOwnerCurrentPredicate ownerIsCurrent,
    required FileMutationOwnerApprovalCacheResolver cacheForOwner,
  }) : _ownerIsCurrent = ownerIsCurrent,
       _cacheForOwner = cacheForOwner;

  final FileMutationOwnerCurrentPredicate _ownerIsCurrent;
  final FileMutationOwnerApprovalCacheResolver _cacheForOwner;

  OwnerToolApprovalCache? currentCache(ChatTurnOwner owner) =>
      _ownerIsCurrent(owner) ? _cacheForOwner(owner) : null;

  FileMutationRuntimeAcknowledgement<Object?> acknowledgeLifecycle(
    FileMutationRuntimeIdentity identity,
  ) {
    final current = _ownerIsCurrent(identity.owner);
    return acknowledge(
      identity,
      current: current,
      value: current ? null : approvalTurnExpiredResult(identity.toolName),
    );
  }

  FileMutationRuntimeAcknowledgement<McpToolResult?> lookupDenial(
    FileMutationRuntimeApprovalRequest request,
  ) {
    final approval = request.request;
    final cache = currentCache(request.identity.owner);
    return acknowledge(
      request.identity,
      current: cache != null,
      value: cache?.lookupDenial(
        request.identity.toolName,
        approval.cacheArguments,
        stateFingerprint: approval.stateFingerprint,
      ),
    );
  }

  FileMutationRuntimeAcknowledgement<Object?> rememberDenial(
    FileMutationRuntimeCacheWriteRequest request,
  ) => _remember(request, denial: true);

  FileMutationRuntimeAcknowledgement<Object?> rememberResult(
    FileMutationRuntimeCacheWriteRequest request,
  ) => _remember(request, denial: false);

  FileMutationRuntimeAcknowledgement<Object?> _remember(
    FileMutationRuntimeCacheWriteRequest request, {
    required bool denial,
  }) {
    final identity = request.identity;
    final approval = request.approval.request;
    final cache = currentCache(identity.owner);
    if (cache == null) {
      return acknowledge(identity, current: false);
    }
    if (denial) {
      cache.rememberDenial(
        identity.toolName,
        approval.cacheArguments,
        request.result,
        stateFingerprint: approval.stateFingerprint,
      );
    } else {
      cache.rememberResult(
        identity.toolName,
        approval.cacheArguments,
        request.result,
        stateFingerprint: approval.stateFingerprint,
      );
    }
    return acknowledge(identity, current: true);
  }

  FileMutationRuntimeAcknowledgement<T> acknowledge<T>(
    FileMutationRuntimeIdentity identity, {
    required bool current,
    T? value,
    String? message,
  }) => FileMutationRuntimeAcknowledgement(
    identity: identity,
    disposition: current
        ? FileMutationRuntimeAcknowledgementDisposition.completed
        : FileMutationRuntimeAcknowledgementDisposition.ownerExpired,
    value: current ? value : null,
    message: message,
  );
}
