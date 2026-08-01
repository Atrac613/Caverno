import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../../core/services/browser_tool_policy.dart';
import '../entities/mcp_tool_entity.dart';
import 'browser_session_ownership_coordinator.dart';
import 'immutable_json_snapshot.dart';

Map<String, dynamic> freezeBrowserToolMap(Map<String, dynamic> value) {
  return ImmutableJsonSnapshot.freezeMap(value);
}

/// Immutable browser tool input captured for one exact operation.
final class BrowserToolRequest {
  BrowserToolRequest({
    required this.operation,
    required Map<String, dynamic> arguments,
  }) : arguments = freezeBrowserToolMap(arguments);

  final BrowserSessionOperationIdentity operation;
  final Map<String, dynamic> arguments;

  String get toolName => operation.toolName;
  String? get reason => arguments['reason'] as String?;
}

/// Operation-tagged page metadata read without exposing browser state.
final class BrowserPageObservation {
  const BrowserPageObservation({required this.operation, this.currentUrl});

  final BrowserSessionOperationIdentity operation;
  final String? currentUrl;
}

/// Immutable save-target lookup input.
final class BrowserSaveTargetRequest {
  const BrowserSaveTargetRequest({
    required this.filename,
    required this.format,
    required this.destination,
  });

  final String filename;
  final String format;
  final String? destination;
}

/// Operation-tagged save-target metadata used for approval presentation.
final class BrowserSaveTargetObservation {
  const BrowserSaveTargetObservation({
    required this.operation,
    required this.destinationLabel,
    required this.destinationChanged,
    required this.requestedDestination,
    required this.requestedFilename,
    required this.filename,
    required this.directoryPath,
    required this.path,
  });

  final BrowserSessionOperationIdentity operation;
  final String destinationLabel;
  final bool destinationChanged;
  final String requestedDestination;
  final String requestedFilename;
  final String filename;
  final String directoryPath;
  final String path;
}

/// Immutable browser execution packet.
final class BrowserExecutionRequest {
  BrowserExecutionRequest({
    required this.operation,
    required Map<String, dynamic> arguments,
  }) : arguments = freezeBrowserToolMap(arguments);

  final BrowserSessionOperationIdentity operation;
  final Map<String, dynamic> arguments;

  String get toolName => operation.toolName;
}

/// Operation-tagged browser transport completion.
final class BrowserExecutionResult {
  const BrowserExecutionResult({required this.operation, required this.result});

  final BrowserSessionOperationIdentity operation;
  final McpToolResult result;
}

/// Sanitized auto-review facts detached from notifier settings and UI.
final class BrowserApprovalGateRequest {
  BrowserApprovalGateRequest({
    required this.toolRequest,
    required this.policy,
    required Map<String, dynamic> Function() buildReviewArguments,
    required this.sensitiveValuePreview,
  }) : _buildReviewArguments = buildReviewArguments;

  final BrowserToolRequest toolRequest;
  final BrowserToolPolicyDecision policy;
  final Map<String, dynamic> Function() _buildReviewArguments;
  final String? sensitiveValuePreview;

  late final Map<String, dynamic> reviewArguments = freezeBrowserToolMap(
    _buildReviewArguments(),
  );

  String? get reason => toolRequest.reason;
}

/// Operation-tagged approval gate completion.
final class BrowserApprovalGateResult {
  const BrowserApprovalGateResult({
    required this.operation,
    required this.decision,
  });

  final BrowserSessionOperationIdentity operation;
  final ToolApprovalGateDecision decision;
}

/// Immutable manual approval presentation detached from notifier state.
final class BrowserManualApprovalRequest {
  BrowserManualApprovalRequest({
    required this.toolRequest,
    required this.policy,
    required this.summary,
    required List<String> details,
    required this.targetSummary,
    required this.sensitiveValuePreview,
  }) : details = List<String>.unmodifiable(details);

  final BrowserToolRequest toolRequest;
  final BrowserToolPolicyDecision policy;
  final String summary;
  final List<String> details;
  final String? targetSummary;
  final String? sensitiveValuePreview;

  String? get reason => toolRequest.reason;
}

/// Operation-tagged manual browser approval completion.
final class BrowserManualApprovalResult {
  const BrowserManualApprovalResult({
    required this.operation,
    required this.approved,
  });

  final BrowserSessionOperationIdentity operation;
  final bool approved;
}

abstract interface class BrowserExecutionPort {
  Future<BrowserExecutionResult> execute(
    BrowserSessionOperationIdentity operation,
    BrowserExecutionRequest request,
    BrowserSessionEffectPermit permit,
  );
}

abstract interface class BrowserApprovalPort {
  Future<BrowserApprovalGateResult> resolveGate(
    BrowserSessionOperationIdentity operation,
    BrowserApprovalGateRequest request,
  );

  Future<BrowserManualApprovalResult> requestManualApproval(
    BrowserSessionOperationIdentity operation,
    BrowserManualApprovalRequest request,
  );

  bool isOperationCurrent(BrowserSessionOperationIdentity operation);

  McpToolResult? expiredResult(BrowserSessionOperationIdentity operation);
}

abstract interface class BrowserObservationPort {
  BrowserPageObservation currentPage(BrowserSessionOperationIdentity operation);

  Future<BrowserSaveTargetObservation> resolveSaveTarget(
    BrowserSessionOperationIdentity operation,
    BrowserSaveTargetRequest request,
  );
}
