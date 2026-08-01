import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/save_skill_tool_handler.dart';
import 'save_skill_runtime_contract.dart';
import 'save_skill_runtime_result_support.dart';

export 'save_skill_runtime_contract.dart';

part 'save_skill_runtime_success_recovery.dart';

final class SaveSkillToolRuntimeAdapter {
  const SaveSkillToolRuntimeAdapter({
    required SaveSkillSnapshotCallback captureSnapshot,
    required SaveSkillFreshManualApprovalCallback requestFreshManualApproval,
    required SaveSkillOwnerCallback acknowledgeOwner,
    required SaveSkillWriteCallback write,
    required SaveSkillCompensationCallback compensate,
    required SaveSkillSuccessCallback recordSuccess,
    required SaveSkillSuccessReconciliationCallback reconcileSuccess,
  }) : _captureSnapshot = captureSnapshot,
       _requestFreshManualApproval = requestFreshManualApproval,
       _acknowledgeOwner = acknowledgeOwner,
       _write = write,
       _compensate = compensate,
       _recordSuccess = recordSuccess,
       _reconcileSuccess = reconcileSuccess;

  final SaveSkillSnapshotCallback _captureSnapshot;
  final SaveSkillFreshManualApprovalCallback _requestFreshManualApproval;
  final SaveSkillOwnerCallback _acknowledgeOwner;
  final SaveSkillWriteCallback _write;
  final SaveSkillCompensationCallback _compensate;
  final SaveSkillSuccessCallback _recordSuccess;
  final SaveSkillSuccessReconciliationCallback _reconcileSuccess;
  Future<SaveSkillRuntimeCompletion> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) async {
    final input = SaveSkillRuntimeInput(owner: owner, toolCall: toolCall);
    final bridge = _SaveSkillRuntimeBridge(
      input: input,
      captureSnapshot: _captureSnapshot,
      requestFreshManualApproval: _requestFreshManualApproval,
      acknowledgeOwner: _acknowledgeOwner,
      write: _write,
      compensate: _compensate,
      recordSuccess: _recordSuccess,
      reconcileSuccess: _reconcileSuccess,
    );
    final handler = SaveSkillToolHandler(
      storePort: bridge,
      approvalPort: bridge,
    );
    McpToolResult result;
    try {
      result = await handler.handle(input.toToolRequest());
    } catch (error) {
      result = bridge.failureFor(error);
    }
    return SaveSkillRuntimeCompletion(
      identity: input.identity,
      disposition: bridge.classify(result),
      result: result,
    );
  }
}

final class _SaveSkillRuntimeBridge
    implements SkillStorePort, SkillSaveApprovalPort {
  _SaveSkillRuntimeBridge({
    required this.input,
    required SaveSkillSnapshotCallback captureSnapshot,
    required SaveSkillFreshManualApprovalCallback requestFreshManualApproval,
    required SaveSkillOwnerCallback acknowledgeOwner,
    required SaveSkillWriteCallback write,
    required SaveSkillCompensationCallback compensate,
    required SaveSkillSuccessCallback recordSuccess,
    required SaveSkillSuccessReconciliationCallback reconcileSuccess,
  }) : _captureSnapshot = captureSnapshot,
       _requestFreshManualApproval = requestFreshManualApproval,
       _acknowledgeOwner = acknowledgeOwner,
       _write = write,
       _compensate = compensate,
       _recordSuccess = recordSuccess,
       _reconcileSuccess = reconcileSuccess;

  final SaveSkillRuntimeInput input;
  final SaveSkillSnapshotCallback _captureSnapshot;
  final SaveSkillFreshManualApprovalCallback _requestFreshManualApproval;
  final SaveSkillOwnerCallback _acknowledgeOwner;
  final SaveSkillWriteCallback _write;
  final SaveSkillCompensationCallback _compensate;
  final SaveSkillSuccessCallback _recordSuccess;
  final SaveSkillSuccessReconciliationCallback _reconcileSuccess;
  SaveSkillRuntimeDisposition? _observedDisposition;
  SaveSkillCatalogIdentity? _catalogIdentity;
  SaveSkillWriteAcknowledgement? _committedWrite;
  bool _approvalRequested = false, _approvalGranted = false;
  bool _writeDispatched = false;
  @override
  SkillStoreSnapshot snapshot(SaveSkillOperationIdentity identity) {
    _requireOperation(identity);
    if (_catalogIdentity != null) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      throw StateError('The skill catalog snapshot was requested twice.');
    }
    final acknowledgement = _snapshotAcknowledgement();
    if (acknowledgement.identity != input.identity) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      throw StateError('Skill catalog snapshot identity mismatch.');
    }
    if (acknowledgement.disposition != SaveSkillSnapshotDisposition.captured) {
      _observe(
        acknowledgement.disposition == SaveSkillSnapshotDisposition.rejected
            ? SaveSkillRuntimeDisposition.rejected
            : SaveSkillRuntimeDisposition.effectUncertain,
      );
      throw StateError('The skill catalog snapshot is unavailable.');
    }
    final skills = acknowledgement.skills!;
    _catalogIdentity = SaveSkillCatalogIdentity(
      runtime: input.identity,
      catalogDigest: saveSkillCatalogDigest(skills),
    );
    return SkillStoreSnapshot(identity: identity, skills: skills);
  }

  @override
  Future<SkillSaveApprovalDecision> requestApproval(
    SkillSaveApprovalRequest request,
  ) async {
    _requireOperation(request.toolRequest.identity);
    final catalog = _requireCatalog();
    if (_approvalRequested) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      return SkillSaveApprovalDecision(
        identity: request.toolRequest.identity,
        approved: false,
      );
    }
    _approvalRequested = true;
    final SaveSkillApprovalAcknowledgement acknowledgement;
    try {
      acknowledgement = await _requestFreshManualApproval(
        SaveSkillRuntimeApprovalRequest(identity: catalog, request: request),
      );
    } catch (_) {
      _observe(SaveSkillRuntimeDisposition.rejected);
      return SkillSaveApprovalDecision(
        identity: request.toolRequest.identity,
        approved: false,
      );
    }
    if (acknowledgement.identity != catalog) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      return SkillSaveApprovalDecision(
        identity: request.toolRequest.identity,
        approved: false,
      );
    }
    _approvalGranted =
        acknowledgement.disposition == SaveSkillApprovalDisposition.approved;
    _observeApproval(acknowledgement.disposition);
    return SkillSaveApprovalDecision(
      identity: request.toolRequest.identity,
      approved: _approvalGranted,
    );
  }

  @override
  SkillSaveAcknowledgement acknowledgeOwner(
    SaveSkillOperationIdentity identity,
  ) {
    _requireOperation(identity);
    final disposition = _ownerDisposition();
    return switch (disposition) {
      SaveSkillOwnerDisposition.current =>
        SkillSaveAcknowledgement.acknowledged(identity: identity),
      SaveSkillOwnerDisposition.ownerExpired =>
        SkillSaveAcknowledgement.ownerExpired(identity: identity),
      SaveSkillOwnerDisposition.effectUncertain =>
        SkillSaveAcknowledgement.effectUncertain(identity: identity),
    };
  }

  @override
  Future<SkillStoreWriteResult> upsertMarkdown(
    SaveSkillOperationIdentity identity,
    SkillStoreWriteRequest request,
  ) async {
    _requireOperation(identity);
    final catalog = _requireCatalog();
    if (!_approvalRequested || !_approvalGranted) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      return SkillStoreWriteResult.effectUncertain(identity: identity);
    }
    if (_ownerDisposition() != SaveSkillOwnerDisposition.current ||
        !_catalogIsCurrent(catalog)) {
      return SkillStoreWriteResult.ownerExpired(
        identity: identity,
        expiredWriteDisposition: SkillStoreExpiredWriteDisposition.notCommitted,
      );
    }

    final writeRequest = SaveSkillRuntimeWriteRequest(
      catalog: catalog,
      request: request,
    );
    final SaveSkillWriteAcknowledgement acknowledgement;
    _writeDispatched = true;
    try {
      acknowledgement = await _write(writeRequest);
    } catch (_) {
      _observe(SaveSkillRuntimeDisposition.effectUncertain);
      return SkillStoreWriteResult.effectUncertain(identity: identity);
    }
    if (acknowledgement.identity != writeRequest.identity) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      return SkillStoreWriteResult.effectUncertain(identity: identity);
    }
    switch (acknowledgement.disposition) {
      case SaveSkillWriteDisposition.rejectedBeforeEffect:
        return SkillStoreWriteResult.rejected(
          identity: identity,
          errorMessage: acknowledgement.errorMessage!,
        );
      case SaveSkillWriteDisposition.ownerExpiredBeforeEffect:
        _observe(SaveSkillRuntimeDisposition.ownerExpired);
        return SkillStoreWriteResult.ownerExpired(
          identity: identity,
          expiredWriteDisposition:
              SkillStoreExpiredWriteDisposition.notCommitted,
        );
      case SaveSkillWriteDisposition.ownerExpiredAfterEffect:
        return _compensateWrite(
          identity,
          acknowledgement.identity,
          acknowledgement.compensationToken!,
        );
      case SaveSkillWriteDisposition.effectUncertainAfterEffect:
        return _compensateWrite(
          identity,
          acknowledgement.identity,
          acknowledgement.compensationToken!,
          reconciledError: acknowledgement.errorMessage!,
        );
      case SaveSkillWriteDisposition.committed:
        break;
    }

    _committedWrite = acknowledgement;
    if (_ownerDisposition() != SaveSkillOwnerDisposition.current) {
      return _compensateWrite(
        identity,
        acknowledgement.identity,
        acknowledgement.compensationToken!,
      );
    }
    return SkillStoreWriteResult.committed(
      identity: identity,
      skill: acknowledgement.skill!,
    );
  }

  @override
  Future<SkillSaveAcknowledgement> recordSuccessfulSave(
    SaveSkillOperationIdentity identity,
  ) async {
    _requireOperation(identity);
    final catalog = _requireCatalog();
    final write = _committedWrite;
    if (write == null || write.identity.catalog != catalog) {
      _observe(SaveSkillRuntimeDisposition.effectUncertain);
      return SkillSaveAcknowledgement.effectUncertain(identity: identity);
    }
    if (_ownerDisposition() != SaveSkillOwnerDisposition.current) {
      final compensated = await _compensateWrite(
        identity,
        write.identity,
        write.compensationToken!,
      );
      return compensated.disposition ==
                  SkillStoreWriteDisposition.ownerExpired &&
              compensated.expiredWriteDisposition ==
                  SkillStoreExpiredWriteDisposition.compensated
          ? SkillSaveAcknowledgement.ownerExpired(identity: identity)
          : SkillSaveAcknowledgement.effectUncertain(identity: identity);
    }
    final successIdentity = SaveSkillSuccessIdentity(
      mutation: write.identity,
      compensationToken: write.compensationToken!,
      savedSkillDigest: saveSkillDigest(write.skill!),
    );
    final SaveSkillSuccessAcknowledgement acknowledgement;
    try {
      acknowledgement = await _recordSuccess(successIdentity);
    } catch (_) {
      return _uncertainSuccess(identity, write);
    }
    if (acknowledgement.identity != successIdentity) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      return _uncertainSuccess(identity, write);
    }
    if (acknowledgement.disposition ==
        SaveSkillSuccessDisposition.acknowledged) {
      return SkillSaveAcknowledgement.acknowledged(identity: identity);
    }
    if (acknowledgement.disposition ==
        SaveSkillSuccessDisposition.ownerExpired) {
      final compensated = await _compensateWrite(
        identity,
        write.identity,
        write.compensationToken!,
      );
      return compensated.disposition ==
                  SkillStoreWriteDisposition.ownerExpired &&
              compensated.expiredWriteDisposition ==
                  SkillStoreExpiredWriteDisposition.compensated
          ? SkillSaveAcknowledgement.ownerExpired(identity: identity)
          : SkillSaveAcknowledgement.effectUncertain(identity: identity);
    }
    return _uncertainSuccess(identity, write);
  }

  Future<SkillStoreWriteResult> _compensateWrite(
    SaveSkillOperationIdentity identity,
    SaveSkillMutationIdentity mutation,
    String token, {
    String? reconciledError,
  }) async {
    if (reconciledError == null) {
      _observe(SaveSkillRuntimeDisposition.ownerExpired);
    }
    final SaveSkillCompensationAcknowledgement acknowledgement;
    try {
      acknowledgement = await _compensate(
        SaveSkillCompensationRequest(
          identity: mutation,
          compensationToken: token,
        ),
      );
    } catch (_) {
      _observe(SaveSkillRuntimeDisposition.effectUncertain);
      return SkillStoreWriteResult.effectUncertain(identity: identity);
    }
    if (acknowledgement.identity != mutation ||
        acknowledgement.compensationToken != token) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      return SkillStoreWriteResult.effectUncertain(identity: identity);
    }
    return switch (acknowledgement.disposition) {
      SaveSkillCompensationDisposition.compensated ||
      SaveSkillCompensationDisposition.alreadyAbsent =>
        reconciledError == null
            ? SkillStoreWriteResult.ownerExpired(
                identity: identity,
                expiredWriteDisposition:
                    SkillStoreExpiredWriteDisposition.compensated,
              )
            : SkillStoreWriteResult.rejected(
                identity: identity,
                errorMessage: reconciledError,
              ),
      SaveSkillCompensationDisposition.retained => _retainedWrite(identity),
      SaveSkillCompensationDisposition.effectUncertain => _uncertainWrite(
        identity,
      ),
    };
  }

  SaveSkillSnapshotAcknowledgement _snapshotAcknowledgement() {
    try {
      return _captureSnapshot(input.identity);
    } catch (_) {
      _observe(SaveSkillRuntimeDisposition.rejected);
      return SaveSkillSnapshotAcknowledgement.rejected(
        identity: input.identity,
      );
    }
  }

  bool _catalogIsCurrent(SaveSkillCatalogIdentity expected) {
    final acknowledgement = _snapshotAcknowledgement();
    if (acknowledgement.identity != input.identity) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      return false;
    }
    if (acknowledgement.disposition != SaveSkillSnapshotDisposition.captured) {
      _observe(SaveSkillRuntimeDisposition.rejected);
      return false;
    }
    final actual = SaveSkillCatalogIdentity(
      runtime: input.identity,
      catalogDigest: saveSkillCatalogDigest(acknowledgement.skills!),
    );
    if (actual != expected) {
      _observe(SaveSkillRuntimeDisposition.rejected);
      return false;
    }
    return true;
  }

  SaveSkillOwnerDisposition _ownerDisposition() {
    final SaveSkillOwnerAcknowledgement acknowledgement;
    try {
      acknowledgement = _acknowledgeOwner(input.identity);
    } catch (_) {
      _observe(SaveSkillRuntimeDisposition.effectUncertain);
      return SaveSkillOwnerDisposition.effectUncertain;
    }
    if (acknowledgement.identity != input.identity) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      return SaveSkillOwnerDisposition.effectUncertain;
    }
    switch (acknowledgement.disposition) {
      case SaveSkillOwnerDisposition.current:
        break;
      case SaveSkillOwnerDisposition.ownerExpired:
        _observe(SaveSkillRuntimeDisposition.ownerExpired);
        break;
      case SaveSkillOwnerDisposition.effectUncertain:
        _observe(SaveSkillRuntimeDisposition.effectUncertain);
        break;
    }
    return acknowledgement.disposition;
  }

  SaveSkillRuntimeDisposition classify(McpToolResult result) =>
      classifySaveSkillRuntimeResult(
        observed: _observedDisposition,
        result: result,
      );

  McpToolResult failureFor(Object error) => saveSkillRuntimeBoundaryFailure(
    writeDispatched: _writeDispatched,
    observed: _observedDisposition,
    error: error,
  );

  SkillStoreWriteResult _uncertainWrite(SaveSkillOperationIdentity identity) {
    _observe(SaveSkillRuntimeDisposition.effectUncertain);
    return SkillStoreWriteResult.effectUncertain(identity: identity);
  }

  SkillStoreWriteResult _retainedWrite(SaveSkillOperationIdentity identity) {
    _observe(SaveSkillRuntimeDisposition.effectUncertain);
    return SkillStoreWriteResult.ownerExpired(
      identity: identity,
      expiredWriteDisposition: SkillStoreExpiredWriteDisposition.retained,
    );
  }

  SaveSkillCatalogIdentity _requireCatalog() {
    final identity = _catalogIdentity;
    if (identity == null) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      throw StateError('The skill catalog snapshot was not captured.');
    }
    return identity;
  }

  void _requireOperation(SaveSkillOperationIdentity identity) {
    if (identity.owner != input.identity.owner ||
        identity.toolCallId != input.identity.toolCallId ||
        identity.toolName != input.identity.toolName) {
      _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      throw StateError('Save skill operation identity mismatch.');
    }
  }

  void _observeApproval(SaveSkillApprovalDisposition disposition) {
    switch (disposition) {
      case SaveSkillApprovalDisposition.approved:
        return;
      case SaveSkillApprovalDisposition.rejected:
        _observe(SaveSkillRuntimeDisposition.rejected);
        return;
      case SaveSkillApprovalDisposition.ownerExpired:
        _observe(SaveSkillRuntimeDisposition.ownerExpired);
        return;
      case SaveSkillApprovalDisposition.effectUncertain:
        _observe(SaveSkillRuntimeDisposition.effectUncertain);
        return;
    }
  }

  void _observe(SaveSkillRuntimeDisposition disposition) {
    if (saveSkillRuntimeDispositionPriority(disposition) >
        saveSkillRuntimeDispositionPriority(_observedDisposition)) {
      _observedDisposition = disposition;
    }
  }
}
