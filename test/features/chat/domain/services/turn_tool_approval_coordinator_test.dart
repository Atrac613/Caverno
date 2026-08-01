import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_approval_coordinator.dart';
import 'package:test/test.dart';

final class _OwnerPort implements ToolApprovalOwnerPort {
  final Set<ChatTurnOwner> currentOwners = {};

  @override
  bool isCurrent(ChatTurnOwner owner) => currentOwners.contains(owner);
}

final class _ManualPort implements ManualToolApprovalPort {
  ManualToolApprovalDecision decision =
      const ManualToolApprovalDecision.approved();
  final List<ChatTurnOwner> owners = [];
  final List<ManualToolApprovalRequest> requests = [];
  void Function(ChatTurnOwner owner)? onRequest;
  Object? error;

  @override
  Future<ManualToolApprovalDecision> requestApproval(
    ChatTurnOwner owner,
    ManualToolApprovalRequest request,
  ) async {
    owners.add(owner);
    requests.add(request);
    onRequest?.call(owner);
    if (error case final value?) {
      throw value;
    }
    return decision;
  }
}

final class _AutoReviewPort implements ToolApprovalAutoReviewPort {
  ToolApprovalAutoReviewDecision? decision;
  Object? error;
  final List<ChatTurnOwner> owners = [];
  final List<ToolApprovalAutoReviewRequest> requests = [];
  final List<ToolApprovalAutoReviewDomain> domains = [];
  void Function(ChatTurnOwner owner)? onReview;

  @override
  Future<ToolApprovalAutoReviewDecision?> review(
    ChatTurnOwner owner,
    ToolApprovalAutoReviewRequest request, {
    required ToolApprovalAutoReviewDomain domain,
  }) async {
    owners.add(owner);
    requests.add(request);
    domains.add(domain);
    onReview?.call(owner);
    if (error case final value?) {
      throw value;
    }
    return decision;
  }
}

final class _AuditPort implements ToolApprovalAuditPort {
  final List<ChatTurnOwner> owners = [];
  final List<ToolApprovalAuditRecord> records = [];
  bool shouldThrow = false;
  void Function(ChatTurnOwner owner)? onRecord;

  @override
  Future<void> record(
    ChatTurnOwner owner,
    ToolApprovalAuditRecord record,
  ) async {
    owners.add(owner);
    records.add(record);
    onRecord?.call(owner);
    if (shouldThrow) {
      throw StateError('audit unavailable');
    }
  }
}

final class _Harness {
  _Harness() {
    coordinator = TurnToolApprovalCoordinator(
      manualApprovalPort: manual,
      autoReviewPort: autoReview,
      auditPort: audit,
      ownerPort: owners,
    );
  }

  final _OwnerPort owners = _OwnerPort();
  final _ManualPort manual = _ManualPort();
  final _AutoReviewPort autoReview = _AutoReviewPort();
  final _AuditPort audit = _AuditPort();
  late final TurnToolApprovalCoordinator coordinator;
}

ChatTurnOwner _owner(String conversationId, [int generation = 1]) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

ToolApprovalRequest _request({
  required ChatTurnOwner owner,
  ToolApprovalMode mode = ToolApprovalMode.defaultPermissions,
  ToolApprovalAutoReviewDomain domain = ToolApprovalAutoReviewDomain.coding,
  bool fullAccessEligible = false,
  bool cacheable = true,
  Map<String, dynamic>? arguments,
  Map<String, dynamic>? cacheArguments,
  String? cacheStateFingerprint,
  String? warningTitle = 'Confirm action',
  String? warningMessage = 'Review this action.',
  List<Message> conversationMessages = const [],
  bool hasUntrustedInfluence = false,
}) {
  final effectiveArguments =
      arguments ??
      <String, dynamic>{
        'path': 'lib/main.dart',
        'reason': 'update implementation',
      };
  return ToolApprovalRequest(
    owner: owner,
    toolCallId: 'call-1',
    toolName: 'write_file',
    arguments: effectiveArguments,
    actionKind: 'write file',
    mode: mode,
    reviewDomain: domain,
    fullAccessEligible: fullAccessEligible,
    cacheArguments: cacheable ? cacheArguments ?? effectiveArguments : null,
    cacheStateFingerprint: cacheStateFingerprint,
    path: 'lib/main.dart',
    workingDirectory: '/workspace/project',
    reason: 'Update the implementation.',
    warningTitle: warningTitle,
    warningMessage: warningMessage,
    preview: 'replacement preview',
    conversationMessages: conversationMessages,
    hasUntrustedInfluence: hasUntrustedInfluence,
  );
}

McpToolResult _result({
  String toolName = 'write_file',
  String result = 'done',
  bool isSuccess = true,
  String? errorMessage,
}) {
  return McpToolResult(
    toolName: toolName,
    result: result,
    isSuccess: isSuccess,
    errorMessage: errorMessage,
  );
}

ToolApprovalAutoReviewDecision _reviewDecision({
  required ToolApprovalAutoReviewOutcome outcome,
  String rationale = 'The request is scoped.',
  String riskLevel = 'low',
}) {
  return ToolApprovalAutoReviewDecision(
    outcome: outcome,
    riskLevel: riskLevel,
    userAuthorization: 'high',
    rationale: rationale,
  );
}

void main() {
  group('immutable requests and records', () {
    test('deep-freezes arguments, cache identity, and messages', () {
      final nested = <String, dynamic>{
        'path': 'lib/main.dart',
        'options': <String, dynamic>{
          'flags': <Object?>['safe', true, 2, null],
          'tags': <Object?>['owner-a'],
        },
      };
      final messages = <Message>[
        Message(
          id: 'user-1',
          role: MessageRole.user,
          content: 'Update the file.',
          timestamp: DateTime(2026),
        ),
      ];
      final request = _request(
        owner: _owner('thread-a'),
        arguments: nested,
        cacheArguments: nested,
        conversationMessages: messages,
      );

      (nested['options'] as Map<String, dynamic>)['flags'] = ['changed'];
      ((nested['options'] as Map<String, dynamic>)['tags'] as List<Object?>)
          .add('owner-b');
      messages.clear();

      expect(request.arguments['options'], {
        'flags': ['safe', true, 2, null],
        'tags': ['owner-a'],
      });
      expect(request.cacheArguments, request.arguments);
      expect(request.conversationMessages, hasLength(1));
      expect(
        () => request.arguments['path'] = 'lib/changed.dart',
        throwsUnsupportedError,
      );
      expect(
        () => (request.arguments['options'] as Map)['new'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => (request.arguments['options'] as Map)['flags'].add('changed'),
        throwsUnsupportedError,
      );
      expect(
        () => (request.arguments['options'] as Map)['tags'].add('changed'),
        throwsUnsupportedError,
      );
    });

    test('rejects non-JSON request values', () {
      final owner = _owner('thread-a');
      for (final value in <Object?>[
        <Object?, Object?>{7: 'seven'},
        <Object?>{'set'},
        DateTime.utc(2026),
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => _request(owner: owner, arguments: {'value': value}),
          throwsArgumentError,
          reason: value.toString(),
        );
      }
    });
  });

  group('manual and cached decisions', () {
    test('returns manual approval with unchanged fallback warnings', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      harness.manual.decision = const ManualToolApprovalDecision.approved(
        rememberApproval: true,
      );

      final outcome = await harness.coordinator.resolve(_request(owner: owner));

      expect(outcome.isApproved, isTrue);
      expect(outcome.rememberApproval, isTrue);
      expect(outcome.gateDecision?.needsManual, isTrue);
      expect(harness.manual.owners, [owner]);
      expect(harness.manual.requests.single.warningTitle, 'Confirm action');
      expect(
        harness.manual.requests.single.warningMessage,
        'Review this action.',
      );
      expect(harness.autoReview.requests, isEmpty);
      expect(harness.audit.records, isEmpty);
      expect(
        () => harness.manual.requests.single.arguments['path'] = 'poison.dart',
        throwsUnsupportedError,
      );
      expect(const ManualToolApprovalDecision.approved().isApproved, isTrue);
    });

    test(
      'propagates a manual port failure without caching a decision',
      () async {
        final harness = _Harness();
        final owner = _owner('thread-a');
        harness.owners.currentOwners.add(owner);
        final error = StateError('manual approval unavailable');
        harness.manual.error = error;

        await expectLater(
          harness.coordinator.resolve(_request(owner: owner)),
          throwsA(same(error)),
        );
        harness.manual.error = null;
        final retry = await harness.coordinator.resolve(_request(owner: owner));

        expect(retry.isApproved, isTrue);
        expect(harness.manual.requests, hasLength(2));
      },
    );

    test('caches and reuses an exact manual denial result', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      final denial = _result(
        result: '',
        isSuccess: false,
        errorMessage: 'User denied the write.',
      );
      harness.manual.decision = ManualToolApprovalDecision.denied(denial);
      expect(harness.manual.decision.isApproved, isFalse);

      final request = _request(owner: owner);
      final first = await harness.coordinator.resolve(request);
      final second = await harness.coordinator.resolve(
        _request(
          owner: owner,
          mode: ToolApprovalMode.fullAccess,
          fullAccessEligible: true,
        ),
      );

      expect(first.denialResult, same(denial));
      expect(second.denialResult, same(denial));
      expect(first.reusedCachedDenial, isFalse);
      expect(second.reusedCachedDenial, isTrue);
      expect(second.gateDecision, isNull);
      expect(harness.manual.requests, hasLength(1));
      expect(harness.autoReview.requests, isEmpty);
      expect(harness.audit.records, isEmpty);
    });

    test('reuses remembered approval with deterministic identity', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      final firstRequest = _request(
        owner: owner,
        cacheStateFingerprint: 'state-a',
        cacheArguments: {
          'z': 'stable-value',
          'reason': 'first wording',
          'nested': {
            'enabled': true,
            'values': [1, null, 'two'],
          },
        },
      );

      await harness.coordinator.resolve(firstRequest);
      final executionResult = _result();
      expect(
        harness.coordinator.rememberApprovalResult(
          firstRequest,
          executionResult,
        ),
        same(executionResult),
      );
      final reused = await harness.coordinator.resolve(
        _request(
          owner: owner,
          mode: ToolApprovalMode.autoReview,
          cacheStateFingerprint: 'state-a',
          cacheArguments: {
            'nested': {
              'values': [1, null, 'two'],
              'enabled': true,
            },
            'reason': 'different wording',
            'z': 'stable-value',
          },
        ),
      );

      expect(reused.isApproved, isTrue);
      expect(reused.gateDecision, ToolApprovalGateDecision.cachedApproval);
      expect(reused.reusedCachedApproval, isTrue);
      expect(harness.manual.requests, hasLength(1));
      expect(harness.audit.records.single.decisionSource, 'cached_approval');
      expect(
        harness.audit.records.single.arguments['reason'],
        'different wording',
      );
      expect(harness.autoReview.requests, isEmpty);
    });

    test('does not reuse null cache identities or distinct state', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      final uncached = _request(owner: owner, cacheable: false);
      await harness.coordinator.resolve(uncached);
      harness.coordinator.rememberApprovalResult(uncached, _result());
      await harness.coordinator.resolve(uncached);

      final stateA = _request(owner: owner, cacheStateFingerprint: 'state-a');
      await harness.coordinator.resolve(stateA);
      harness.coordinator.rememberApprovalResult(stateA, _result());
      await harness.coordinator.resolve(
        _request(owner: owner, cacheStateFingerprint: 'state-b'),
      );

      expect(harness.manual.requests, hasLength(4));
    });

    test('isolates equal generations and later generations', () async {
      final harness = _Harness();
      final ownerA = _owner('thread-a');
      final ownerB = _owner('thread-b');
      final ownerANext = _owner('thread-a', 2);
      harness.owners.currentOwners.addAll([ownerA, ownerB, ownerANext]);
      final requestA = _request(owner: ownerA);

      await harness.coordinator.resolve(requestA);
      harness.coordinator.rememberApprovalResult(requestA, _result());
      await harness.coordinator.resolve(_request(owner: ownerB));
      await harness.coordinator.resolve(_request(owner: ownerANext));
      final reusedA = await harness.coordinator.resolve(requestA);

      expect(harness.manual.owners, [ownerA, ownerB, ownerANext]);
      expect(reusedA.gateDecision, ToolApprovalGateDecision.cachedApproval);
    });

    test('does not replay one owner denial to a peer or successor', () async {
      final harness = _Harness();
      final ownerA = _owner('thread-a');
      final ownerB = _owner('thread-b');
      final ownerANext = _owner('thread-a', 2);
      harness.owners.currentOwners.addAll([ownerA, ownerB, ownerANext]);
      final denial = _result(
        result: '',
        isSuccess: false,
        errorMessage: 'User denied owner A.',
      );
      harness.manual.decision = ManualToolApprovalDecision.denied(denial);
      await harness.coordinator.resolve(_request(owner: ownerA));
      harness.manual.decision = const ManualToolApprovalDecision.approved();

      final peer = await harness.coordinator.resolve(_request(owner: ownerB));
      final successor = await harness.coordinator.resolve(
        _request(owner: ownerANext),
      );
      final replay = await harness.coordinator.resolve(_request(owner: ownerA));

      expect(peer.isApproved, isTrue);
      expect(successor.isApproved, isTrue);
      expect(replay.denialResult, same(denial));
      expect(replay.reusedCachedDenial, isTrue);
      expect(harness.manual.owners, [ownerA, ownerB, ownerANext]);
    });
  });

  group('cached-denial preflight', () {
    test('returns an exact cached denial before continuation work', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      final denial = _result(
        result: '',
        isSuccess: false,
        errorMessage: 'User denied the write.',
      );
      harness.manual.decision = ManualToolApprovalDecision.denied(denial);
      final request = _request(owner: owner);
      await harness.coordinator.resolve(request);

      final preflight = await harness.coordinator.preflightCachedDenial(
        request,
      );

      expect(preflight.request, same(request));
      expect(preflight.outcome?.denialResult, same(denial));
      expect(harness.manual.requests, hasLength(1));
      await expectLater(
        harness.coordinator.resolveAfterPreflight(preflight),
        throwsStateError,
      );
    });

    test('binds a one-shot continuation to its coordinator', () async {
      final harness = _Harness();
      final otherHarness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      otherHarness.owners.currentOwners.add(owner);
      final preflight = await harness.coordinator.preflightCachedDenial(
        _request(owner: owner),
      );

      await expectLater(
        otherHarness.coordinator.resolveAfterPreflight(preflight),
        throwsStateError,
      );
      final outcome = await harness.coordinator.resolveAfterPreflight(
        preflight,
        targetDisplayName: 'Desk Sensor',
      );
      expect(outcome.isApproved, isTrue);
      expect(harness.manual.owners, [owner]);
      expect(harness.manual.requests.single.targetDisplayName, 'Desk Sensor');
      await expectLater(
        harness.coordinator.resolveAfterPreflight(preflight),
        throwsStateError,
      );
    });

    test('expires ownership between preflight and continuation', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      final preflight = await harness.coordinator.preflightCachedDenial(
        _request(owner: owner),
      );
      harness.owners.currentOwners.remove(owner);

      final outcome = await harness.coordinator.resolveAfterPreflight(
        preflight,
      );

      expect(outcome.isApproved, isFalse);
      expect(
        outcome.denialResult?.errorMessage,
        'The approval turn expired before execution',
      );
      expect(harness.manual.requests, isEmpty);
      expect(harness.audit.records.single.decisionSource, 'owner_expired');
    });
  });

  group('automated gate precedence', () {
    test('runs eligible full access and audits ineligible fallback', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);

      final direct = await harness.coordinator.resolve(
        _request(
          owner: owner,
          mode: ToolApprovalMode.fullAccess,
          fullAccessEligible: true,
        ),
      );
      final fallback = await harness.coordinator.resolve(
        _request(
          owner: owner,
          mode: ToolApprovalMode.fullAccess,
          fullAccessEligible: false,
          cacheable: false,
        ),
      );

      expect(direct.gateDecision, ToolApprovalGateDecision.fullAccess);
      expect(fallback.gateDecision?.needsManual, isTrue);
      expect(harness.audit.records.map((record) => record.decisionSource), [
        'full_access',
        'full_access_ineligible',
      ]);
      expect(harness.autoReview.requests, isEmpty);
    });

    test('allows auto-review and builds the exact owner request', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      harness.autoReview.decision = _reviewDecision(
        outcome: ToolApprovalAutoReviewOutcome.allow,
      );
      final messages = List<Message>.generate(
        10,
        (index) => Message(
          id: 'message-$index',
          role: index.isEven ? MessageRole.user : MessageRole.assistant,
          content: index == 9 ? 'x' * 950 : 'message $index',
          timestamp: DateTime(2026, 1, index + 1),
        ),
      );

      final outcome = await harness.coordinator.resolve(
        _request(
          owner: owner,
          mode: ToolApprovalMode.autoReview,
          conversationMessages: messages,
          hasUntrustedInfluence: true,
        ),
      );

      expect(outcome.gateDecision, ToolApprovalGateDecision.autoReviewAllowed);
      expect(harness.autoReview.owners, [owner]);
      expect(harness.autoReview.domains, [ToolApprovalAutoReviewDomain.coding]);
      final review = harness.autoReview.requests.single;
      expect(review.actionKind, 'write file');
      expect(review.toolName, 'write_file');
      expect(review.arguments['path'], 'lib/main.dart');
      expect(review.path, 'lib/main.dart');
      expect(review.workingDirectory, '/workspace/project');
      expect(review.reason, 'Update the implementation.');
      expect(review.warningTitle, 'Confirm action');
      expect(review.warningMessage, 'Review this action.');
      expect(review.preview, 'replacement preview');
      expect(review.hasUntrustedInfluence, isTrue);
      expect(review.conversationTail, hasLength(8));
      expect(review.conversationTail.last.content, endsWith('...'));
      expect(
        () => review.arguments['path'] = 'poison.dart',
        throwsUnsupportedError,
      );
      final audit = harness.audit.records.single;
      expect(audit.outcome, 'allowed');
      expect(audit.decisionSource, 'auto_review');
      expect(audit.rationale, 'The request is scoped.');
      expect(audit.riskLevel, 'low');
      expect(audit.hasUntrustedInfluence, isTrue);
      expect(
        () => audit.arguments['path'] = 'poison.dart',
        throwsUnsupportedError,
      );
    });

    test('falls back to manual when auto-review returns no decision', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);

      final outcome = await harness.coordinator.resolve(
        _request(owner: owner, mode: ToolApprovalMode.autoReview),
      );

      expect(outcome.isApproved, isTrue);
      expect(outcome.gateDecision?.needsManual, isTrue);
      expect(harness.autoReview.requests, hasLength(1));
      expect(harness.manual.requests, hasLength(1));
      expect(harness.audit.records.single.outcome, 'review_unavailable');
      expect(harness.audit.records.single.decisionSource, 'auto_review');
    });

    test('falls back to manual on auto-review and audit errors', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      harness.autoReview.error = StateError('review unavailable');
      harness.audit.shouldThrow = true;

      final outcome = await harness.coordinator.resolve(
        _request(owner: owner, mode: ToolApprovalMode.autoReview),
      );

      expect(outcome.isApproved, isTrue);
      expect(outcome.gateDecision?.needsManual, isTrue);
      expect(harness.manual.requests, hasLength(1));
      expect(harness.audit.records.single.outcome, 'review_unavailable');
    });

    test('escalates an untainted coding denial with warning copy', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      harness.autoReview.decision = _reviewDecision(
        outcome: ToolApprovalAutoReviewOutcome.deny,
        rationale: 'The write needs confirmation.',
        riskLevel: 'medium',
      );

      final outcome = await harness.coordinator.resolve(
        _request(owner: owner, mode: ToolApprovalMode.autoReview),
      );

      expect(outcome.isApproved, isTrue);
      expect(outcome.gateDecision?.escalatedFromAutoReviewDenial, isTrue);
      final prompt = harness.manual.requests.single;
      expect(prompt.warningTitle, 'Auto-review flagged this action');
      expect(
        prompt.warningMessage,
        'The write needs confirmation.\n\nReview this action.',
      );
      expect(harness.audit.records.single.outcome, 'denied_escalated_manual');
      expect(
        harness.coordinator.domainEscalatesDeniedActionToManual(
          ToolApprovalAutoReviewDomain.coding,
        ),
        isTrue,
      );
    });

    test('uses rationale alone when escalation has no fallback', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      harness.autoReview.decision = _reviewDecision(
        outcome: ToolApprovalAutoReviewOutcome.deny,
        rationale: 'Review required.',
      );

      await harness.coordinator.resolve(
        _request(
          owner: owner,
          mode: ToolApprovalMode.autoReview,
          warningMessage: null,
        ),
      );

      expect(harness.manual.requests.single.warningMessage, 'Review required.');
    });

    test(
      'hard-denies tainted or non-coding review and caches payload',
      () async {
        for (final configuration in [
          (domain: ToolApprovalAutoReviewDomain.coding, untrusted: true),
          (domain: ToolApprovalAutoReviewDomain.browser, untrusted: false),
        ]) {
          final harness = _Harness();
          final owner = _owner('thread-${configuration.domain.name}');
          harness.owners.currentOwners.add(owner);
          harness.autoReview.decision = _reviewDecision(
            outcome: ToolApprovalAutoReviewOutcome.deny,
            rationale: 'The action is unsafe.',
            riskLevel: 'high',
          );
          final request = _request(
            owner: owner,
            mode: ToolApprovalMode.autoReview,
            domain: configuration.domain,
            hasUntrustedInfluence: configuration.untrusted,
          );

          final denied = await harness.coordinator.resolve(request);
          final cached = await harness.coordinator.resolve(request);

          expect(denied.isApproved, isFalse);
          expect(
            denied.denialResult?.result,
            'Auto-review denied this action. Rationale: '
            'The action is unsafe.',
          );
          expect(denied.denialResult?.toolName, 'write_file');
          expect(denied.denialResult?.isSuccess, isFalse);
          expect(
            denied.denialResult?.errorMessage,
            'Auto-review denied: The action is unsafe.',
          );
          expect(cached.denialResult, same(denied.denialResult));
          expect(harness.manual.requests, isEmpty);
          expect(harness.audit.records.single.outcome, 'denied');
          expect(
            harness.coordinator.domainEscalatesDeniedActionToManual(
              configuration.domain,
            ),
            configuration.domain == ToolApprovalAutoReviewDomain.coding,
          );
        }
      },
    );
  });

  group('owner lifecycle', () {
    test('rejects an initially stale owner and audits expiration', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');

      final outcome = await harness.coordinator.resolve(_request(owner: owner));

      expect(outcome.isApproved, isFalse);
      expect(outcome.gateDecision, isNull);
      expect(
        outcome.denialResult?.errorMessage,
        'The approval turn expired before execution',
      );
      expect(harness.manual.requests, isEmpty);
      expect(harness.autoReview.requests, isEmpty);
      expect(harness.audit.records.single.decisionSource, 'owner_expired');
    });

    test('revalidates full-access ownership after its audit', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      harness.audit.onRecord = harness.owners.currentOwners.remove;

      final outcome = await harness.coordinator.resolve(
        _request(
          owner: owner,
          mode: ToolApprovalMode.fullAccess,
          fullAccessEligible: true,
        ),
      );

      expect(outcome.isApproved, isFalse);
      expect(outcome.denialResult?.toolName, 'write_file');
      expect(outcome.denialResult?.result, '');
      expect(outcome.denialResult?.isSuccess, isFalse);
      expect(
        outcome.denialResult?.errorMessage,
        'The approval turn expired before execution',
      );
      expect(harness.audit.records.map((record) => record.decisionSource), [
        'full_access',
        'owner_expired',
      ]);
      expect(harness.manual.requests, isEmpty);
      expect(harness.autoReview.requests, isEmpty);
    });

    test('revalidates cached approval ownership after its audit', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      final request = _request(owner: owner);
      await harness.coordinator.resolve(request);
      harness.coordinator.rememberApprovalResult(request, _result());
      harness.audit.onRecord = harness.owners.currentOwners.remove;

      final outcome = await harness.coordinator.resolve(request);

      expect(outcome.isApproved, isFalse);
      expect(outcome.reusedCachedApproval, isFalse);
      expect(
        outcome.denialResult?.errorMessage,
        'The approval turn expired before execution',
      );
      expect(harness.audit.records.map((record) => record.decisionSource), [
        'cached_approval',
        'owner_expired',
      ]);
      expect(harness.manual.requests, hasLength(1));
      expect(harness.autoReview.requests, isEmpty);
    });

    test('rejects owner expiration during auto-review', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      harness.owners.currentOwners.add(owner);
      harness.autoReview.decision = _reviewDecision(
        outcome: ToolApprovalAutoReviewOutcome.allow,
      );
      harness.autoReview.onReview = harness.owners.currentOwners.remove;

      final outcome = await harness.coordinator.resolve(
        _request(owner: owner, mode: ToolApprovalMode.autoReview),
      );

      expect(outcome.isApproved, isFalse);
      expect(
        outcome.denialResult?.errorMessage,
        'The approval turn expired before execution',
      );
      expect(harness.audit.records.map((record) => record.decisionSource), [
        'auto_review',
        'owner_expired',
      ]);
    });

    test(
      'rejects owner expiration during manual approval without caching',
      () async {
        final harness = _Harness();
        final owner = _owner('thread-a');
        harness.owners.currentOwners.add(owner);
        harness.manual.onRequest = harness.owners.currentOwners.remove;

        final outcome = await harness.coordinator.resolve(
          _request(owner: owner),
        );
        harness.owners.currentOwners.add(owner);
        harness.manual.onRequest = null;
        await harness.coordinator.resolve(_request(owner: owner));

        expect(outcome.isApproved, isFalse);
        expect(harness.manual.requests, hasLength(2));
      },
    );

    test(
      'rejects a manual completion after explicit owner retirement',
      () async {
        final harness = _Harness();
        final owner = _owner('thread-a');
        harness.owners.currentOwners.add(owner);
        harness.manual.onRequest = harness.coordinator.clearOwner;

        final outcome = await harness.coordinator.resolve(
          _request(owner: owner),
        );
        final replay = await harness.coordinator.resolve(
          _request(owner: owner),
        );

        expect(outcome.isApproved, isFalse);
        expect(
          outcome.denialResult?.errorMessage,
          'The approval turn expired before execution',
        );
        expect(replay.isApproved, isFalse);
        expect(harness.manual.requests, hasLength(1));
      },
    );

    test('clearOwner and clearAll retire only their exact owners', () async {
      final harness = _Harness();
      final ownerA = _owner('thread-a');
      final ownerB = _owner('thread-b');
      harness.owners.currentOwners.addAll([ownerA, ownerB]);
      final requestA = _request(owner: ownerA);
      final requestB = _request(owner: ownerB);
      await harness.coordinator.resolve(requestA);
      await harness.coordinator.resolve(requestB);
      harness.coordinator.rememberApprovalResult(requestA, _result());
      harness.coordinator.rememberApprovalResult(requestB, _result());

      expect(harness.coordinator.clearOwner(ownerA), isTrue);
      expect(harness.coordinator.clearOwner(ownerA), isFalse);
      final retiredA = await harness.coordinator.resolve(requestA);
      final activeB = await harness.coordinator.resolve(requestB);
      harness.coordinator.clearAll();
      final retiredB = await harness.coordinator.resolve(requestB);

      expect(retiredA.isApproved, isFalse);
      expect(activeB.gateDecision, ToolApprovalGateDecision.cachedApproval);
      expect(retiredB.isApproved, isFalse);
    });

    test('does not remember late approval or denial decisions', () async {
      final harness = _Harness();
      final owner = _owner('thread-a');
      final request = _request(owner: owner);
      final denial = _result(isSuccess: false, errorMessage: 'Denied');

      expect(
        harness.coordinator.rememberApprovalResult(request, _result()),
        isA<McpToolResult>(),
      );
      expect(harness.coordinator.rememberDenial(request, denial), same(denial));
      harness.owners.currentOwners.add(owner);
      await harness.coordinator.resolve(request);

      expect(harness.manual.requests, hasLength(1));
    });
  });
}
