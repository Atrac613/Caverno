part of 'file_rollback_tool_handler_test.dart';

void _runFileRollbackPostEffectCases(
  ChatTurnOwner ownerA,
  ChatTurnOwner ownerANext,
  ChatTurnOwner ownerB,
) {
  group('FileRollbackToolHandler post-effect handling', () {
    late FileRollbackToolRequest request;
    late _FakeHistoryPort history;
    late _FakeApprovalPort approval;
    late _FakeExecutionPort execution;

    setUp(() {
      request = _request(ownerA);
      history = _FakeHistoryPort()..preview = _preview(request.identity);
      approval = _FakeApprovalPort()
        ..gate = ToolApprovalGateDecision.autoReviewAllowed;
      execution = _FakeExecutionPort();
    });

    test('executes and acknowledges the exact checkpoint', () async {
      final result = await _handler(
        history,
        approval,
        execution,
      ).handle(request);

      expect(result, same(_success));
      expect(execution.identities, [request.identity]);
      expect(execution.checkpointTokens, ['checkpoint-a']);
      expect(approval.rememberedResults, [same(_success)]);
      expect(jsonDecode(result.result), {
        'ok': true,
        'path': '/workspace/a/lib/main.dart',
      });
    });

    test(
      'preserves a known execution failure and exact JSON payload',
      () async {
        execution.builder = (identity, token) {
          return FileRollbackExecutionResult.completed(
            identity: identity,
            checkpointToken: token,
            result: _knownFailure,
          );
        };

        final result = await _handler(
          history,
          approval,
          execution,
        ).handle(request);

        expect(result, same(_knownFailure));
        expect(jsonDecode(result.result), {
          'ok': false,
          'code': 'file_changed_since_preview',
          'path': '/workspace/a/lib/main.dart',
        });
        expect(approval.rememberedResults, [same(_knownFailure)]);
      },
    );

    test('does not cache a full-access result', () async {
      approval.gate = ToolApprovalGateDecision.fullAccess;

      expect(
        await _handler(history, approval, execution).handle(request),
        same(_success),
      );
      expect(approval.rememberedResults, isEmpty);
    });

    test('treats execution exceptions as possible side effects', () async {
      execution.error = StateError('transport failed after dispatch');

      final result = await _handler(
        history,
        approval,
        execution,
      ).handle(request);

      expect(
        result.errorMessage,
        'The file change may have been rolled back; inspect the target before '
        'retrying',
      );
      expect(approval.rememberedResults, isEmpty);
    });

    for (final poison in <_ExecutionBuilder>[
      (identity, token) => FileRollbackExecutionResult.completed(
        identity: _identity(ownerA, call: 'other-call'),
        checkpointToken: token,
        result: _success,
      ),
      (identity, token) => FileRollbackExecutionResult.completed(
        identity: _identity(ownerB),
        checkpointToken: token,
        result: _success,
      ),
      (identity, token) => FileRollbackExecutionResult.completed(
        identity: identity,
        checkpointToken: 'checkpoint-b',
        result: _success,
      ),
    ]) {
      test('never trusts a poisoned post-effect completion', () async {
        execution.builder = poison;

        final result = await _handler(
          history,
          approval,
          execution,
        ).handle(request);

        expect(
          result.errorMessage,
          'The file change may have been rolled back; inspect the target before '
          'retrying',
        );
        expect(approval.rememberedResults, isEmpty);
      });
    }

    test('maps explicit execution uncertainty conservatively', () async {
      execution.builder = (identity, token) {
        return FileRollbackExecutionResult.effectUncertain(
          identity: identity,
          checkpointToken: token,
        );
      };

      final result = await _handler(
        history,
        approval,
        execution,
      ).handle(request);

      expect(result.errorMessage, contains('may have been rolled back'));
    });

    for (final disposition in [
      FileRollbackExpiredEffectDisposition.notApplied,
      FileRollbackExpiredEffectDisposition.compensated,
    ]) {
      test(
        'reports safe owner expiry after no effect or compensation',
        () async {
          execution.builder = (identity, token) {
            return FileRollbackExecutionResult.ownerExpired(
              identity: identity,
              checkpointToken: token,
              expiredEffectDisposition: disposition,
            );
          };

          final result = await _handler(
            history,
            approval,
            execution,
          ).handle(request);

          expect(result.errorMessage, 'Tool approval expired before execution');
        },
      );
    }

    for (final disposition in [
      FileRollbackExpiredEffectDisposition.retained,
      FileRollbackExpiredEffectDisposition.uncertain,
    ]) {
      test(
        'reports possible side effect when compensation is unsafe',
        () async {
          execution.builder = (identity, token) {
            return FileRollbackExecutionResult.ownerExpired(
              identity: identity,
              checkpointToken: token,
              expiredEffectDisposition: disposition,
            );
          };

          final result = await _handler(
            history,
            approval,
            execution,
          ).handle(request);

          expect(result.errorMessage, contains('may have been rolled back'));
        },
      );
    }

    test(
      'treats poisoned or failed result acknowledgement as uncertain',
      () async {
        for (final configure in <void Function(_FakeApprovalPort)>[
          (port) => port.resultAckIdentity = _identity(ownerANext),
          (port) => port.resultAckToken = 'checkpoint-b',
          (port) => port.resultAckDisposition =
              FileRollbackAcknowledgementDisposition.ownerExpired,
          (port) => port.resultAckError = StateError('cache unavailable'),
        ]) {
          approval = _FakeApprovalPort()
            ..gate = ToolApprovalGateDecision.autoReviewAllowed;
          configure(approval);

          final result = await _handler(
            history,
            approval,
            execution,
          ).handle(request);

          expect(result.errorMessage, contains('may have been rolled back'));
        }
      },
    );

    test('never trusts a completed result for another tool', () async {
      execution.builder = (identity, token) {
        return FileRollbackExecutionResult.completed(
          identity: identity,
          checkpointToken: token,
          result: const McpToolResult(
            toolName: 'delete_file',
            result: '{"ok":true}',
            isSuccess: true,
          ),
        );
      };

      final result = await _handler(
        history,
        approval,
        execution,
      ).handle(request);

      expect(result.errorMessage, contains('may have been rolled back'));
      expect(approval.rememberedResults, isEmpty);
    });
  });
}
