import '../../entities/chat_turn_owner.dart';
import '../../entities/tool_call_info.dart';
import '../immutable_json_snapshot.dart';

/// Exact production release carried across the approval turn boundary.
final class PendingBlockedRelease {
  const PendingBlockedRelease({
    required this.toolName,
    required this.command,
    this.executionIdentity,
    this.workingDirectory,
    this.background = false,
  });

  final String toolName;
  final String command;

  /// Null only for legacy payloads, which cannot authorize an exact retry.
  final String? executionIdentity;
  final String? workingDirectory;
  final bool background;
}

/// Immutable evidence used to plan a blocked-release retry.
final class BlockedProductionReleaseRetryInput {
  BlockedProductionReleaseRetryInput({
    required this.owner,
    required List<ToolResultInfo> ownerToolResults,
    required List<String> ownerExecutedCommands,
    List<String> ownerExecutedReleaseIdentities = const [],
    required this.approvalGranted,
    required Set<String> attemptedSignatures,
    required this.feedbackId,
    this.pendingBlockedRelease,
  }) : ownerToolResults = List<ToolResultInfo>.unmodifiable(
         ownerToolResults.map(_freezeToolResult),
       ),
       ownerExecutedCommands = List<String>.unmodifiable(ownerExecutedCommands),
       ownerExecutedReleaseIdentities = List<String>.unmodifiable(
         ownerExecutedReleaseIdentities,
       ),
       attemptedSignatures = Set<String>.unmodifiable(attemptedSignatures);

  final ChatTurnOwner owner;
  final List<ToolResultInfo> ownerToolResults;
  final List<String> ownerExecutedCommands;
  final List<String> ownerExecutedReleaseIdentities;
  final PendingBlockedRelease? pendingBlockedRelease;
  final bool approvalGranted;
  final Set<String> attemptedSignatures;
  final String feedbackId;

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) =>
      ToolResultInfo(
        id: result.id,
        name: result.name,
        arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
        result: result.result,
      );
}

enum BlockedProductionReleaseRetryNoPlanReason {
  noBlockedRelease,
  approvalMissing,
  alreadyExecuted,
  repeatedSignature,
}

final class BlockedProductionReleaseRetryPlan {
  const BlockedProductionReleaseRetryPlan({
    required this.owner,
    required this.toolName,
    required this.command,
    required this.executionIdentity,
    required this.workingDirectory,
    required this.background,
    required this.signature,
    required this.feedback,
  });

  final ChatTurnOwner owner;
  final String toolName;
  final String command;
  final String? executionIdentity;
  final String? workingDirectory;
  final bool background;
  final String signature;
  final ToolResultInfo feedback;
}

final class BlockedProductionReleaseRetryDisposition {
  const BlockedProductionReleaseRetryDisposition.plan(this.plan)
    : noPlanReason = null;

  const BlockedProductionReleaseRetryDisposition.noPlan(this.noPlanReason)
    : plan = null;

  final BlockedProductionReleaseRetryPlan? plan;
  final BlockedProductionReleaseRetryNoPlanReason? noPlanReason;
}
