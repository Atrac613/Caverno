import 'package:caverno/features/chat/data/datasources/lsp_go_to_definition_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:test/test.dart';

final class _Lifecycle implements LspDefinitionLifecyclePort {
  bool current = true;
  LspDefinitionOperationIdentity? identityOverride;

  @override
  LspDefinitionOwnerAcknowledgement acknowledgeOwner(
    LspDefinitionOperationIdentity identity,
  ) {
    final acknowledged = identityOverride ?? identity;
    return current
        ? LspDefinitionOwnerAcknowledgement.current(identity: acknowledged)
        : LspDefinitionOwnerAcknowledgement.ownerExpired(
            identity: acknowledged,
          );
  }
}

final class _DirectDefinitionRegistry extends LspJsonRpcSessionRegistry {
  LspDefinitionLookupRequest? received;

  @override
  bool get usesDirectDefinitionLookup => true;

  @override
  Future<List<LspDefinitionLocation>?> collectDefinitions({
    required String projectRoot,
    required String path,
    required int line,
    required int character,
  }) async {
    received = LspDefinitionLookupRequest(
      identity: LspDefinitionOperationIdentity(
        owner: ChatTurnOwner(
          conversationId: 'direct-registry',
          interactionGeneration: 1,
        ),
        toolCallId: 'direct-call',
        toolName: canonicalLspGoToDefinitionToolName,
        requestDigest: 'direct-digest',
      ),
      projectRoot: projectRoot,
      path: path,
      line: line,
      character: character,
    );
    return const [
      LspDefinitionLocation(
        uri: 'file:///workspace/lib/target.dart',
        startLine: 2,
        startCharacter: 3,
      ),
    ];
  }
}

LspDefinitionLookupRequest _request(
  ChatTurnOwner owner, {
  String callId = 'call-a',
  String path = '/workspace/lib/main.dart',
}) {
  return LspDefinitionLookupRequest(
    identity: LspDefinitionOperationIdentity(
      owner: owner,
      toolCallId: callId,
      toolName: canonicalLspGoToDefinitionToolName,
      requestDigest: 'digest:$path',
    ),
    projectRoot: '/workspace',
    path: path,
    line: 0,
    character: 0,
  );
}

LspDefinitionSessionAcquisition _ready(
  LspDefinitionLookupRequest request,
  LspDefinitionSessionEffect effect, [
  LspDefinitionOperationIdentity? identity,
]) {
  return LspDefinitionSessionAcquisition.ready(
    identity: identity ?? request.identity,
    sessionToken: Object(),
    languageId: 'dart',
    sessionEffect: effect,
  );
}

LspDefinitionSessionAcquirer _expireOnAcquire(
  _Lifecycle lifecycle,
  LspDefinitionSessionEffect effect,
) {
  return (request) async {
    lifecycle.current = false;
    return _ready(request, effect);
  };
}

LspGoToDefinitionRuntimeAdapter _adapter({
  required _Lifecycle lifecycle,
  required LspDefinitionSessionAcquirer acquire,
  LspDefinitionCollector? collect,
  LspDefinitionSessionCleaner? cleanup,
}) {
  return LspGoToDefinitionRuntimeAdapter(
    lifecyclePort: lifecycle,
    acquireSession: acquire,
    collectDefinitions:
        collect ??
        (request, acquisition) async => LspDefinitionCollection(
          identity: request.identity,
          definitions: const [],
        ),
    cleanupSession:
        cleanup ??
        (identity, acquisition) async => LspDefinitionCleanupAcknowledgement(
          identity: identity,
          disposition: LspDefinitionCleanupDisposition.compensated,
        ),
  );
}

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );
  final otherOwner = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 4,
  );

  test(
    'production registry factory reports unavailable without launch',
    () async {
      final request = _request(owner, path: '/workspace/missing.unknown');
      final adapter = LspGoToDefinitionRuntimeAdapter.fromRegistry(
        registry: LspJsonRpcSessionRegistry(),
        lifecyclePort: _Lifecycle(),
      );

      final result = await adapter.goToDefinition(request);

      expect(result.identity, request.identity);
      expect(result.kind, LspDefinitionLookupResultKind.completed);
      expect(result.definitions, isNull);
      expect(result.sessionEffect, LspDefinitionSessionEffect.none);
    },
  );

  test(
    'registry factory supports an explicit direct lookup capability',
    () async {
      final registry = _DirectDefinitionRegistry();
      final request = _request(owner);
      final adapter = LspGoToDefinitionRuntimeAdapter.fromRegistry(
        registry: registry,
        lifecyclePort: _Lifecycle(),
      );

      final result = await adapter.goToDefinition(request);

      expect(result.kind, LspDefinitionLookupResultKind.completed);
      expect(result.sessionEffect, LspDefinitionSessionEffect.reused);
      expect(result.definitions, hasLength(1));
      expect(result.definitions!.single.startLine, 2);
      expect(registry.received?.projectRoot, request.projectRoot);
      expect(registry.received?.path, request.path);
      expect(registry.received?.line, request.line);
      expect(registry.received?.character, request.character);
    },
  );

  test('fences cross-owner and same-owner async poison', () async {
    final request = _request(owner);
    final poisoned = [
      _request(otherOwner).identity,
      _request(owner, callId: 'call-b').identity,
    ];
    for (final identity in poisoned) {
      final acquisitionResult = await _adapter(
        lifecycle: _Lifecycle(),
        acquire: (_) async =>
            _ready(request, LspDefinitionSessionEffect.started, identity),
      ).goToDefinition(request);
      expect(
        acquisitionResult.kind,
        LspDefinitionLookupResultKind.effectUncertain,
      );
    }
  });

  test('conditionally compensates a newly started expired session', () async {
    final lifecycle = _Lifecycle();
    var cleanupCount = 0;
    final result = await _adapter(
      lifecycle: lifecycle,
      acquire: _expireOnAcquire(lifecycle, LspDefinitionSessionEffect.started),
      cleanup: (identity, acquisition) async {
        cleanupCount += 1;
        return LspDefinitionCleanupAcknowledgement(
          identity: identity,
          disposition: LspDefinitionCleanupDisposition.compensated,
        );
      },
    ).goToDefinition(_request(owner));

    expect(result.kind, LspDefinitionLookupResultKind.ownerExpired);
    expect(result.sessionEffect, LspDefinitionSessionEffect.compensated);
    expect(cleanupCount, 1);
  });

  test(
    'does not trust a poisoned conditional cleanup acknowledgement',
    () async {
      final lifecycle = _Lifecycle();
      final result = await _adapter(
        lifecycle: lifecycle,
        acquire: _expireOnAcquire(
          lifecycle,
          LspDefinitionSessionEffect.started,
        ),
        cleanup: (_, _) async => LspDefinitionCleanupAcknowledgement(
          identity: _request(owner, callId: 'call-b').identity,
          disposition: LspDefinitionCleanupDisposition.compensated,
        ),
      ).goToDefinition(_request(owner));

      expect(result.kind, LspDefinitionLookupResultKind.effectUncertain);
    },
  );

  test('expiry of a reused session does not clean shared state', () async {
    final lifecycle = _Lifecycle();
    var cleanupCount = 0;
    final result = await _adapter(
      lifecycle: lifecycle,
      acquire: _expireOnAcquire(lifecycle, LspDefinitionSessionEffect.reused),
      cleanup: (identity, acquisition) async {
        cleanupCount += 1;
        throw StateError('must not clean a reused session');
      },
    ).goToDefinition(_request(owner));

    expect(result.kind, LspDefinitionLookupResultKind.ownerExpired);
    expect(result.sessionEffect, LspDefinitionSessionEffect.reused);
    expect(cleanupCount, 0);
  });

  test('classifies acquisition uncertainty and collection failure', () async {
    final request = _request(owner);
    final uncertain = await _adapter(
      lifecycle: _Lifecycle(),
      acquire: (_) async => throw StateError('launch handoff lost'),
    ).goToDefinition(request);
    expect(uncertain.kind, LspDefinitionLookupResultKind.effectUncertain);

    final failed = await _adapter(
      lifecycle: _Lifecycle(),
      acquire: (request) async =>
          _ready(request, LspDefinitionSessionEffect.started),
      collect: (_, _) async => throw StateError('request failed'),
    ).goToDefinition(request);
    expect(failed.kind, LspDefinitionLookupResultKind.failed);
    expect(failed.errorMessage, 'Bad state: request failed');
    expect(failed.sessionEffect, LspDefinitionSessionEffect.started);
  });
}
