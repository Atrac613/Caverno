import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolApprovalAutoReviewService', () {
    test('parses allow decisions', () {
      final decision = ToolApprovalAutoReviewService.parseDecision(
        '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this scoped edit."}',
      );

      expect(decision, isNotNull);
      expect(decision!.isAllowed, isTrue);
      expect(decision.riskLevel, 'low');
      expect(decision.userAuthorization, 'high');
    });

    test('parses fenced deny decisions', () {
      final decision = ToolApprovalAutoReviewService.parseDecision(
        '```json\n{"outcome":"deny","riskLevel":"critical","userAuthorization":"unknown","rationale":"The command deletes unrelated files."}\n```',
      );

      expect(decision, isNotNull);
      expect(decision!.isAllowed, isFalse);
      expect(decision.rationale, 'The command deletes unrelated files.');
    });

    test('returns null for malformed decisions', () {
      expect(
        ToolApprovalAutoReviewService.parseDecision('allow this action'),
        isNull,
      );
      expect(
        ToolApprovalAutoReviewService.parseDecision(
          '{"outcome":"maybe","rationale":"unclear"}',
        ),
        isNull,
      );
    });

    test('resolves a cached approval and records its audit source', () async {
      final audits = <String>[];
      var cachedCallbackCount = 0;

      final result = await ToolApprovalAutoReviewService.resolveGate(
        hasCachedApproval: true,
        mode: ToolApprovalMode.defaultPermissions,
        fullAccessEligible: false,
        review: () async => null,
        recordAudit:
            ({
              required String outcome,
              required String decisionSource,
              String? rationale,
              String? riskLevel,
            }) async => audits.add('$outcome:$decisionSource'),
        ownerIsCurrent: () => true,
        deniedEscalates: false,
        hasUntrustedInfluence: false,
        onCachedApproval: () => cachedCallbackCount += 1,
      );

      expect(result, ToolApprovalGateDecision.cachedApproval);
      expect(audits, ['allowed:cached_approval']);
      expect(cachedCallbackCount, 1);
    });

    test('rejects an allowing decision after its owner expires', () async {
      final audits = <String>[];
      final result = await ToolApprovalAutoReviewService.resolveGate(
        hasCachedApproval: false,
        mode: ToolApprovalMode.fullAccess,
        fullAccessEligible: true,
        review: () async => null,
        recordAudit:
            ({
              required String outcome,
              required String decisionSource,
              String? rationale,
              String? riskLevel,
            }) async => audits.add('$outcome:$decisionSource'),
        ownerIsCurrent: () => false,
        deniedEscalates: false,
        hasUntrustedInfluence: false,
      );

      expect(result.isDenied, isTrue);
      expect(result.deniedRationale, contains('turn expired'));
      expect(audits, ['denied:owner_expired']);
    });

    test('resolves every uncached approval mode and audit outcome', () async {
      Future<({ToolApprovalGateDecision decision, List<String> audits})>
      resolve({
        required ToolApprovalMode mode,
        required bool fullAccessEligible,
        ToolApprovalAutoReviewDecision? reviewDecision,
        bool deniedEscalates = false,
      }) async {
        final audits = <String>[];
        final decision = await ToolApprovalAutoReviewService.resolveGate(
          hasCachedApproval: false,
          mode: mode,
          fullAccessEligible: fullAccessEligible,
          review: () async => reviewDecision,
          recordAudit:
              ({
                required String outcome,
                required String decisionSource,
                String? rationale,
                String? riskLevel,
              }) async => audits.add('$outcome:$decisionSource'),
          ownerIsCurrent: () => true,
          deniedEscalates: deniedEscalates,
          hasUntrustedInfluence: false,
        );
        return (decision: decision, audits: audits);
      }

      final fullAccess = await resolve(
        mode: ToolApprovalMode.fullAccess,
        fullAccessEligible: true,
      );
      expect(fullAccess.decision, ToolApprovalGateDecision.fullAccess);
      expect(fullAccess.audits, ['allowed:full_access']);

      final ineligible = await resolve(
        mode: ToolApprovalMode.fullAccess,
        fullAccessEligible: false,
      );
      expect(ineligible.decision.needsManual, isTrue);
      expect(ineligible.audits, ['manual_fallback:full_access_ineligible']);

      final defaultMode = await resolve(
        mode: ToolApprovalMode.defaultPermissions,
        fullAccessEligible: true,
      );
      expect(defaultMode.decision.needsManual, isTrue);
      expect(defaultMode.audits, isEmpty);

      final unavailable = await resolve(
        mode: ToolApprovalMode.autoReview,
        fullAccessEligible: true,
      );
      expect(unavailable.decision.needsManual, isTrue);
      expect(unavailable.audits, ['review_unavailable:auto_review']);

      final allowed = await resolve(
        mode: ToolApprovalMode.autoReview,
        fullAccessEligible: true,
        reviewDecision: const ToolApprovalAutoReviewDecision(
          outcome: ToolApprovalAutoReviewOutcome.allow,
          riskLevel: 'low',
          userAuthorization: 'high',
          rationale: 'The user requested the scoped action.',
        ),
      );
      expect(allowed.decision, ToolApprovalGateDecision.autoReviewAllowed);
      expect(allowed.audits, ['allowed:auto_review']);

      final denied = await resolve(
        mode: ToolApprovalMode.autoReview,
        fullAccessEligible: true,
        reviewDecision: const ToolApprovalAutoReviewDecision(
          outcome: ToolApprovalAutoReviewOutcome.deny,
          riskLevel: 'high',
          userAuthorization: 'low',
          rationale: 'The action exceeds the request.',
        ),
      );
      expect(denied.decision.isDenied, isTrue);
      expect(denied.audits, ['denied:auto_review']);

      final escalated = await resolve(
        mode: ToolApprovalMode.autoReview,
        fullAccessEligible: true,
        deniedEscalates: true,
        reviewDecision: const ToolApprovalAutoReviewDecision(
          outcome: ToolApprovalAutoReviewOutcome.deny,
          riskLevel: 'medium',
          userAuthorization: 'unknown',
          rationale: 'A human should decide.',
        ),
      );
      expect(escalated.decision.needsManual, isTrue);
      expect(escalated.decision.escalatedFromAutoReviewDenial, isTrue);
      expect(escalated.audits, ['denied_escalated_manual:auto_review']);
    });

    test(
      'records owner expiry when it occurs during an allowing audit',
      () async {
        final audits = <String>[];
        var ownerIsCurrent = true;

        final result = await ToolApprovalAutoReviewService.resolveGate(
          hasCachedApproval: false,
          mode: ToolApprovalMode.fullAccess,
          fullAccessEligible: true,
          review: () async => null,
          recordAudit:
              ({
                required String outcome,
                required String decisionSource,
                String? rationale,
                String? riskLevel,
              }) async {
                audits.add('$outcome:$decisionSource');
                if (decisionSource == 'full_access') ownerIsCurrent = false;
              },
          ownerIsCurrent: () => ownerIsCurrent,
          deniedEscalates: false,
          hasUntrustedInfluence: false,
        );

        expect(result.isDenied, isTrue);
        expect(audits, ['allowed:full_access', 'denied:owner_expired']);
      },
    );

    test('keeps untrusted auto-review denials non-escalatable', () async {
      final result = await ToolApprovalAutoReviewService.resolveGate(
        hasCachedApproval: false,
        mode: ToolApprovalMode.autoReview,
        fullAccessEligible: true,
        review: () async => const ToolApprovalAutoReviewDecision(
          outcome: ToolApprovalAutoReviewOutcome.deny,
          riskLevel: 'high',
          userAuthorization: 'unknown',
          rationale: 'Untrusted content requested the write.',
        ),
        recordAudit:
            ({
              required String outcome,
              required String decisionSource,
              String? rationale,
              String? riskLevel,
            }) async {},
        ownerIsCurrent: () => true,
        deniedEscalates: true,
        hasUntrustedInfluence: true,
      );

      expect(result.isDenied, isTrue);
      expect(result.escalatedFromAutoReviewDenial, isFalse);
    });

    test('builds visible conversation tail without system messages', () {
      final now = DateTime(2026, 5, 26);
      final tail = ToolApprovalAutoReviewService.buildConversationTail([
        Message(
          id: 'system',
          role: MessageRole.system,
          content: 'hidden',
          timestamp: now,
        ),
        Message(
          id: 'user',
          role: MessageRole.user,
          content: 'Please edit README.',
          timestamp: now,
        ),
        Message(
          id: 'assistant',
          role: MessageRole.assistant,
          content: 'I will update it.',
          timestamp: now,
        ),
      ]);

      expect(tail.map((entry) => entry.role), ['user', 'assistant']);
      expect(tail.map((entry) => entry.content), [
        'Please edit README.',
        'I will update it.',
      ]);
    });

    Map<String, dynamic> capabilityFor(String toolName) {
      final messages = ToolApprovalAutoReviewService.buildMessages(
        ToolApprovalAutoReviewRequest(
          actionKind: toolName,
          toolName: toolName,
          arguments: const {'command': 'rm -rf build'},
          conversationTail: const [],
        ),
      );
      final user = messages.firstWhere((m) => m.role == MessageRole.user);
      final packet = jsonDecode(user.content) as Map<String, dynamic>;
      return (packet['action'] as Map)['capability'] as Map<String, dynamic>;
    }

    test('embeds SEC1 capability context in the review packet', () {
      final capability = capabilityFor('local_execute_command');
      expect(capability['class'], 'shellExecution');
      expect(capability['risk'], 'high');
      expect(capability['mutatesState'], isTrue);
    });

    test('marks untrusted output for a network fetch', () {
      final capability = capabilityFor('http_get');
      expect(capability['producesUntrustedContent'], isTrue);
    });

    Map<String, dynamic> packetFor({required bool hasUntrustedInfluence}) {
      final messages = ToolApprovalAutoReviewService.buildMessages(
        ToolApprovalAutoReviewRequest(
          actionKind: 'local_execute_command',
          toolName: 'local_execute_command',
          arguments: const {'command': 'rm -rf build'},
          conversationTail: const [],
          hasUntrustedInfluence: hasUntrustedInfluence,
        ),
      );
      final user = messages.firstWhere((m) => m.role == MessageRole.user);
      return (jsonDecode(user.content) as Map<String, dynamic>)['action']
          as Map<String, dynamic>;
    }

    test('surfaces SEC2 untrusted influence in the review packet', () {
      expect(
        packetFor(hasUntrustedInfluence: true)['untrustedInfluence'],
        isTrue,
      );
      expect(
        packetFor(hasUntrustedInfluence: false)['untrustedInfluence'],
        isFalse,
      );
    });
  });
}
