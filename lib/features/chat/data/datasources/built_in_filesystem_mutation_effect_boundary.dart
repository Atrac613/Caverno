import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/file_mutation_tool_handler.dart';
import 'file_mutation_runtime_contract.dart';
import 'file_rollback_checkpoint_store.dart';
import 'filesystem_tools.dart';
import 'first_party_tool_execution_result.dart';

part 'built_in_filesystem_mutation_compensation.dart';

typedef BuiltInFilesystemRawMutationRunner =
    Future<FirstPartyToolExecutionResult> Function({
      required String name,
      required Map<String, dynamic> arguments,
    });

typedef BuiltInFilesystemMutationSnapshotReader =
    Future<TextFileSnapshot> Function(String path);

typedef BuiltInFilesystemMutationSnapshotRestorer =
    Future<String> Function({
      required String path,
      required bool existedBefore,
      String? content,
    });

/// Executes filesystem mutations either through the legacy checkpoint path or
/// through an explicit effect handoff owned by the file mutation runtime.
final class BuiltInFilesystemMutationEffectBoundary {
  BuiltInFilesystemMutationEffectBoundary({
    required BuiltInFilesystemRawMutationRunner operationRunner,
    required BuiltInFilesystemMutationSnapshotReader snapshotReader,
    required FileRollbackCheckpointStore checkpointStore,
    BuiltInFilesystemMutationSnapshotRestorer? snapshotRestorer,
  }) : _operationRunner = operationRunner,
       _snapshotReader = snapshotReader,
       _checkpointStore = checkpointStore,
       _snapshotRestorer =
           snapshotRestorer ?? FilesystemTools.restoreTextSnapshot;

  final BuiltInFilesystemRawMutationRunner _operationRunner;
  final BuiltInFilesystemMutationSnapshotReader _snapshotReader;
  final FileRollbackCheckpointStore _checkpointStore;
  final BuiltInFilesystemMutationSnapshotRestorer _snapshotRestorer;

  /// Preserves the original built-in behavior for callers that do not own an
  /// external mutation effect lease.
  Future<McpToolResult> executeLegacy({
    required ChatTurnOwner? owner,
    required String name,
    required String path,
    required Map<String, dynamic> arguments,
  }) => _checkpointStore.mutationPathFence.runExclusive(path, () async {
    final snapshot = await _snapshotReader(path);
    if (snapshot.error != null) {
      // Refuse either way — nothing restorable means nothing to roll back —
      // but report it at the level the refusal belongs to. An aliased target
      // is a safety rejection and stays an envelope-level failure; anything
      // else is an ordinary filesystem error, which this codebase reports as
      // an envelope-level success carrying the error in its payload. Failing
      // both alike made every legacy filesystem envelope the exception to that
      // contract, and the tool loop counts envelope failures differently.
      final message =
          'A restorable text snapshot is required before file mutation: '
          '${snapshot.error}';
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'ok': false,
          'code': 'file_mutation_snapshot_unavailable',
          'error': message,
          'path': snapshot.path,
        }),
        isSuccess: !snapshot.isPathAlias,
        errorMessage: snapshot.isPathAlias ? message : null,
      );
    }
    final execution = await _operationRunner(name: name, arguments: arguments);
    final payloadSuccess = _isMutationPayloadSuccess(execution.result);
    if (payloadSuccess && owner != null) {
      _checkpointStore.push(owner, snapshot);
    }
    return _resultForExecution(name, execution, payloadSuccess: payloadSuccess);
  });

  Future<
    FileMutationRuntimeAcknowledgement<
      FileMutationRollbackCapture<TextFileSnapshot>
    >
  >
  captureBefore(FileMutationRuntimeIdentity identity) async {
    if (!_hasExactMutationPath(identity)) {
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition: FileMutationRuntimeAcknowledgementDisposition.rejected,
        message: 'The file mutation path is invalid.',
      );
    }
    try {
      final snapshot = await _snapshotReader(identity.canonicalPath);
      if (!_snapshotMatchesIdentity(identity, snapshot)) {
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition:
              FileMutationRuntimeAcknowledgementDisposition.effectUncertain,
          message: 'The rollback snapshot path did not match the mutation.',
        );
      }
      if (snapshot.error != null) {
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.rejected,
          message:
              'A restorable text snapshot is required before file mutation: '
              '${snapshot.error}',
        );
      }
      final beforeFingerprint =
          FilesystemTools.textSnapshotFingerprintForSnapshot(snapshot);
      final capture = FileMutationRollbackCapture<TextFileSnapshot>(
        identity: identity,
        snapshot: snapshot,
        beforeFingerprint: beforeFingerprint,
        compensationToken: _compensationToken(identity, beforeFingerprint),
      );
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        value: capture,
      );
    } catch (error) {
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition: FileMutationRuntimeAcknowledgementDisposition.rejected,
        message: 'Unable to capture the file mutation rollback state: $error',
      );
    }
  }

  Future<FileMutationRuntimeAcknowledgement<String>> fingerprint(
    FileMutationRuntimeIdentity identity,
  ) async {
    if (!_hasExactMutationPath(identity)) {
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition: FileMutationRuntimeAcknowledgementDisposition.rejected,
        message: 'The file mutation path is invalid.',
      );
    }
    try {
      final snapshot = await _snapshotReader(identity.canonicalPath);
      if (!_snapshotMatchesIdentity(identity, snapshot)) {
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition:
              FileMutationRuntimeAcknowledgementDisposition.effectUncertain,
          message: 'The file mutation fingerprint path did not match.',
        );
      }
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        value: FilesystemTools.textSnapshotFingerprintForSnapshot(snapshot),
      );
    } catch (error) {
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition:
            FileMutationRuntimeAcknowledgementDisposition.effectUncertain,
        message: 'Unable to fingerprint the file mutation target: $error',
      );
    }
  }

  /// Runs one raw mutation only after the caller transfers its exact effect
  /// lease. This method never records a rollback checkpoint.
  Future<FileMutationExecutionAcknowledgement> executeRaw(
    FileMutationEffectRequest<TextFileSnapshot> request,
    FileMutationEffectAuthorization authorization,
  ) async {
    final identity = request.identity;
    final capture = request.capture;
    if (authorization.identity != identity ||
        !_captureIsExact(capture) ||
        authorization.attempted) {
      throw ArgumentError('File mutation effect handoff mismatch.');
    }
    final transaction = await _checkpointStore.mutationPathFence
        .beginTransaction(
          path: identity.canonicalPath,
          transactionToken: capture.compensationToken,
        );
    try {
      final arguments = _normalizedMutationArguments(
        identity,
        request.operationRequest.operation.arguments,
      );
      final immediatelyBefore = await _snapshotReader(identity.canonicalPath);
      if (!_snapshotMatchesIdentity(identity, immediatelyBefore)) {
        throw StateError('File mutation precondition path mismatch.');
      }
      final immediatelyBeforeFingerprint =
          FilesystemTools.textSnapshotFingerprintForSnapshot(immediatelyBefore);
      if (immediatelyBeforeFingerprint != capture.beforeFingerprint) {
        final acknowledgement = FileMutationExecutionAcknowledgement(
          identity: identity,
          result: _rawFailure(
            identity,
            'The target file changed before mutation execution.',
          ),
          effectDisposition: FileMutationRawEffectDisposition.noEffect,
        );
        _checkpointStore.mutationPathFence.finishWithoutEffect(transaction);
        return acknowledgement;
      }
      if (!authorization.beginEffectHandoff()) {
        final acknowledgement = FileMutationExecutionAcknowledgement(
          identity: identity,
          result: _rawFailure(
            identity,
            'The file mutation effect authorization expired.',
          ),
          effectDisposition: FileMutationRawEffectDisposition.noEffect,
        );
        _checkpointStore.mutationPathFence.finishWithoutEffect(transaction);
        return acknowledgement;
      }

      FirstPartyToolExecutionResult? execution;
      Object? operationError;
      try {
        execution = await _operationRunner(
          name: identity.toolName,
          arguments: arguments,
        );
      } catch (error) {
        operationError = error;
      }

      final after = await _snapshotReader(identity.canonicalPath);
      if (!_snapshotMatchesIdentity(identity, after)) {
        throw StateError('File mutation postcondition path mismatch.');
      }
      final afterFingerprint =
          FilesystemTools.textSnapshotFingerprintForSnapshot(after);
      if (afterFingerprint == capture.beforeFingerprint) {
        final acknowledgement = FileMutationExecutionAcknowledgement(
          identity: identity,
          result: operationError == null
              ? _resultForExecution(identity.toolName, execution!)
              : _rawFailure(
                  identity,
                  'The raw file mutation failed: $operationError',
                ),
          effectDisposition: FileMutationRawEffectDisposition.noEffect,
        );
        _checkpointStore.mutationPathFence.finishWithoutEffect(transaction);
        return acknowledgement;
      }

      final postcondition = FileMutationEffectPostcondition(
        identity: identity,
        afterFingerprint: afterFingerprint,
        compensationToken: capture.compensationToken,
      );
      if (operationError != null) {
        final acknowledgement = FileMutationExecutionAcknowledgement(
          identity: identity,
          result: _rawFailure(
            identity,
            'The raw file mutation failed after changing the target: '
            '$operationError',
          ),
          effectDisposition: FileMutationRawEffectDisposition.partialOrUnknown,
          postcondition: postcondition,
        );
        _checkpointStore.mutationPathFence.markHandoffReady(transaction);
        return acknowledgement;
      }
      final payloadSuccess = _isMutationPayloadSuccess(execution!.result);
      final acknowledgement = FileMutationExecutionAcknowledgement(
        identity: identity,
        result: _resultForExecution(
          identity.toolName,
          execution,
          payloadSuccess: payloadSuccess,
        ),
        effectDisposition: payloadSuccess
            ? FileMutationRawEffectDisposition.applied
            : FileMutationRawEffectDisposition.partialOrUnknown,
        postcondition: postcondition,
      );
      _checkpointStore.mutationPathFence.markHandoffReady(transaction);
      return acknowledgement;
    } catch (_) {
      if (authorization.started) {
        _checkpointStore.mutationPathFence.markHandoffReady(transaction);
      } else {
        _checkpointStore.mutationPathFence.finishWithoutEffect(transaction);
      }
      rethrow;
    }
  }

  Future<FileMutationRuntimeAcknowledgement<FileMutationRollbackRecordReceipt>>
  recordMutation(
    FileMutationRollbackRecordRequest<TextFileSnapshot> request,
  ) async {
    final identity = request.identity;
    final capture = request.capture;
    if (!_captureIsExact(capture) ||
        request.expectedAfterFingerprint.trim().isEmpty) {
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition:
            FileMutationRuntimeAcknowledgementDisposition.effectUncertain,
        message: 'The rollback record request did not match its capture.',
      );
    }
    Future<
      FileMutationRuntimeAcknowledgement<FileMutationRollbackRecordReceipt>
    >
    record() async {
      final observed = await fingerprint(identity);
      if (observed.disposition !=
              FileMutationRuntimeAcknowledgementDisposition.completed ||
          observed.value != request.expectedAfterFingerprint) {
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition:
              FileMutationRuntimeAcknowledgementDisposition.effectUncertain,
          message:
              'The file changed before its rollback checkpoint was recorded.',
        );
      }
      final recordToken = _checkpointStore.recordMutationSnapshot(
        identity.owner,
        capture.snapshot,
        compensationToken: capture.compensationToken,
      );
      if (recordToken == null) {
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition:
              FileMutationRuntimeAcknowledgementDisposition.ownerExpired,
          message: 'The file mutation owner retired before rollback recording.',
        );
      }
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        value: FileMutationRollbackRecordReceipt(
          identity: identity,
          compensationToken: capture.compensationToken,
          recordToken: recordToken,
        ),
      );
    }

    final settlement = await _checkpointStore.mutationPathFence
        .settleTransaction(
          path: identity.canonicalPath,
          transactionToken: capture.compensationToken,
          operation: record,
          releaseWhen: (acknowledgement) =>
              acknowledgement.disposition ==
              FileMutationRuntimeAcknowledgementDisposition.completed,
        );
    if (settlement != null) {
      return settlement.value;
    }
    return _checkpointStore.mutationPathFence.runExclusive(
      identity.canonicalPath,
      record,
    );
  }

  bool _captureIsExact(FileMutationRollbackCapture<TextFileSnapshot> capture) {
    if (!_hasExactMutationPath(capture.identity) ||
        !_snapshotMatchesIdentity(capture.identity, capture.snapshot)) {
      return false;
    }
    final fingerprint = FilesystemTools.textSnapshotFingerprintForSnapshot(
      capture.snapshot,
    );
    return fingerprint == capture.beforeFingerprint &&
        capture.compensationToken ==
            _compensationToken(capture.identity, fingerprint);
  }

  bool _hasExactMutationPath(FileMutationRuntimeIdentity identity) =>
      identity.canonicalPath.trim().isNotEmpty &&
      FileMutationKind.values.any((kind) => kind.toolName == identity.toolName);

  bool _snapshotMatchesIdentity(
    FileMutationRuntimeIdentity identity,
    TextFileSnapshot snapshot,
  ) => DartProjectPath.pathKey(snapshot.path) == identity.canonicalPath;

  String _compensationToken(
    FileMutationRuntimeIdentity identity,
    String beforeFingerprint,
  ) {
    return fileMutationJsonDigest({
      'owner': {
        'conversationId': identity.owner.conversationId,
        'interactionGeneration': identity.owner.interactionGeneration,
      },
      'toolCallId': identity.toolCallId,
      'toolName': identity.toolName,
      'argumentDigest': identity.argumentDigest,
      'resolvedArgumentDigest': identity.resolvedArgumentDigest,
      'projectRoot': identity.projectRoot,
      'canonicalPath': identity.canonicalPath,
      'approvalContextDigest': identity.approvalContextDigest,
      'beforeFingerprint': beforeFingerprint,
    });
  }

  Map<String, dynamic> _normalizedMutationArguments(
    FileMutationRuntimeIdentity identity,
    Map<String, dynamic> arguments,
  ) {
    final path = (arguments['path'] as String?)?.trim() ?? '';
    if (path.isEmpty ||
        DartProjectPath.pathKey(path) != identity.canonicalPath) {
      throw ArgumentError.value(
        path,
        'arguments',
        'The raw mutation path must match the canonical identity path.',
      );
    }
    return switch (identity.toolName) {
      'write_file' => <String, dynamic>{
        'path': path,
        'content': arguments['content'] as String? ?? '',
        'create_parents': arguments['create_parents'] as bool? ?? true,
      },
      'edit_file' => <String, dynamic>{
        'path': path,
        'old_text': arguments['old_text'] as String? ?? '',
        'new_text': arguments['new_text'] as String? ?? '',
        'replace_all': arguments['replace_all'] as bool? ?? false,
      },
      'delete_file' => <String, dynamic>{'path': path},
      _ => throw ArgumentError.value(
        identity.toolName,
        'name',
        'Unsupported raw file mutation.',
      ),
    };
  }

  McpToolResult _resultForExecution(
    String name,
    FirstPartyToolExecutionResult execution, {
    bool? payloadSuccess,
  }) {
    final succeeded =
        payloadSuccess ?? _isMutationPayloadSuccess(execution.result);
    final resultSuccess = name == 'delete_file' ? succeeded : true;
    return McpToolResult(
      toolName: name,
      result: execution.result,
      isSuccess: resultSuccess,
      errorMessage: resultSuccess ? null : 'Failed to delete file',
      outcome: execution.outcome,
    );
  }

  McpToolResult _rawFailure(
    FileMutationRuntimeIdentity identity,
    String message,
  ) {
    return McpToolResult(
      toolName: identity.toolName,
      result: jsonEncode({
        'ok': false,
        'code': 'file_mutation_raw_effect_failed',
        'error': message,
        'path': identity.canonicalPath,
      }),
      isSuccess: false,
      errorMessage: message,
    );
  }

  bool _isMutationPayloadSuccess(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is! Map<String, dynamic> ||
          (decoded['error'] == null && decoded['already_applied'] != true);
    } catch (_) {
      return true;
    }
  }
}
