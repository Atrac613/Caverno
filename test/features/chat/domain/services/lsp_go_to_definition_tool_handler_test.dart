import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/lsp_go_to_definition_tool_handler.dart';
import 'package:test/test.dart';

final class _RecordingLspDefinitionPort implements LspDefinitionPort {
  List<LspDefinitionLocation>? definitions;
  LspDefinitionOperationIdentity? resultIdentity;
  LspDefinitionLookupResultKind resultKind =
      LspDefinitionLookupResultKind.completed;
  LspDefinitionSessionEffect sessionEffect = LspDefinitionSessionEffect.reused;
  Object failedError = StateError('session crashed');
  Object? thrownError;
  void Function(LspDefinitionLookupRequest request)? beforeReturn;

  int callCount = 0;
  final List<LspDefinitionLookupRequest> calls = [];

  @override
  Future<LspDefinitionLookupResult> goToDefinition(
    LspDefinitionLookupRequest request,
  ) async {
    callCount += 1;
    calls.add(request);
    final thrown = thrownError;
    if (thrown != null) throw thrown;
    beforeReturn?.call(request);
    final identity = resultIdentity ?? request.identity;
    return switch (resultKind) {
      LspDefinitionLookupResultKind.completed =>
        LspDefinitionLookupResult.completed(
          identity: identity,
          definitions: definitions,
          sessionEffect: sessionEffect,
        ),
      LspDefinitionLookupResultKind.failed => LspDefinitionLookupResult.failed(
        identity: identity,
        error: failedError,
        sessionEffect: sessionEffect,
      ),
      LspDefinitionLookupResultKind.ownerExpired =>
        LspDefinitionLookupResult.ownerExpired(
          identity: identity,
          sessionEffect: sessionEffect,
        ),
      LspDefinitionLookupResultKind.effectUncertain =>
        LspDefinitionLookupResult.effectUncertain(identity: identity),
    };
  }
}

final class _RecordingLspLifecyclePort implements LspDefinitionLifecyclePort {
  final List<LspDefinitionOperationIdentity> acknowledgements = [];
  LspDefinitionOperationIdentity? firstIdentity;
  LspDefinitionOperationIdentity? secondIdentity;
  LspDefinitionOwnerAcknowledgementDisposition firstDisposition =
      LspDefinitionOwnerAcknowledgementDisposition.current;
  LspDefinitionOwnerAcknowledgementDisposition secondDisposition =
      LspDefinitionOwnerAcknowledgementDisposition.current;
  Object? firstError;
  Object? secondError;

  @override
  LspDefinitionOwnerAcknowledgement acknowledgeOwner(
    LspDefinitionOperationIdentity identity,
  ) {
    acknowledgements.add(identity);
    final first = acknowledgements.length == 1;
    final error = first ? firstError : secondError;
    if (error != null) throw error;
    final acknowledgedIdentity = first
        ? firstIdentity ?? identity
        : secondIdentity ?? identity;
    final disposition = first ? firstDisposition : secondDisposition;
    return disposition == LspDefinitionOwnerAcknowledgementDisposition.current
        ? LspDefinitionOwnerAcknowledgement.current(
            identity: acknowledgedIdentity,
          )
        : LspDefinitionOwnerAcknowledgement.ownerExpired(
            identity: acknowledgedIdentity,
          );
  }
}

LspGoToDefinitionToolInput _input({
  required ChatTurnOwner owner,
  String toolCallId = 'call-a',
  String toolName = canonicalLspGoToDefinitionToolName,
  String? projectRoot = '/workspace/project',
  Map<String, dynamic> arguments = const {
    'path': 'lib/main.dart',
    'line': 1,
    'column': 1,
  },
}) {
  return LspGoToDefinitionToolInput(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
    ownerProjectRoot: projectRoot,
    arguments: arguments,
  );
}

LspGoToDefinitionToolHandler _handler(
  LspDefinitionPort port, {
  LspDefinitionLifecyclePort? lifecycle,
}) {
  return LspGoToDefinitionToolHandler(
    port: port,
    lifecyclePort: lifecycle ?? _RecordingLspLifecyclePort(),
  );
}

Map<String, dynamic> _payload(String result) {
  return jsonDecode(result) as Map<String, dynamic>;
}

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );
  final visibleOwner = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 11,
  );

  test('requires the explicit owner project root', () async {
    for (final projectRoot in <String?>[null, '', '  ']) {
      final port = _RecordingLspDefinitionPort();
      final result = await _handler(
        port,
      ).handle(_input(owner: owner, projectRoot: projectRoot));

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'An active coding project is required');
      expect(_payload(result.result), {
        'ok': false,
        'code': 'active_coding_project_required',
        'error':
            'An active coding project is required for LSP go-to-definition.',
      });
      expect(port.callCount, 0);
    }
  });

  test('rejects missing and malformed path, line, or column values', () async {
    final cases = <Map<String, dynamic>>[
      const {'line': 1, 'column': 1},
      const {'path': ' ', 'line': 1, 'column': 1},
      const {'path': 'lib/main.dart', 'column': 1},
      const {'path': 'lib/main.dart', 'line': 'invalid', 'column': 1},
      const {'path': 'lib/main.dart', 'line': 1},
      const {'path': 'lib/main.dart', 'line': 1, 'column': 'invalid'},
    ];

    for (final arguments in cases) {
      final port = _RecordingLspDefinitionPort();
      final result = await _handler(
        port,
      ).handle(_input(owner: owner, arguments: arguments));

      expect(result.isSuccess, isFalse, reason: '$arguments');
      expect(result.errorMessage, 'path, line, and column are required');
      expect(_payload(result.result), {
        'ok': false,
        'code': 'invalid_arguments',
        'error': 'path, line, and column are required.',
      });
      expect(port.callCount, 0);
    }
  });

  test('rejects zero and negative one-based positions', () async {
    for (final arguments in const [
      {'path': 'lib/main.dart', 'line': 0, 'column': 1},
      {'path': 'lib/main.dart', 'line': -1, 'column': 1},
      {'path': 'lib/main.dart', 'line': 1, 'column': 0},
      {'path': 'lib/main.dart', 'line': 1, 'column': -1},
    ]) {
      final port = _RecordingLspDefinitionPort();
      final result = await _handler(
        port,
      ).handle(_input(owner: owner, arguments: arguments));

      expect(result.isSuccess, isFalse, reason: '$arguments');
      expect(_payload(result.result)['code'], 'invalid_arguments');
      expect(port.callCount, 0);
    }
  });

  test(
    'freezes arguments and forwards exact owner with zero-based positions',
    () async {
      final rawTags = <Object?>['owner-a'];
      final rawMetadata = <String, dynamic>{'owner': rawTags};
      final arguments = <String, dynamic>{
        'path': 'lib/main.dart',
        'line': ' 2 ',
        'column': 3.9,
        'metadata': {
          'paths': <Object?>['lib/main.dart'],
          'raw_metadata': rawMetadata,
        },
      };
      final input = _input(owner: owner, arguments: arguments);
      final metadata = arguments['metadata']! as Map<String, dynamic>;
      arguments
        ..['path'] = 'lib/poison.dart'
        ..['line'] = 99
        ..['column'] = 99;
      (metadata['paths']! as List<Object?>).add('lib/poison.dart');
      rawMetadata['poisoned'] = true;
      rawTags.add('poisoned');
      final port = _RecordingLspDefinitionPort()..definitions = const [];

      final result = await _handler(port).handle(input);

      expect(result.isSuccess, isTrue);
      final request = port.calls.single;
      expect(request.identity, same(input.identity));
      expect(request.identity.owner, owner);
      expect(request.identity.toolCallId, 'call-a');
      expect(request.identity.toolName, canonicalLspGoToDefinitionToolName);
      expect(request.projectRoot, '/workspace/project');
      expect(request.path, '/workspace/project/lib/main.dart');
      expect(request.line, 1);
      expect(request.character, 2);
      final frozenMetadata =
          input.arguments['metadata'] as Map<String, dynamic>;
      final frozenRawMetadata =
          frozenMetadata['raw_metadata'] as Map<String, dynamic>;
      final frozenTags = frozenRawMetadata['owner'] as List<Object?>;
      expect(frozenRawMetadata.keys, ['owner']);
      expect(frozenTags, ['owner-a']);
      expect(
        () => input.arguments['path'] = 'lib/other.dart',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((input.arguments['metadata'] as Map<String, dynamic>)['paths']
                    as List<Object?>)
                .add('lib/other.dart'),
        throwsUnsupportedError,
      );
      expect(() => frozenRawMetadata['changed'] = true, throwsUnsupportedError);
      expect(() => frozenTags.add('changed'), throwsUnsupportedError);
    },
  );

  test('rejects empty identities and non-JSON argument aliases', () {
    for (final toolCallId in ['', '  ']) {
      expect(
        () => _input(owner: owner, toolCallId: toolCallId),
        throwsArgumentError,
      );
    }
    expect(
      () => _input(owner: owner, toolName: ' lsp_go_to_definition '),
      throwsArgumentError,
    );
    expect(
      () => _input(
        owner: owner,
        arguments: {
          'path': 'lib/main.dart',
          'line': 1,
          'column': 1,
          'metadata': <Object?, Object?>{7: 'not-json'},
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => _input(
        owner: owner,
        arguments: {
          'path': 'lib/main.dart',
          'line': 1,
          'column': 1,
          'metadata': <String>{'not-json'},
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => _input(
        owner: owner,
        arguments: {
          'path': 'lib/main.dart',
          'line': 1,
          'column': 1,
          'metadata': _MutableValue(),
        },
      ),
      throwsArgumentError,
    );
  });

  test('keeps relative paths and roots isolated across owners', () async {
    final port = _RecordingLspDefinitionPort()..definitions = const [];
    final handler = _handler(port);

    final visibleResult = await handler.handle(
      _input(
        owner: visibleOwner,
        projectRoot: '/workspace/b',
        arguments: const {'path': 'lib/visible.dart', 'line': 9, 'column': 5},
      ),
    );
    final ownerResult = await handler.handle(
      _input(
        owner: owner,
        projectRoot: '/workspace/project',
        arguments: const {'path': 'lib/owner.dart', 'line': 2, 'column': 3},
      ),
    );

    expect(visibleResult.isSuccess, isTrue);
    expect(ownerResult.isSuccess, isTrue);
    expect(port.calls[0].identity.owner, visibleOwner);
    expect(port.calls[0].projectRoot, '/workspace/b');
    expect(port.calls[0].path, '/workspace/b/lib/visible.dart');
    expect(port.calls[0].line, 8);
    expect(port.calls[0].character, 4);
    expect(port.calls[1].identity.owner, owner);
    expect(port.calls[1].projectRoot, '/workspace/project');
    expect(port.calls[1].path, '/workspace/project/lib/owner.dart');
    expect(port.calls[1].line, 1);
    expect(port.calls[1].character, 2);
    expect(
      _payload(ownerResult.result)['path'],
      '/workspace/project/lib/owner.dart',
    );
    expect(
      ownerResult.result,
      isNot(contains('/workspace/b/lib/visible.dart')),
    );
  });

  test(
    'contains completions poisoned by another conversation or generation',
    () async {
      final staleOwners = [
        visibleOwner,
        ChatTurnOwner(
          conversationId: owner.conversationId,
          interactionGeneration: owner.interactionGeneration - 1,
        ),
      ];

      for (final staleOwner in staleOwners) {
        final poisonedInput = _input(owner: staleOwner);
        final port = _RecordingLspDefinitionPort()
          ..resultIdentity = poisonedInput.identity
          ..definitions = [
            const LspDefinitionLocation(
              uri: 'file:///workspace/poison.dart',
              startLine: 0,
              startCharacter: 0,
            ),
          ];

        final result = await _handler(port).handle(_input(owner: owner));

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('possible process side effects'));
        expect(
          _payload(result.result)['code'],
          'lsp_session_outcome_uncertain',
        );
        expect(result.result, isNot(contains('poison.dart')));
      }
    },
  );

  test('keys the same owner and call by immutable request digest', () {
    final first = _input(owner: owner);
    final same = _input(owner: owner);
    final changed = _input(
      owner: owner,
      arguments: const {'path': 'lib/other.dart', 'line': 1, 'column': 1},
    );

    expect(first.identity, same.identity);
    expect(first.identity.hashCode, same.identity.hashCode);
    expect(first.identity, isNot(changed.identity));
    expect(first.identity.requestDigest, isNot(changed.identity.requestDigest));
  });

  test('blocks cross-owner and same-owner poison before dispatch', () async {
    final request = _input(owner: owner);
    final poisonedIdentities = [
      _input(owner: visibleOwner).identity,
      _input(owner: owner, toolCallId: 'call-b').identity,
      _input(
        owner: owner,
        arguments: const {'path': 'lib/poison.dart', 'line': 1, 'column': 1},
      ).identity,
    ];

    for (final poisonedIdentity in poisonedIdentities) {
      final port = _RecordingLspDefinitionPort();
      final lifecycle = _RecordingLspLifecyclePort()
        ..firstIdentity = poisonedIdentity;

      final result = await _handler(port, lifecycle: lifecycle).handle(request);

      expect(result.isSuccess, isFalse);
      expect(_payload(result.result)['code'], 'turn_owner_expired');
      expect(port.calls, isEmpty);
      expect(lifecycle.acknowledgements, [request.identity]);
    }
  });

  test(
    'contains same-owner completion and post-dispatch acknowledgement poison',
    () async {
      final request = _input(owner: owner);
      final sameOwnerOtherCall = _input(
        owner: owner,
        toolCallId: 'call-b',
      ).identity;

      final completionPort = _RecordingLspDefinitionPort()
        ..resultIdentity = sameOwnerOtherCall
        ..definitions = [
          const LspDefinitionLocation(
            uri: 'file:///workspace/poison.dart',
            startLine: 0,
            startCharacter: 0,
          ),
        ];
      final completionResult = await _handler(completionPort).handle(request);

      expect(
        _payload(completionResult.result)['code'],
        'lsp_session_outcome_uncertain',
      );
      expect(completionResult.result, isNot(contains('poison.dart')));

      final acknowledgementPort = _RecordingLspDefinitionPort()
        ..definitions = [
          const LspDefinitionLocation(
            uri: 'file:///workspace/poison.dart',
            startLine: 0,
            startCharacter: 0,
          ),
        ];
      final lifecycle = _RecordingLspLifecyclePort()
        ..secondIdentity = sameOwnerOtherCall;
      final acknowledgementResult = await _handler(
        acknowledgementPort,
        lifecycle: lifecycle,
      ).handle(request);

      expect(
        _payload(acknowledgementResult.result)['code'],
        'lsp_session_outcome_uncertain',
      );
      expect(acknowledgementResult.result, isNot(contains('poison.dart')));
    },
  );

  test(
    'distinguishes safe expiry from a retained post-launch process',
    () async {
      for (final safeEffect in const [
        LspDefinitionSessionEffect.none,
        LspDefinitionSessionEffect.reused,
        LspDefinitionSessionEffect.compensated,
      ]) {
        final lifecycle = _RecordingLspLifecyclePort()
          ..secondDisposition =
              LspDefinitionOwnerAcknowledgementDisposition.ownerExpired;
        final port = _RecordingLspDefinitionPort()
          ..definitions = const []
          ..sessionEffect = safeEffect;

        final result = await _handler(
          port,
          lifecycle: lifecycle,
        ).handle(_input(owner: owner));

        expect(
          _payload(result.result)['code'],
          'turn_owner_expired',
          reason: safeEffect.name,
        );
      }

      final lifecycle = _RecordingLspLifecyclePort()
        ..secondDisposition =
            LspDefinitionOwnerAcknowledgementDisposition.ownerExpired;
      final port = _RecordingLspDefinitionPort()
        ..definitions = const []
        ..sessionEffect = LspDefinitionSessionEffect.started;

      final result = await _handler(
        port,
        lifecycle: lifecycle,
      ).handle(_input(owner: owner));

      expect(_payload(result.result)['code'], 'lsp_session_outcome_uncertain');
      expect(result.errorMessage, contains('possible process side effects'));
    },
  );

  test('contains uncertain and thrown post-dispatch outcomes', () async {
    final uncertainPort = _RecordingLspDefinitionPort()
      ..resultKind = LspDefinitionLookupResultKind.effectUncertain;
    final uncertain = await _handler(
      uncertainPort,
    ).handle(_input(owner: owner));

    expect(_payload(uncertain.result)['code'], 'lsp_session_outcome_uncertain');

    final thrownPort = _RecordingLspDefinitionPort()
      ..thrownError = StateError('transport lost after launch');
    final thrown = await _handler(thrownPort).handle(_input(owner: owner));

    expect(_payload(thrown.result), {
      'ok': false,
      'code': 'lsp_session_outcome_uncertain',
      'error':
          'The LSP definition lookup process outcome is uncertain; inspect '
          'possible process side effects before retrying.',
      'path': '/workspace/project/lib/main.dart',
      'next_action':
          'Inspect active language server processes before retrying the '
          'lookup.',
    });
  });

  test('fences lifecycle acknowledgement failures around dispatch', () async {
    final beforeLifecycle = _RecordingLspLifecyclePort()
      ..firstError = StateError('lifecycle unavailable');
    final beforePort = _RecordingLspDefinitionPort();
    final before = await _handler(
      beforePort,
      lifecycle: beforeLifecycle,
    ).handle(_input(owner: owner));

    expect(_payload(before.result)['code'], 'turn_owner_expired');
    expect(beforePort.calls, isEmpty);

    final afterLifecycle = _RecordingLspLifecyclePort()
      ..secondError = StateError('lifecycle unavailable');
    final afterPort = _RecordingLspDefinitionPort()..definitions = const [];
    final after = await _handler(
      afterPort,
      lifecycle: afterLifecycle,
    ).handle(_input(owner: owner));

    expect(_payload(after.result)['code'], 'lsp_session_outcome_uncertain');
    expect(afterPort.calls, hasLength(1));
  });

  test(
    'maps an explicitly expired owner completion to owner-expired',
    () async {
      final port = _RecordingLspDefinitionPort()
        ..resultKind = LspDefinitionLookupResultKind.ownerExpired
        ..sessionEffect = LspDefinitionSessionEffect.reused;

      final result = await _handler(port).handle(_input(owner: owner));

      expect(result.isSuccess, isFalse);
      expect(_payload(result.result)['code'], 'turn_owner_expired');
    },
  );

  test('maps an unavailable language server to the exact failure', () async {
    final port = _RecordingLspDefinitionPort();

    final result = await _handler(port).handle(_input(owner: owner));

    expect(result.isSuccess, isFalse);
    expect(
      result.errorMessage,
      'No supported language server session is available',
    );
    expect(_payload(result.result), {
      'ok': false,
      'code': 'language_server_unavailable',
      'error':
          'No supported language server session is available for this file.',
      'path': '/workspace/project/lib/main.dart',
    });
  });

  test(
    'maps an empty definition response to an exact success payload',
    () async {
      final port = _RecordingLspDefinitionPort()..definitions = const [];

      final result = await _handler(port).handle(_input(owner: owner));

      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(_payload(result.result), {
        'ok': true,
        'provider': 'lsp_json_rpc',
        'path': '/workspace/project/lib/main.dart',
        'line': 1,
        'column': 1,
        'definition_count': 0,
        'definitions': <dynamic>[],
      });
    },
  );

  test('decodes a file URI and maps its one-based range', () async {
    final uri = Uri.file(
      '/workspace/project/lib/my definition.dart',
    ).toString();
    final port = _RecordingLspDefinitionPort()
      ..definitions = [
        LspDefinitionLocation(
          uri: uri,
          startLine: 4,
          startCharacter: 2,
          endLine: 6,
          endCharacter: 8,
        ),
      ];

    final result = await _handler(port).handle(_input(owner: owner));

    expect(result.isSuccess, isTrue);
    expect(_payload(result.result)['definitions'], [
      {
        'uri': uri,
        'path': '/workspace/project/lib/my definition.dart',
        'relative_path': 'lib/my definition.dart',
        'line': 5,
        'column': 3,
        'end_line': 7,
        'end_column': 9,
      },
    ]);
  });

  test('preserves multiple definition ordering and optional paths', () async {
    final firstUri = Uri.file('/workspace/project/lib/first.dart').toString();
    final secondUri = Uri.file('/external/second.dart').toString();
    const remoteUri = 'https://example.test/third.dart';
    const malformedUri = 'file://[invalid';
    final port = _RecordingLspDefinitionPort()
      ..definitions = [
        LspDefinitionLocation(uri: firstUri, startLine: 0, startCharacter: 1),
        LspDefinitionLocation(uri: secondUri, startLine: 2, startCharacter: 3),
        const LspDefinitionLocation(
          uri: remoteUri,
          startLine: 4,
          startCharacter: 5,
        ),
        const LspDefinitionLocation(
          uri: malformedUri,
          startLine: 6,
          startCharacter: 7,
        ),
      ];

    final result = await _handler(port).handle(_input(owner: owner));
    final definitions = _payload(result.result)['definitions'] as List<dynamic>;

    expect(definitions, [
      {
        'uri': firstUri,
        'path': '/workspace/project/lib/first.dart',
        'relative_path': 'lib/first.dart',
        'line': 1,
        'column': 2,
      },
      {
        'uri': secondUri,
        'path': '/external/second.dart',
        'line': 3,
        'column': 4,
      },
      {'uri': remoteUri, 'line': 5, 'column': 6},
      {'uri': malformedUri, 'line': 7, 'column': 8},
    ]);
  });

  test('maps an identity-tagged port failure to the exact payload', () async {
    final port = _RecordingLspDefinitionPort()
      ..resultKind = LspDefinitionLookupResultKind.failed
      ..sessionEffect = LspDefinitionSessionEffect.none
      ..failedError = StateError('session crashed');

    final result = await _handler(port).handle(_input(owner: owner));

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, 'Bad state: session crashed');
    expect(_payload(result.result), {
      'ok': false,
      'code': 'lsp_go_to_definition_failed',
      'error': 'Bad state: session crashed',
      'path': '/workspace/project/lib/main.dart',
    });
  });
}

final class _MutableValue {}
