part of 'file_rollback_tool_handler_test.dart';

void _runFileRollbackContractCases(ChatTurnOwner ownerA) {
  group('FileRollbackOperationIdentity', () {
    test('normalizes and validates the exact tool identity', () {
      final identity = FileRollbackOperationIdentity(
        owner: ownerA,
        toolCallId: ' call-a ',
        toolName: ' rollback_last_file_change ',
      );

      expect(identity.toolCallId, 'call-a');
      expect(identity.toolName, canonicalFileRollbackToolName);
      expect(identity, _identity(ownerA, call: 'call-a'));
      expect(
        () => FileRollbackOperationIdentity(
          owner: ownerA,
          toolCallId: ' ',
          toolName: canonicalFileRollbackToolName,
        ),
        throwsArgumentError,
      );
      expect(
        () => FileRollbackOperationIdentity(
          owner: ownerA,
          toolCallId: 'call-a',
          toolName: '\n',
        ),
        throwsArgumentError,
      );
      expect(
        () => FileRollbackOperationIdentity(
          owner: ownerA,
          toolCallId: 'call-a',
          toolName: 'delete_file',
        ),
        throwsArgumentError,
      );
    });

    test('requires a non-empty checkpoint token', () {
      expect(
        () => _preview(_identity(ownerA), token: '\t'),
        throwsArgumentError,
      );
      expect(
        () => _preview(_identity(ownerA), path: '\n'),
        throwsArgumentError,
      );
      expect(
        _preview(_identity(ownerA), token: ' checkpoint-a ').checkpointToken,
        'checkpoint-a',
      );
    });
  });

  group('FileRollbackToolRequest', () {
    test('deep-freezes JSON-safe input without changing key types', () {
      final labels = <Object?>['safe'];
      final metadata = <String, Object?>{'attempt': 7, 'labels': labels};
      final arguments = <String, dynamic>{
        'reason': 'restore owner A',
        'metadata': metadata,
      };
      final request = _request(ownerA, arguments: arguments);

      labels.add('poisoned');
      metadata['attempt'] = 9;
      arguments['reason'] = 'poisoned';

      expect(request.reason, 'restore owner A');
      expect(request.arguments['metadata'], {
        'attempt': 7,
        'labels': ['safe'],
      });
      expect(
        () => request.arguments['reason'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((request.arguments['metadata'] as Map<String, dynamic>)['labels']
                    as List<Object?>)
                .add('changed'),
        throwsUnsupportedError,
      );
    });

    test('rejects non-JSON keys, sets, and mutable leaves', () {
      for (final arguments in <Map<String, dynamic>>[
        {
          'metadata': <Object?, Object?>{7: 'invalid'},
        },
        {
          'metadata': <String>{'invalid'},
        },
        {'metadata': _MutableLeaf()},
        {'metadata': double.nan},
        {'metadata': double.infinity},
      ]) {
        expect(
          () => _request(ownerA, arguments: arguments),
          throwsArgumentError,
        );
      }
    });
  });
}
