import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/tool_approval_gate.dart';

void main() {
  group('ToolApprovalGateDecision.fromAutoReviewDenial', () {
    test('escalates a user-driven denial to manual approval', () {
      // No untrusted content in context: the denial is the user's own request,
      // so the human gets to decide instead of the turn dead-ending.
      final decision = ToolApprovalGateDecision.fromAutoReviewDenial(
        'high-risk shell execution',
        hasUntrustedInfluence: false,
      );

      expect(decision.needsManual, isTrue);
      expect(decision.isDenied, isFalse);
      expect(decision.escalatedFromAutoReviewDenial, isTrue);
      expect(decision.autoReviewEscalationRationale, 'high-risk shell execution');
    });

    test('hard-denies when untrusted content is in context', () {
      // Untrusted (remote/MCP) content must never reach a human rubber-stamp,
      // so a tainted denial stays a hard deny and is never offered for approval.
      final decision = ToolApprovalGateDecision.fromAutoReviewDenial(
        'untrusted content driving a write',
        hasUntrustedInfluence: true,
      );

      expect(decision.isDenied, isTrue);
      expect(decision.needsManual, isFalse);
      expect(decision.escalatedFromAutoReviewDenial, isFalse);
      expect(decision.deniedRationale, 'untrusted content driving a write');
      expect(decision.autoReviewEscalationRationale, isNull);
    });
  });

  group('ToolApprovalGateDecision', () {
    test('plain manual approval is not an auto-review escalation', () {
      const decision = ToolApprovalGateDecision.needsManualApproval;

      expect(decision.needsManual, isTrue);
      expect(decision.escalatedFromAutoReviewDenial, isFalse);
      expect(decision.autoReviewEscalationRationale, isNull);
    });

    test('hard deny carries rationale but no escalation', () {
      final decision = ToolApprovalGateDecision.denied('blocked');

      expect(decision.isDenied, isTrue);
      expect(decision.needsManual, isFalse);
      expect(decision.deniedRationale, 'blocked');
      expect(decision.escalatedFromAutoReviewDenial, isFalse);
      expect(decision.autoReviewEscalationRationale, isNull);
    });

    test('full access bypasses approval and caching', () {
      expect(ToolApprovalGateDecision.fullAccess.runsDirectly, isTrue);
      expect(ToolApprovalGateDecision.fullAccess.bypassedApproval, isTrue);
      expect(ToolApprovalGateDecision.autoReviewAllowed.runsDirectly, isTrue);
      expect(ToolApprovalGateDecision.autoReviewAllowed.bypassedApproval, isFalse);
    });
  });
}
