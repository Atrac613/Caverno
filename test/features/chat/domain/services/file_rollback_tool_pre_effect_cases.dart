part of 'file_rollback_tool_handler_test.dart';

void _runFileRollbackPreEffectCases(
  ChatTurnOwner ownerA,
  ChatTurnOwner ownerANext,
  ChatTurnOwner ownerB,
) {
  group('FileRollbackToolHandler pre-effect fencing', () {
    test('returns an exact cached denial before reading history', () async {
      const cachedResult = McpToolResult(
        toolName: canonicalFileRollbackToolName,
        result: '',
        isSuccess: false,
        errorMessage: 'cached denial',
      );
      final request = _request(ownerA);
      final history = _FakeHistoryPort();
      final approval = _FakeApprovalPort()
        ..cachedDenial = FileRollbackCachedDenial(
          identity: request.identity,
          result: cachedResult,
        );
      final execution = _FakeExecutionPort();

      expect(
        await _handler(history, approval, execution).handle(request),
        same(cachedResult),
      );
      expect(history.identities, isEmpty);
      expect(execution.identities, isEmpty);
    });

    test('rejects a cached result with another tool identity', () async {
      const poisonedResult = McpToolResult(
        toolName: 'delete_file',
        result: '',
        isSuccess: false,
        errorMessage: 'poisoned',
      );
      final request = _request(ownerA);
      final history = _FakeHistoryPort();
      final approval = _FakeApprovalPort()
        ..cachedDenial = FileRollbackCachedDenial(
          identity: request.identity,
          result: poisonedResult,
        );
      final execution = _FakeExecutionPort();

      await expectLater(
        _handler(history, approval, execution).handle(request),
        throwsStateError,
      );
      expect(history.identities, isEmpty);
      expect(execution.identities, isEmpty);
    });

    test('rejects a poisoned cached denial before history lookup', () async {
      final history = _FakeHistoryPort();
      final approval = _FakeApprovalPort()
        ..cachedDenial = FileRollbackCachedDenial(
          identity: _identity(ownerB),
          result: _knownFailure,
        );
      final execution = _FakeExecutionPort();

      await expectLater(
        _handler(history, approval, execution).handle(_request(ownerA)),
        throwsStateError,
      );
      expect(history.identities, isEmpty);
      expect(execution.identities, isEmpty);
    });

    test('returns no-history failure for only the exact identity', () async {
      final history = _FakeHistoryPort();
      final approval = _FakeApprovalPort();
      final execution = _FakeExecutionPort();
      final request = _request(ownerA);

      final result = await _handler(
        history,
        approval,
        execution,
      ).handle(request);

      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'No recent file change is available to roll back',
      );
      expect(history.identities, [request.identity]);
      expect(approval.gateRequests, isEmpty);
      expect(execution.identities, isEmpty);
    });

    test('propagates history failure without approval effects', () async {
      final error = StateError('history failed');
      final history = _FakeHistoryPort()..error = error;
      final approval = _FakeApprovalPort();
      final execution = _FakeExecutionPort();

      await expectLater(
        _handler(history, approval, execution).handle(_request(ownerA)),
        throwsA(same(error)),
      );
      expect(approval.gateRequests, isEmpty);
      expect(execution.identities, isEmpty);
    });

    for (final poison in <FileRollbackOperationIdentity Function()>[
      () => _identity(ownerA, call: 'other-call'),
      () => _identity(ownerANext),
      () => _identity(ownerB),
    ]) {
      test('rejects a poisoned preview before approval', () async {
        final history = _FakeHistoryPort()..preview = _preview(poison());
        final approval = _FakeApprovalPort();
        final execution = _FakeExecutionPort();

        await expectLater(
          _handler(history, approval, execution).handle(_request(ownerA)),
          throwsStateError,
        );
        expect(approval.gateRequests, isEmpty);
        expect(execution.identities, isEmpty);
      });
    }

    test('rejects an approval response for another checkpoint', () async {
      final request = _request(ownerA);
      final history = _FakeHistoryPort()..preview = _preview(request.identity);
      final approval = _FakeApprovalPort()..gateToken = 'checkpoint-b';
      final execution = _FakeExecutionPort();

      await expectLater(
        _handler(history, approval, execution).handle(request),
        throwsStateError,
      );
      expect(approval.manualRequests, isEmpty);
      expect(execution.identities, isEmpty);
    });

    test('rejects a same-owner approval from another call', () async {
      final request = _request(ownerA);
      final history = _FakeHistoryPort()..preview = _preview(request.identity);
      final approval = _FakeApprovalPort()
        ..gateIdentity = _identity(ownerA, call: 'other-call');
      final execution = _FakeExecutionPort();

      await expectLater(
        _handler(history, approval, execution).handle(request),
        throwsStateError,
      );
      expect(execution.identities, isEmpty);
    });

    test('maps exact auto-review denial and acknowledgement', () async {
      final request = _request(ownerA);
      final history = _FakeHistoryPort()..preview = _preview(request.identity);
      final approval = _FakeApprovalPort()
        ..gate = ToolApprovalGateDecision.denied('unsafe rollback');
      final execution = _FakeExecutionPort();

      final result = await _handler(
        history,
        approval,
        execution,
      ).handle(request);

      expect(
        result.result,
        'Auto-review denied this action. Rationale: unsafe rollback',
      );
      expect(result.errorMessage, 'Auto-review denied: unsafe rollback');
      expect(approval.rememberedDenials, [same(result)]);
      expect(execution.identities, isEmpty);
    });

    test('rejects poisoned manual and denial acknowledgements', () async {
      final request = _request(ownerA);
      final history = _FakeHistoryPort()..preview = _preview(request.identity);
      final execution = _FakeExecutionPort();

      final manualPoison = _FakeApprovalPort()
        ..manualIdentity = _identity(ownerB);
      await expectLater(
        _handler(history, manualPoison, execution).handle(request),
        throwsStateError,
      );

      final denialPoison = _FakeApprovalPort()
        ..manualApproved = false
        ..denialAckToken = 'checkpoint-b';
      await expectLater(
        _handler(history, denialPoison, execution).handle(request),
        throwsStateError,
      );
      expect(execution.identities, isEmpty);
    });

    test('uses summary fallback and preserves an explicit reason', () async {
      final summaryRequest = _request(ownerA, call: 'summary');
      final explicitRequest = _request(
        ownerA,
        call: 'explicit',
        arguments: const {'reason': '  restore exact bytes  '},
      );
      final history = _FakeHistoryPort();
      final approval = _FakeApprovalPort()..manualApproved = false;
      final execution = _FakeExecutionPort();

      history.preview = _preview(summaryRequest.identity);
      await _handler(history, approval, execution).handle(summaryRequest);
      expect(
        approval.manualRequests.last.reason,
        'Restore the previous contents of this file.',
      );

      history.preview = _preview(explicitRequest.identity);
      await _handler(history, approval, execution).handle(explicitRequest);
      expect(approval.manualRequests.last.reason, '  restore exact bytes  ');
    });

    test('owner expiration after approval prevents execution', () async {
      final request = _request(ownerA);
      final history = _FakeHistoryPort()..preview = _preview(request.identity);
      final approval = _FakeApprovalPort()
        ..gate = ToolApprovalGateDecision.autoReviewAllowed
        ..ownerAckDisposition =
            FileRollbackAcknowledgementDisposition.ownerExpired;
      final execution = _FakeExecutionPort();

      final result = await _handler(
        history,
        approval,
        execution,
      ).handle(request);

      expect(result.errorMessage, 'Tool approval expired before execution');
      expect(execution.identities, isEmpty);
    });

    test('rejects a cross-owner acknowledgement before execution', () async {
      final request = _request(ownerA);
      final history = _FakeHistoryPort()..preview = _preview(request.identity);
      final approval = _FakeApprovalPort()
        ..gate = ToolApprovalGateDecision.autoReviewAllowed
        ..ownerAckIdentity = _identity(ownerB);
      final execution = _FakeExecutionPort();

      await expectLater(
        _handler(history, approval, execution).handle(request),
        throwsStateError,
      );
      expect(execution.identities, isEmpty);
    });
  });
}
