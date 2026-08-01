import '../../domain/services/lsp_go_to_definition_tool_contract.dart';
import 'lsp_json_rpc_session_registry.dart';

export '../../domain/services/lsp_go_to_definition_tool_handler.dart';
export 'lsp_json_rpc_session_registry.dart';

enum LspDefinitionSessionAcquisitionKind { unavailable, ready }

final class _DirectLspDefinitionCollection {
  const _DirectLspDefinitionCollection(this.definitions);

  final List<LspDefinitionLocation>? definitions;
}

final class LspDefinitionSessionAcquisition {
  const LspDefinitionSessionAcquisition.unavailable({
    required this.identity,
    this.sessionEffect = LspDefinitionSessionEffect.none,
  }) : kind = LspDefinitionSessionAcquisitionKind.unavailable,
       sessionToken = null,
       languageId = null;

  const LspDefinitionSessionAcquisition.ready({
    required this.identity,
    required this.sessionToken,
    required this.languageId,
    required this.sessionEffect,
  }) : kind = LspDefinitionSessionAcquisitionKind.ready;

  final LspDefinitionOperationIdentity identity;
  final LspDefinitionSessionAcquisitionKind kind;
  final Object? sessionToken;
  final String? languageId;
  final LspDefinitionSessionEffect sessionEffect;
}

final class LspDefinitionCollection {
  LspDefinitionCollection({
    required this.identity,
    required List<LspDefinitionLocation>? definitions,
  }) : definitions = definitions == null
           ? null
           : List<LspDefinitionLocation>.unmodifiable(definitions);

  final LspDefinitionOperationIdentity identity;
  final List<LspDefinitionLocation>? definitions;
}

enum LspDefinitionCleanupDisposition { compensated, sessionMismatch }

final class LspDefinitionCleanupAcknowledgement {
  const LspDefinitionCleanupAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final LspDefinitionOperationIdentity identity;
  final LspDefinitionCleanupDisposition disposition;
}

typedef LspDefinitionSessionAcquirer =
    Future<LspDefinitionSessionAcquisition> Function(
      LspDefinitionLookupRequest request,
    );
typedef LspDefinitionCollector =
    Future<LspDefinitionCollection> Function(
      LspDefinitionLookupRequest request,
      LspDefinitionSessionAcquisition acquisition,
    );
typedef LspDefinitionSessionCleaner =
    Future<LspDefinitionCleanupAcknowledgement> Function(
      LspDefinitionOperationIdentity identity,
      LspDefinitionSessionAcquisition acquisition,
    );

final class LspGoToDefinitionRuntimeAdapter implements LspDefinitionPort {
  const LspGoToDefinitionRuntimeAdapter({
    required LspDefinitionLifecyclePort lifecyclePort,
    required LspDefinitionSessionAcquirer acquireSession,
    required LspDefinitionCollector collectDefinitions,
    required LspDefinitionSessionCleaner cleanupSession,
  }) : _lifecyclePort = lifecyclePort,
       _acquireSession = acquireSession,
       _collectDefinitions = collectDefinitions,
       _cleanupSession = cleanupSession;

  factory LspGoToDefinitionRuntimeAdapter.fromRegistry({
    required LspJsonRpcSessionRegistry registry,
    required LspDefinitionLifecyclePort lifecyclePort,
  }) {
    return LspGoToDefinitionRuntimeAdapter(
      lifecyclePort: lifecyclePort,
      acquireSession: (request) async {
        if (registry.usesDirectDefinitionLookup) {
          final definitions = await registry.collectDefinitions(
            projectRoot: request.projectRoot,
            path: request.path,
            line: request.line,
            character: request.character,
          );
          return LspDefinitionSessionAcquisition.ready(
            identity: request.identity,
            sessionToken: _DirectLspDefinitionCollection(definitions),
            languageId: 'direct',
            sessionEffect: LspDefinitionSessionEffect.reused,
          );
        }
        final result = await registry.ensureSession(
          projectRoot: request.projectRoot,
          changedPaths: [request.path],
        );
        final session = result.session;
        if (!result.ok) {
          return session == null
              ? LspDefinitionSessionAcquisition.unavailable(
                  identity: request.identity,
                )
              : LspDefinitionSessionAcquisition.unavailable(
                  identity: request.identity,
                  sessionEffect: LspDefinitionSessionEffect.uncertain,
                );
        }
        if (session == null) {
          return LspDefinitionSessionAcquisition.unavailable(
            identity: request.identity,
            sessionEffect: LspDefinitionSessionEffect.uncertain,
          );
        }
        final effect = result.reused
            ? LspDefinitionSessionEffect.reused
            : LspDefinitionSessionEffect.started;
        if (session.isClosed) {
          return LspDefinitionSessionAcquisition.unavailable(
            identity: request.identity,
            sessionEffect: result.reused
                ? LspDefinitionSessionEffect.reused
                : LspDefinitionSessionEffect.compensated,
          );
        }
        return LspDefinitionSessionAcquisition.ready(
          identity: request.identity,
          sessionToken: session,
          languageId: result.languageId ?? session.command.languageId,
          sessionEffect: effect,
        );
      },
      collectDefinitions: (request, acquisition) async {
        final session = acquisition.sessionToken;
        if (session is _DirectLspDefinitionCollection) {
          return LspDefinitionCollection(
            identity: request.identity,
            definitions: session.definitions,
          );
        }
        if (session is! LspJsonRpcSession) {
          throw StateError('LSP session token mismatch.');
        }
        final definitions = await session.collectDefinitions(
          path: request.path,
          line: request.line,
          character: request.character,
          timeout: registry.definitionRequestTimeout,
        );
        return LspDefinitionCollection(
          identity: request.identity,
          definitions: definitions,
        );
      },
      cleanupSession: (identity, acquisition) async {
        final session = acquisition.sessionToken;
        final languageId = acquisition.languageId;
        if (session is! LspJsonRpcSession || languageId == null) {
          return LspDefinitionCleanupAcknowledgement(
            identity: identity,
            disposition: LspDefinitionCleanupDisposition.sessionMismatch,
          );
        }
        final closed = await registry.closeSessionIfMatches(
          projectRoot: session.projectRoot,
          languageId: languageId,
          expectedSession: session,
        );
        return LspDefinitionCleanupAcknowledgement(
          identity: identity,
          disposition: closed
              ? LspDefinitionCleanupDisposition.compensated
              : LspDefinitionCleanupDisposition.sessionMismatch,
        );
      },
    );
  }

  final LspDefinitionLifecyclePort _lifecyclePort;
  final LspDefinitionSessionAcquirer _acquireSession;
  final LspDefinitionCollector _collectDefinitions;
  final LspDefinitionSessionCleaner _cleanupSession;

  @override
  Future<LspDefinitionLookupResult> goToDefinition(
    LspDefinitionLookupRequest request,
  ) async {
    if (!_ownerCurrent(request.identity)) {
      return _expired(request.identity, LspDefinitionSessionEffect.none);
    }

    late final LspDefinitionSessionAcquisition acquisition;
    try {
      acquisition = await _acquireSession(request);
    } catch (_) {
      return LspDefinitionLookupResult.effectUncertain(
        identity: request.identity,
      );
    }
    if (acquisition.identity != request.identity ||
        acquisition.sessionEffect == LspDefinitionSessionEffect.uncertain) {
      return LspDefinitionLookupResult.effectUncertain(
        identity: request.identity,
      );
    }
    if (!_ownerCurrent(request.identity)) {
      return _settleExpired(request.identity, acquisition);
    }
    if (acquisition.kind == LspDefinitionSessionAcquisitionKind.unavailable) {
      return LspDefinitionLookupResult.completed(
        identity: request.identity,
        definitions: null,
        sessionEffect: acquisition.sessionEffect,
      );
    }

    late final LspDefinitionCollection collection;
    try {
      collection = await _collectDefinitions(request, acquisition);
    } catch (error) {
      if (!_ownerCurrent(request.identity)) {
        return _settleExpired(request.identity, acquisition);
      }
      return LspDefinitionLookupResult.failed(
        identity: request.identity,
        error: error,
        sessionEffect: acquisition.sessionEffect,
      );
    }
    if (collection.identity != request.identity) {
      return LspDefinitionLookupResult.effectUncertain(
        identity: request.identity,
      );
    }
    if (!_ownerCurrent(request.identity)) {
      return _settleExpired(request.identity, acquisition);
    }
    return LspDefinitionLookupResult.completed(
      identity: request.identity,
      definitions: collection.definitions,
      sessionEffect: acquisition.sessionEffect,
    );
  }

  bool _ownerCurrent(LspDefinitionOperationIdentity identity) {
    try {
      final acknowledgement = _lifecyclePort.acknowledgeOwner(identity);
      return acknowledgement.identity == identity &&
          acknowledgement.disposition ==
              LspDefinitionOwnerAcknowledgementDisposition.current;
    } catch (_) {
      return false;
    }
  }

  Future<LspDefinitionLookupResult> _settleExpired(
    LspDefinitionOperationIdentity identity,
    LspDefinitionSessionAcquisition acquisition,
  ) async {
    if (acquisition.sessionEffect != LspDefinitionSessionEffect.started) {
      return _expired(identity, acquisition.sessionEffect);
    }
    try {
      final cleanup = await _cleanupSession(identity, acquisition);
      if (cleanup.identity == identity &&
          cleanup.disposition == LspDefinitionCleanupDisposition.compensated) {
        return _expired(identity, LspDefinitionSessionEffect.compensated);
      }
    } catch (_) {}
    return LspDefinitionLookupResult.effectUncertain(identity: identity);
  }

  LspDefinitionLookupResult _expired(
    LspDefinitionOperationIdentity identity,
    LspDefinitionSessionEffect effect,
  ) {
    return LspDefinitionLookupResult.ownerExpired(
      identity: identity,
      sessionEffect: effect,
    );
  }
}
