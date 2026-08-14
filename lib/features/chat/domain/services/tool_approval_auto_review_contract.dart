enum ToolApprovalAutoReviewOutcome { allow, deny }

enum ToolApprovalAutoReviewDomain {
  coding,
  browser,
  network,
  connection,
  participant,
}

typedef ToolApprovalGateAuditRecorder =
    Future<void> Function({
      required String outcome,
      required String decisionSource,
      String? rationale,
      String? riskLevel,
    });

class ToolApprovalAutoReviewDecision {
  const ToolApprovalAutoReviewDecision({
    required this.outcome,
    required this.riskLevel,
    required this.userAuthorization,
    required this.rationale,
  });

  final ToolApprovalAutoReviewOutcome outcome;
  final String riskLevel;
  final String userAuthorization;
  final String rationale;

  bool get isAllowed => outcome == ToolApprovalAutoReviewOutcome.allow;
}

class ToolApprovalConversationEntry {
  const ToolApprovalConversationEntry({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class ToolApprovalAutoReviewRequest {
  const ToolApprovalAutoReviewRequest({
    required this.actionKind,
    required this.toolName,
    required this.arguments,
    required this.conversationTail,
    this.path,
    this.workingDirectory,
    this.reason,
    this.warningTitle,
    this.warningMessage,
    this.preview,
    this.hasUntrustedInfluence = false,
  });

  final String actionKind;
  final String toolName;
  final Map<String, dynamic> arguments;
  final List<ToolApprovalConversationEntry> conversationTail;
  final String? path;
  final String? workingDirectory;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;
  final String? preview;
  final bool hasUntrustedInfluence;
}
