import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/tool_approval_auto_review_service.dart';
import '../../domain/services/turn_tool_approval_coordinator.dart';

typedef ManualToolApprovalCallback =
    Future<ManualToolApprovalDecision> Function(
      ChatTurnOwner owner,
      ManualToolApprovalRequest request,
    );

typedef ToolApprovalAutoReviewCallback =
    Future<ToolApprovalAutoReviewDecision?> Function(
      ChatTurnOwner owner,
      ToolApprovalAutoReviewRequest request, {
      required ToolApprovalAutoReviewDomain domain,
    });

typedef ToolApprovalAuditCallback =
    Future<void> Function(ChatTurnOwner owner, ToolApprovalAuditRecord record);

typedef ToolApprovalOwnerCallback = bool Function(ChatTurnOwner owner);

/// Adapts the notifier's manual approval UI to the narrow approval port.
final class CallbackManualToolApprovalPort implements ManualToolApprovalPort {
  const CallbackManualToolApprovalPort(this._requestApproval);

  final ManualToolApprovalCallback _requestApproval;

  @override
  Future<ManualToolApprovalDecision> requestApproval(
    ChatTurnOwner owner,
    ManualToolApprovalRequest request,
  ) => _requestApproval(owner, request);
}

/// Adapts the notifier's secondary completion flow to the auto-review port.
final class CallbackToolApprovalAutoReviewPort
    implements ToolApprovalAutoReviewPort {
  const CallbackToolApprovalAutoReviewPort(this._review);

  final ToolApprovalAutoReviewCallback _review;

  @override
  Future<ToolApprovalAutoReviewDecision?> review(
    ChatTurnOwner owner,
    ToolApprovalAutoReviewRequest request, {
    required ToolApprovalAutoReviewDomain domain,
  }) => _review(owner, request, domain: domain);
}

/// Adapts the notifier's local audit sink to the approval audit port.
final class CallbackToolApprovalAuditPort implements ToolApprovalAuditPort {
  const CallbackToolApprovalAuditPort(this._record);

  final ToolApprovalAuditCallback _record;

  @override
  Future<void> record(ChatTurnOwner owner, ToolApprovalAuditRecord record) =>
      _record(owner, record);
}

/// Adapts the active-response registry to the approval owner port.
final class CallbackToolApprovalOwnerPort implements ToolApprovalOwnerPort {
  const CallbackToolApprovalOwnerPort(this._isCurrent);

  final ToolApprovalOwnerCallback _isCurrent;

  @override
  bool isCurrent(ChatTurnOwner owner) => _isCurrent(owner);
}
