import '../entities/conversation_workflow.dart';
import 'conversation_workflow_conflict_preservation_service.dart';

enum ConversationWorkflowStageConfirmationBlocker {
  confirmationUnavailable,
  invalidRequestFields,
  currentContextMismatch,
  confirmationResultMismatch,
  confirmationDeclined,
  invalidConfirmationFields,
}

final class ConversationWorkflowStageConfirmationRequest {
  const ConversationWorkflowStageConfirmationRequest({
    required this.requestId,
    required this.contextSchemaVersion,
    required this.contextDigest,
    required this.workflowStage,
    required this.approvedPlanStage,
    required this.activeProgressCount,
    required this.orphanProgressCount,
    required this.requestedAt,
  });

  final String requestId;
  final int contextSchemaVersion;
  final String contextDigest;
  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowStage approvedPlanStage;
  final int activeProgressCount;
  final int orphanProgressCount;
  final DateTime requestedAt;
}

sealed class ConversationWorkflowStageConfirmationResult {
  const ConversationWorkflowStageConfirmationResult({
    required this.requestId,
    required this.contextDigest,
    required this.respondedAt,
  });

  final String requestId;
  final String contextDigest;
  final DateTime respondedAt;
}

final class ConversationWorkflowStageConfirmed
    extends ConversationWorkflowStageConfirmationResult {
  const ConversationWorkflowStageConfirmed({
    required super.requestId,
    required super.contextDigest,
    required super.respondedAt,
    required this.decisionId,
    required this.authority,
  });

  final String decisionId;
  final ConversationWorkflowConflictStageAuthority authority;
}

final class ConversationWorkflowStageConfirmationDeclined
    extends ConversationWorkflowStageConfirmationResult {
  const ConversationWorkflowStageConfirmationDeclined({
    required super.requestId,
    required super.contextDigest,
    required super.respondedAt,
  });
}

abstract interface class ConversationWorkflowStageConfirmationPort {
  Future<ConversationWorkflowStageConfirmationResult> requestConfirmation(
    ConversationWorkflowStageConfirmationRequest request,
  );
}

final class ConversationWorkflowStageConfirmationRequestBuildResult {
  ConversationWorkflowStageConfirmationRequestBuildResult({
    required List<ConversationWorkflowStageConfirmationBlocker> blockers,
    this.request,
  }) : blockers = List.unmodifiable(blockers);

  final List<ConversationWorkflowStageConfirmationBlocker> blockers;
  final ConversationWorkflowStageConfirmationRequest? request;

  bool get isBuilt => blockers.isEmpty && request != null;
}

final class ConversationWorkflowStageConfirmationResolution {
  ConversationWorkflowStageConfirmationResolution({
    required List<ConversationWorkflowStageConfirmationBlocker> blockers,
    this.decision,
  }) : blockers = List.unmodifiable(blockers);

  final List<ConversationWorkflowStageConfirmationBlocker> blockers;
  final ConversationWorkflowConflictStageDecision? decision;

  bool get isConfirmed => blockers.isEmpty && decision != null;
}

final class ConversationWorkflowStageConfirmationContract {
  const ConversationWorkflowStageConfirmationContract();

  ConversationWorkflowStageConfirmationRequestBuildResult buildRequest({
    required String requestId,
    required DateTime requestedAt,
    required ConversationWorkflowConflictPreservationResult preservationResult,
  }) {
    final envelope = preservationResult.envelope;
    if (!_requiresStageAuthority(preservationResult) || envelope == null) {
      return _buildBlocked(
        ConversationWorkflowStageConfirmationBlocker.confirmationUnavailable,
      );
    }
    final request = ConversationWorkflowStageConfirmationRequest(
      requestId: requestId,
      contextSchemaVersion: envelope.decisionContext.schemaVersion,
      contextDigest: envelope.decisionContext.contextDigest,
      workflowStage: envelope.workflowStage,
      approvedPlanStage: envelope.approvedPlanStage,
      activeProgressCount: envelope.activeExecutionProgress.length,
      orphanProgressCount: envelope.orphanExecutionProgress.length,
      requestedAt: requestedAt,
    );
    if (!_isValidRequest(request)) {
      return _buildBlocked(
        ConversationWorkflowStageConfirmationBlocker.invalidRequestFields,
      );
    }
    return ConversationWorkflowStageConfirmationRequestBuildResult(
      blockers: const [],
      request: request,
    );
  }

  ConversationWorkflowStageConfirmationResolution resolve({
    required ConversationWorkflowStageConfirmationRequest request,
    required ConversationWorkflowStageConfirmationResult result,
    required ConversationWorkflowConflictPreservationResult
    currentPreservationResult,
  }) {
    if (!_isValidRequest(request)) {
      return _resolveBlocked(
        ConversationWorkflowStageConfirmationBlocker.invalidRequestFields,
      );
    }
    if (!_matchesCurrentContext(request, currentPreservationResult)) {
      return _resolveBlocked(
        ConversationWorkflowStageConfirmationBlocker.currentContextMismatch,
      );
    }
    if (result.requestId != request.requestId ||
        result.contextDigest != request.contextDigest) {
      return _resolveBlocked(
        ConversationWorkflowStageConfirmationBlocker.confirmationResultMismatch,
      );
    }
    if (!result.respondedAt.isUtc ||
        result.respondedAt.isBefore(request.requestedAt)) {
      return _resolveBlocked(
        ConversationWorkflowStageConfirmationBlocker.invalidConfirmationFields,
      );
    }
    if (result is ConversationWorkflowStageConfirmationDeclined) {
      return _resolveBlocked(
        ConversationWorkflowStageConfirmationBlocker.confirmationDeclined,
      );
    }
    final confirmed = result as ConversationWorkflowStageConfirmed;
    if (confirmed.decisionId.trim().isEmpty) {
      return _resolveBlocked(
        ConversationWorkflowStageConfirmationBlocker.invalidConfirmationFields,
      );
    }
    return ConversationWorkflowStageConfirmationResolution(
      blockers: const [],
      decision: ConversationWorkflowConflictStageDecision(
        decisionId: confirmed.decisionId,
        contextDigest: request.contextDigest,
        authority: confirmed.authority,
        source: ConversationWorkflowConflictStageDecisionSource
            .manualUserConfirmation,
        decidedAt: confirmed.respondedAt,
      ),
    );
  }

  bool _requiresStageAuthority(
    ConversationWorkflowConflictPreservationResult result,
  ) {
    final envelope = result.envelope;
    return envelope != null &&
        result.mergeBlockers.isEmpty &&
        result.blockers.length == 1 &&
        result.blockers.single ==
            ConversationWorkflowConflictPreservationBlocker
                .stageAuthorityRequired &&
        envelope.workflowStage != envelope.approvedPlanStage &&
        envelope.selectedStage == null &&
        envelope.stageDecision == null;
  }

  bool _isValidRequest(ConversationWorkflowStageConfirmationRequest request) {
    return request.requestId.trim().isNotEmpty &&
        request.contextSchemaVersion == 1 &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(request.contextDigest) &&
        request.workflowStage != request.approvedPlanStage &&
        request.activeProgressCount >= 0 &&
        request.orphanProgressCount > 0 &&
        request.requestedAt.isUtc;
  }

  bool _matchesCurrentContext(
    ConversationWorkflowStageConfirmationRequest request,
    ConversationWorkflowConflictPreservationResult current,
  ) {
    final envelope = current.envelope;
    return _requiresStageAuthority(current) &&
        envelope != null &&
        envelope.decisionContext.schemaVersion ==
            request.contextSchemaVersion &&
        envelope.decisionContext.contextDigest == request.contextDigest &&
        envelope.workflowStage == request.workflowStage &&
        envelope.approvedPlanStage == request.approvedPlanStage &&
        envelope.activeExecutionProgress.length ==
            request.activeProgressCount &&
        envelope.orphanExecutionProgress.length == request.orphanProgressCount;
  }

  ConversationWorkflowStageConfirmationRequestBuildResult _buildBlocked(
    ConversationWorkflowStageConfirmationBlocker blocker,
  ) {
    return ConversationWorkflowStageConfirmationRequestBuildResult(
      blockers: [blocker],
    );
  }

  ConversationWorkflowStageConfirmationResolution _resolveBlocked(
    ConversationWorkflowStageConfirmationBlocker blocker,
  ) {
    return ConversationWorkflowStageConfirmationResolution(blockers: [blocker]);
  }
}
