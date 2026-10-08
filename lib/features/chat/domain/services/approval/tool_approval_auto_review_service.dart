import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../../../core/security/data_source_classifier.dart';
import '../../../../../core/security/taint_policy.dart';
import '../../entities/message.dart';
import 'tool_approval_auto_review_contract.dart';
import 'tool_approval_auto_review_prompts.dart';
import 'tool_approval_review_packet.dart';

export 'tool_approval_auto_review_contract.dart';

class ToolApprovalAutoReviewService {
  ToolApprovalAutoReviewService._();

  static const int _maxConversationEntries = 32;
  static const int _maxConversationContentChars = 8000;
  static const ToolCapabilityClassifier _capabilityClassifier =
      ToolCapabilityClassifier();
  static const TaintPolicy _taintPolicy = TaintPolicy();

  static Future<ToolApprovalGateDecision> resolveGate({
    required String toolName,
    required bool hasCachedApproval,
    required ToolApprovalMode mode,
    required bool fullAccessEligible,
    required Future<ToolApprovalAutoReviewDecision?> Function() review,
    required ToolApprovalGateAuditRecorder recordAudit,
    required bool Function() ownerIsCurrent,
    required bool deniedEscalates,
    required bool hasUntrustedInfluence,
    bool workspaceCommandContained = false,
    ToolApprovalGateDecision? requiredManualDecision,
    String requiredManualDecisionSource = 'required_manual',
    void Function()? onCachedApproval,
  }) async {
    const expiredRationale = 'The approval turn expired before execution';
    Future<ToolApprovalGateDecision> owned(
      ToolApprovalGateDecision decision,
    ) async {
      if (ownerIsCurrent()) return decision;
      await recordAudit(
        outcome: 'denied',
        decisionSource: 'owner_expired',
        rationale: expiredRationale,
      );
      return ToolApprovalGateDecision.denied(expiredRationale);
    }

    if (!ownerIsCurrent()) {
      return owned(ToolApprovalGateDecision.needsManualApproval);
    }
    final contained =
        workspaceCommandContained &&
        const {
          'local_execute_command',
          'process_start',
          'run_tests',
        }.contains(toolName);
    final taintDecision = _taintPolicy.assess(
      capability: _capabilityClassifier.classify(toolName),
      influencingTrustLevels: hasUntrustedInfluence
          ? const {TrustLevel.untrusted}
          : const {},
    );
    if (!contained && taintDecision == TaintDecision.block) {
      const rationale =
          'Untrusted content influenced a high-risk state-changing action.';
      await recordAudit(
        outcome: 'denied',
        decisionSource: 'taint_policy',
        rationale: rationale,
      );
      return owned(ToolApprovalGateDecision.denied(rationale));
    }
    if (!contained && taintDecision == TaintDecision.requireApproval) {
      await recordAudit(
        outcome: 'manual_required',
        decisionSource: 'taint_policy',
        rationale: 'Untrusted content requires a fresh non-cacheable approval.',
      );
      return owned(ToolApprovalGateDecision.needsManualApproval);
    }
    // Sits above the cache and full-access shortcuts on purpose. A caller
    // raises this when the action itself needs a person -- a shell command
    // that may name a path outside the project, say -- and such an action
    // must not be waved through by a rule saved for an earlier, narrower
    // command, nor summarized for a reviewer that may read past it: in
    // session db878d3a auto-review allowed a read under ~/.caverno while
    // stating it "operates within the selected project".
    if (requiredManualDecision != null) {
      await recordAudit(
        outcome: 'manual_required',
        decisionSource: requiredManualDecisionSource,
        rationale: requiredManualDecision.approvalPromptRationale,
      );
      return owned(requiredManualDecision);
    }
    // Script contents and untrusted inputs can change without changing argv.
    // Contained commands in auto-review mode therefore receive a fresh review.
    if (hasCachedApproval && !contained) {
      await recordAudit(outcome: 'allowed', decisionSource: 'cached_approval');
      onCachedApproval?.call();
      return owned(ToolApprovalGateDecision.cachedApproval);
    }
    if (mode == ToolApprovalMode.fullAccess &&
        !(contained && hasUntrustedInfluence)) {
      if (fullAccessEligible) {
        await recordAudit(outcome: 'allowed', decisionSource: 'full_access');
        return owned(ToolApprovalGateDecision.fullAccess);
      }
      await recordAudit(
        outcome: 'manual_fallback',
        decisionSource: 'full_access_ineligible',
      );
      return owned(ToolApprovalGateDecision.needsManualApproval);
    }
    if (mode != ToolApprovalMode.autoReview &&
        !(contained &&
            hasUntrustedInfluence &&
            mode == ToolApprovalMode.fullAccess)) {
      await recordAudit(
        outcome: 'manual_required',
        decisionSource: 'default_permissions',
        rationale: 'The selected approval mode requires a fresh decision.',
      );
      return owned(ToolApprovalGateDecision.needsManualApproval);
    }
    final decision = await review();
    if (decision == null) {
      await recordAudit(
        outcome: 'review_unavailable',
        decisionSource: 'auto_review',
      );
      return owned(ToolApprovalGateDecision.needsManualApproval);
    }
    if (decision.isAllowed) {
      await recordAudit(
        outcome: 'allowed',
        decisionSource: 'auto_review',
        rationale: decision.rationale,
        riskLevel: decision.riskLevel,
      );
      return owned(ToolApprovalGateDecision.autoReviewAllowed);
    }
    final gateDecision = deniedEscalates
        ? ToolApprovalGateDecision.fromAutoReviewDenial(
            decision.rationale,
            hasUntrustedInfluence: hasUntrustedInfluence,
          )
        : ToolApprovalGateDecision.denied(decision.rationale);
    await recordAudit(
      outcome: gateDecision.escalatedFromAutoReviewDenial
          ? 'denied_escalated_manual'
          : 'denied',
      decisionSource: 'auto_review',
      rationale: decision.rationale,
      riskLevel: decision.riskLevel,
    );
    return owned(gateDecision);
  }

  static List<ToolApprovalConversationEntry> buildConversationTail(
    List<Message> messages,
  ) {
    return messages
        .where(
          (message) =>
              message.role == MessageRole.user ||
              message.role == MessageRole.assistant,
        )
        .takeLast(_maxConversationEntries)
        .map(
          (message) => ToolApprovalConversationEntry(
            // Compatibility user-role tool envelopes are not human consent.
            role: message.isSynthesizedPrompt
                ? 'untrusted_context'
                : message.role.name,
            content: _truncate(message.content, _maxConversationContentChars),
          ),
        )
        .toList(growable: false);
  }

  static List<Message> buildMessages(
    ToolApprovalAutoReviewRequest request, {
    ToolApprovalAutoReviewDomain domain = ToolApprovalAutoReviewDomain.coding,
  }) {
    final now = DateTime.now();
    return [
      Message(
        id: 'auto_review_policy',
        role: MessageRole.system,
        timestamp: now,
        content: ToolApprovalAutoReviewPrompts.policyFor(domain),
      ),
      Message(
        id: 'auto_review_request',
        role: MessageRole.user,
        timestamp: now,
        content: jsonEncode(ToolApprovalReviewPacket.build(request)),
      ),
    ];
  }

  static ToolApprovalAutoReviewDecision? parseDecision(String content) {
    final jsonText = _extractJsonObject(content);
    if (jsonText == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final outcomeText = '${decoded['outcome'] ?? ''}'.trim().toLowerCase();
    final outcome = switch (outcomeText) {
      'allow' => ToolApprovalAutoReviewOutcome.allow,
      'deny' => ToolApprovalAutoReviewOutcome.deny,
      _ => null,
    };
    if (outcome == null) return null;

    final rationale = '${decoded['rationale'] ?? ''}'.trim();
    if (rationale.isEmpty) return null;

    return ToolApprovalAutoReviewDecision(
      outcome: outcome,
      riskLevel: '${decoded['riskLevel'] ?? 'unknown'}'.trim(),
      userAuthorization: '${decoded['userAuthorization'] ?? 'unknown'}'.trim(),
      rationale: rationale,
    );
  }

  static String? _extractJsonObject(String content) {
    var candidate = content.trim();
    final fenced = RegExp(
      r'^```(?:json)?\s*(.*?)\s*```$',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(candidate);
    if (fenced != null) {
      candidate = fenced.group(1)!.trim();
    }

    if (candidate.startsWith('{') && candidate.endsWith('}')) {
      return candidate;
    }

    final start = candidate.indexOf('{');
    final end = candidate.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    return candidate.substring(start, end + 1);
  }

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }
}

extension _TakeLastExtension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList(growable: false);
    if (values.length <= count) return values;
    return values.skip(values.length - count);
  }
}
