import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/python_script_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/python_staging_lease_registry.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 8,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 8,
  );
  final ownerANextGeneration = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 9,
  );

  group('PythonScriptToolRequest', () {
    test('freezes arguments and the exact owner message snapshot', () {
      final labels = <Object?>['metadata'];
      final metadata = <String, dynamic>{
        'labels': labels,
        'flags': <Object?>['safe'],
        'owners': <String, Object?>{'primary': 'owner-a'},
      };
      final arguments = <String, dynamic>{
        'code': '  print("owner a")  ',
        'reason': 'Inspect owner A.',
        'metadata': metadata,
      };
      final messages = <Message>[
        _message(
          id: 'owner-a-input',
          role: MessageRole.user,
          imageBase64: 'owner-a-base64',
          imageMimeType: 'image/png',
        ),
      ];
      final snapshot = PythonOwnerMessageSnapshot(
        owner: ownerA,
        messages: messages,
      );
      final request = PythonScriptToolRequest(
        owner: ownerA,
        toolCallId: 'python-call-owner-a',
        toolName: 'run_python_script',
        ownerMessages: snapshot,
        arguments: arguments,
      );

      labels.add('poisoned');
      (metadata['flags'] as List<Object?>).add('poisoned');
      (metadata['owners'] as Map)['primary'] = 'owner-b';
      metadata['labels'] = ['replaced'];
      arguments['code'] = 'print("poisoned")';
      messages.add(
        _message(
          id: 'visible-owner-b',
          role: MessageRole.user,
          imageBase64: 'owner-b-base64',
        ),
      );

      expect(request.code, 'print("owner a")');
      expect(request.toolCallId, 'python-call-owner-a');
      expect(request.reason, 'Inspect owner A.');
      expect(request.ownerMessages.messages, hasLength(1));
      expect(request.arguments['metadata'], {
        'labels': ['metadata'],
        'flags': ['safe'],
        'owners': {'primary': 'owner-a'},
      });
      final frozenOwners =
          (request.arguments['metadata'] as Map)['owners'] as Map;
      expect(
        () => (request.arguments['metadata'] as Map)['new'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['labels'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['flags'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(() => frozenOwners['primary'] = 'late', throwsUnsupportedError);
      expect(
        () => request.ownerMessages.messages.add(
          _message(id: 'late', role: MessageRole.user),
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects a message snapshot from another owner or generation', () {
      for (final poisonedOwner in [ownerB, ownerANextGeneration]) {
        expect(
          () => PythonScriptToolRequest(
            owner: ownerA,
            toolCallId: 'python-call-owner-a',
            toolName: 'run_python_script',
            ownerMessages: PythonOwnerMessageSnapshot(
              owner: poisonedOwner,
              messages: const [],
            ),
            arguments: const {'code': 'pass'},
          ),
          throwsArgumentError,
        );
      }
    });

    test('normalizes the attempt identity and stringifies the reason', () {
      final request = _request(
        ownerA,
        toolCallId: ' python-call ',
        toolName: ' run_python_script ',
        arguments: const {'code': 'pass', 'reason': 42},
      );

      expect(request.toolCallId, 'python-call');
      expect(request.toolName, 'run_python_script');
      expect(request.reason, '42');
      expect(request.attempt.owner, ownerA);
      expect(request.attempt.toolCallId, 'python-call');
      expect(request.attempt.toolName, 'run_python_script');
      for (final values in [(' ', 'run_python_script'), ('call', '\n')]) {
        expect(
          () => _request(ownerA, toolCallId: values.$1, toolName: values.$2),
          throwsArgumentError,
        );
      }
    });

    test('rejects mutable values and mutable nested map keys', () {
      expect(
        () => _request(
          ownerA,
          arguments: {'code': 'pass', 'mutable': _MutableValue()},
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          ownerA,
          arguments: {
            'code': 'pass',
            'notJson': <Object?>{'value'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          ownerA,
          arguments: {'code': 'pass', 'notFinite': double.nan},
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          ownerA,
          arguments: {
            'code': 'pass',
            'nested': {_MutableValue(): true},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => PythonStagedInputs(workingDirectory: ' ', inputs: const []),
        throwsArgumentError,
      );
      expect(
        PythonStagedInputs(
          workingDirectory: ' /tmp/python-owner-a ',
          inputs: const [],
        ).workingDirectory,
        '/tmp/python-owner-a',
      );
    });
  });

  group('PythonScriptToolHandler validation and selection', () {
    test('rejects a non-canonical tool before any side effect', () async {
      final fixture = _fixture();

      final result = await fixture.handler.handle(
        _request(ownerA, toolName: 'local_execute_command'),
      );

      expect(result.toolName, 'local_execute_command');
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'Unsupported Python tool');
      expect(fixture.events, isEmpty);
    });

    test('maps missing and empty code to the exact recovery error', () async {
      for (final arguments in [
        <String, dynamic>{},
        <String, dynamic>{'code': null},
        <String, dynamic>{'code': '   '},
      ]) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(
          _request(ownerA, arguments: arguments),
        );

        expect(result.toolName, 'run_python_script');
        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, PythonScriptToolHandler.missingCodeMessage);
        expect(fixture.events, isEmpty);
      }
    });

    test('stages no attachment for non-attachment owner messages', () async {
      final fixture = _fixture();
      final messages = [
        _message(id: 'system', role: MessageRole.system),
        _message(id: 'user-plain', role: MessageRole.user),
        _message(
          id: 'assistant-image',
          role: MessageRole.assistant,
          imageBase64: 'assistant-base64',
        ),
      ];

      final result = await fixture.handler.handle(
        _request(ownerA, messages: messages),
      );

      expect(result.isSuccess, isTrue);
      expect(fixture.staging.calls.single.attempt.owner, ownerA);
      expect(fixture.staging.calls.single.attachment, isNull);
      final execution = fixture.execution.calls.single.request;
      expect(execution.arguments['working_directory'], '/tmp/python-default');
      expect(execution.arguments['inputs'], isEmpty);
      expect(execution.arguments, isNot(contains('timeout_seconds')));
      expect(execution.directoryIdentity.canonicalPath, '/tmp/python-default');
      expect(
        execution.directoryIdentity.markerNonce,
        'marker-conversation-a-python-call-owner-a',
      );
    });

    test('selects a user attachment past newer ineligible messages', () async {
      final fixture = _fixture();
      final messages = [
        _message(
          id: 'eligible-user',
          role: MessageRole.user,
          originalImagePath: '/owner/a/photo.jpg',
          originalImageMimeType: 'image/jpeg',
        ),
        _message(id: 'newer-user-plain', role: MessageRole.user),
        _message(
          id: 'newest-assistant-image',
          role: MessageRole.assistant,
          imageBase64: 'assistant-base64',
        ),
      ];

      await fixture.handler.handle(_request(ownerA, messages: messages));

      final attachment = fixture.staging.calls.single.attachment!;
      expect(attachment.messageId, 'eligible-user');
      expect(attachment.originalImagePath, '/owner/a/photo.jpg');
      expect(attachment.originalImageMimeType, 'image/jpeg');
      expect(attachment.imageBase64, isNull);
    });

    test('selects only the latest of multiple eligible user inputs', () async {
      final fixture = _fixture();
      final messages = [
        _message(
          id: 'older-path',
          role: MessageRole.user,
          originalImagePath: '/owner/a/older.jpg',
        ),
        _message(
          id: 'latest-upload',
          role: MessageRole.user,
          imageBase64: 'latest-base64',
          imageMimeType: 'image/webp',
        ),
      ];

      await fixture.handler.handle(_request(ownerA, messages: messages));

      final attachment = fixture.staging.calls.single.attachment!;
      expect(attachment.messageId, 'latest-upload');
      expect(attachment.imageBase64, 'latest-base64');
      expect(attachment.imageMimeType, 'image/webp');
      expect(attachment.originalImagePath, isNull);
    });

    test('does not read a newer visible conversation attachment', () async {
      final fixture = _fixture();
      final ownerMessages = <Message>[
        _message(
          id: 'owner-a-attachment',
          role: MessageRole.user,
          imageBase64: 'owner-a-base64',
        ),
      ];
      final ownerSnapshot = PythonOwnerMessageSnapshot(
        owner: ownerA,
        messages: ownerMessages,
      );
      final request = PythonScriptToolRequest(
        owner: ownerA,
        toolCallId: 'python-call-owner-a',
        toolName: 'run_python_script',
        ownerMessages: ownerSnapshot,
        arguments: const {'code': 'print(len(caverno.inputs))'},
      );
      final visibleConversationMessages = <Message>[
        _message(
          id: 'visible-owner-b-attachment',
          role: MessageRole.user,
          imageBase64: 'owner-b-base64',
        ),
      ];
      visibleConversationMessages.add(
        _message(
          id: 'visible-owner-b-newer',
          role: MessageRole.user,
          originalImagePath: '/owner/b/private.png',
        ),
      );
      ownerMessages.addAll(visibleConversationMessages);

      await fixture.handler.handle(request);

      final staged = fixture.staging.calls.single;
      expect(staged.attempt.owner, ownerA);
      expect(staged.attachment?.messageId, 'owner-a-attachment');
      expect(staged.attachment?.imageBase64, 'owner-a-base64');
      expect(staged.attachment?.originalImagePath, isNull);
      expect(fixture.staging.owners.toSet(), {ownerA});
      expect(fixture.execution.owners.toSet(), {ownerA});
      expect(fixture.approval.owners.toSet(), {ownerA});
    });
  });

  group('PythonScriptToolHandler staging and execution', () {
    test('recursively freezes staged inputs before execution', () async {
      final tags = <Object?>['owner-a'];
      final nested = <String, dynamic>{'tags': tags};
      final sourceInput = <String, dynamic>{
        'name': 'attachment_0.jpg',
        'path': '/tmp/python-owner-a/attachment_0.jpg',
        'mime': 'image/jpeg',
        'metadata': nested,
      };
      final staged = PythonStagedInputs(
        workingDirectory: '/tmp/python-owner-a',
        inputs: [sourceInput],
      );
      final fixture = _fixture();
      fixture.staging.results[ownerA] = staged;

      sourceInput['path'] = '/owner/b/private.jpg';
      tags.add('poisoned');
      nested['tags'] = ['replaced'];

      await fixture.handler.handle(_request(ownerA));

      expect(
        staged.inputs.single['path'],
        '/tmp/python-owner-a/attachment_0.jpg',
      );
      expect(staged.inputs.single['metadata'], {
        'tags': ['owner-a'],
      });
      final executionInputs =
          fixture.execution.calls.single.request.arguments['inputs'] as List;
      expect(executionInputs.single, {
        'name': 'attachment_0.jpg',
        'path': '/tmp/python-owner-a/attachment_0.jpg',
        'mime': 'image/jpeg',
        'metadata': {
          'tags': ['owner-a'],
        },
      });
      expect(
        () => staged.inputs.single['path'] = '/late',
        throwsUnsupportedError,
      );
      expect(
        () => (executionInputs.single as Map)['path'] = '/late',
        throwsUnsupportedError,
      );
    });

    test('preserves present timeout values and omits absent timeout', () async {
      for (final timeout in <Object>[1, 30.5, -4, 100000]) {
        final fixture = _fixture();

        await fixture.handler.handle(
          _request(
            ownerA,
            arguments: {
              'code': '  print("timeout")  ',
              'timeout_seconds': timeout,
            },
          ),
        );

        final execution = fixture.execution.calls.single.request;
        expect(execution.code, 'print("timeout")');
        expect(execution.arguments['timeout_seconds'], same(timeout));
      }

      final absentFixture = _fixture();
      await absentFixture.handler.handle(_request(ownerA));
      expect(
        absentFixture.execution.calls.single.request.arguments,
        isNot(contains('timeout_seconds')),
      );
    });

    test('passes through exact success, failure, and timeout payloads', () async {
      const results = [
        McpToolResult(
          toolName: 'run_python_script',
          result:
              '{"language":"python","stdout":"ok\\n","stderr":"","result":{"count":1}}',
          isSuccess: true,
        ),
        McpToolResult(
          toolName: 'run_python_script',
          result:
              '{"language":"python","stdout":"","stderr":"","error":"ValueError: boom","traceback":"trace"}',
          isSuccess: true,
        ),
        McpToolResult(
          toolName: 'run_python_script',
          result:
              '{"language":"python","stdout":"","stderr":"","error":"python_worker_timeout","timed_out":true}',
          isSuccess: true,
        ),
      ];
      for (final expected in results) {
        final fixture = _fixture();
        fixture.execution.results[ownerA] = expected;

        final actual = await fixture.handler.handle(_request(ownerA));

        expect(actual, same(expected));
        expect(
          fixture.approval.rememberedResults.single.result,
          same(expected),
        );
      }
    });

    test('preserves the disabled-runtime failure exactly', () async {
      const unavailable = McpToolResult(
        toolName: 'run_python_script',
        result: '',
        isSuccess: false,
        errorMessage: 'Python runtime is not available',
      );
      final fixture = _fixture();
      fixture.execution.results[ownerA] = unavailable;

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result, same(unavailable));
      expect(result.result, isEmpty);
      expect(result.errorMessage, 'Python runtime is not available');
      expect(fixture.approval.rememberedResults.single.result, same(result));
    });

    test('maps unexpected execution errors to effect uncertainty', () async {
      final fixture = _fixture();
      fixture.execution.errors[ownerA] = StateError('runtime transport failed');

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('possible side effects'));
      expect(fixture.approval.rememberedResults, isEmpty);
      expect(fixture.staging.releaseCalls, hasLength(1));
    });

    test('propagates staging errors before approval or execution', () async {
      final fixture = _fixture();
      fixture.staging.errors[ownerA] = StateError('attachment staging failed');

      await expectLater(
        fixture.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'attachment staging failed',
          ),
        ),
      );

      expect(fixture.approval.gateRequests, isEmpty);
      expect(fixture.approval.manualRequests, isEmpty);
      expect(fixture.approval.rememberedResults, isEmpty);
      expect(fixture.execution.calls, isEmpty);
      expect(fixture.staging.releaseCalls, isEmpty);
    });
  });

  group('PythonScriptToolHandler exact completion fencing', () {
    test('rejects a staging completion from another owner', () async {
      final fixture = _fixture()
        ..staging.completionOverride = PythonScriptCompletion.completed(
          owner: ownerB,
          toolCallId: 'python-call-owner-a',
          toolName: 'run_python_script',
          value: null,
        );

      await expectLater(
        fixture.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Python input staging owner mismatch.',
          ),
        ),
      );
      expect(fixture.approval.gateRequests, isEmpty);
      expect(fixture.execution.calls, isEmpty);
    });

    test('rejects gate and manual completions from another call', () async {
      final gateFixture = _fixture()
        ..approval.gateCompletionOverride = PythonScriptCompletion.completed(
          owner: ownerA,
          toolCallId: 'poisoned-call',
          toolName: 'run_python_script',
          value: ToolApprovalGateDecision.autoReviewAllowed,
        );
      await expectLater(
        gateFixture.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Python approval gate tool call mismatch.',
          ),
        ),
      );

      final manualFixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.needsManualApproval
        ..approval.manualCompletionOverride = PythonScriptCompletion.completed(
          owner: ownerA,
          toolCallId: 'python-call-owner-a',
          toolName: 'read_file',
          value: true,
        );
      await expectLater(
        manualFixture.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Python manual approval tool name mismatch.',
          ),
        ),
      );
      expect(manualFixture.execution.calls, isEmpty);
    });

    test('maps an expired execution without caching success', () async {
      final fixture = _fixture()
        ..execution.completionOverride = PythonScriptCompletion.ownerExpired(
          owner: ownerA,
          toolCallId: 'python-call-owner-a',
          toolName: 'run_python_script',
        );

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('possible side effects'));
      expect(fixture.approval.rememberedResults, isEmpty);
    });

    test('maps a poisoned execution result to effect uncertainty', () async {
      final fixture = _fixture()
        ..execution.results[ownerA] = const McpToolResult(
          toolName: 'read_file',
          result: '{}',
          isSuccess: true,
        );

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('possible side effects'));
      expect(fixture.approval.rememberedResults, isEmpty);
    });

    test('requires exact successful cleanup after a terminal result', () async {
      final fixture = _fixture()
        ..staging.releaseCompletionOverride =
            PythonScriptCompletion.ownerExpired(
              owner: ownerA,
              toolCallId: 'python-call-owner-a',
              toolName: 'run_python_script',
            );

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('possible side effects'));
      expect(fixture.staging.releaseCalls, hasLength(1));
    });

    test('does not settle a cleanup identity mismatch', () async {
      final fixture = _fixture()
        ..staging.releaseCompletionOverride = PythonScriptCompletion.completed(
          owner: ownerA,
          toolCallId: 'python-call-owner-a',
          toolName: 'run_python_script',
          value: PythonStagingCleanupOutcome.identityMismatch,
        );

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('possible side effects'));
      expect(fixture.stagingLeases.pendingCleanupAttempts, [
        _request(ownerA).attempt,
      ]);
    });
  });

  group('PythonScriptToolHandler staging ownership', () {
    test('releases an allocation when staging throws afterward', () async {
      final fixture = _fixture();
      fixture.staging.errorsAfterAllocation[ownerA] = StateError(
        'staging failed after allocation',
      );

      await expectLater(
        fixture.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'staging failed after allocation',
          ),
        ),
      );

      final released = fixture.staging.releaseCalls.single.claim.lease;
      expect(released.attempt, _request(ownerA).attempt);
      expect(released.directoryIdentity.markerNonce, isNotEmpty);
      expect(fixture.execution.calls, isEmpty);
    });

    test('keeps the lease until execution has settled', () async {
      final executionGate = Completer<void>();
      final fixture = _fixture();
      fixture.execution.beforeReturn = (_) => executionGate.future;

      final pending = fixture.handler.handle(_request(ownerA));
      await Future<void>.delayed(Duration.zero);

      expect(fixture.execution.calls, hasLength(1));
      expect(fixture.staging.releaseCalls, isEmpty);

      executionGate.complete();
      expect((await pending).isSuccess, isTrue);
      expect(fixture.staging.releaseCalls, hasLength(1));
    });

    test('rejects duplicate and late allocations with port cleanup', () async {
      final duplicateFixture = _fixture()..staging.allocateTwice = true;
      await expectLater(
        duplicateFixture.handler.handle(_request(ownerA)),
        throwsA(isA<StateError>()),
      );
      expect(duplicateFixture.staging.portCleanups, hasLength(1));
      expect(duplicateFixture.staging.releaseCalls, hasLength(1));

      final lateFixture = _fixture()..staging.allocateAfterSettlement = true;
      expect(
        (await lateFixture.handler.handle(_request(ownerA))).isSuccess,
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        lateFixture.staging.lateAcknowledgements.single.disposition,
        PythonStagingAllocationDisposition.rejectedPortCleanup,
      );
      expect(
        lateFixture.staging.portCleanups.single.stagedInputs.workingDirectory,
        '/tmp/python-late',
      );
    });

    test('makes owner-clear cleanup exclusive after allocation', () async {
      final fixture = _fixture();
      fixture.staging.afterAllocated = (_) async {
        final cleared = fixture.stagingLeases.clearOwner(ownerA);
        final claim = cleared.cleanupClaims.single;
        await fixture.staging.release(claim);
        expect(
          fixture.stagingLeases.settleCleanup(claim: claim, succeeded: true),
          PythonStagingCleanupSettleStatus.settled,
        );
      };

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('expired before execution'));
      expect(fixture.staging.releaseCalls, hasLength(1));
      expect(fixture.execution.calls, isEmpty);
    });

    test('reopens a failed cleanup for an exact retry', () async {
      final fixture = _fixture()
        ..staging.releaseError = StateError('delete failed');

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('possible side effects'));
      final stageCall = fixture.staging.calls.single;
      final retry = fixture.stagingLeases.claimPendingCleanup(owner: ownerA);
      expect(retry.status, PythonStagingCleanupClaimStatus.claimed);
      expect(retry.claim!.lease.token, same(stageCall.token));
      fixture.staging.releaseError = null;
      await fixture.staging.release(retry.claim!);
      expect(
        fixture.stagingLeases.settleCleanup(
          claim: retry.claim!,
          succeeded: true,
        ),
        PythonStagingCleanupSettleStatus.settled,
      );
    });
  });

  group('PythonScriptToolHandler cache and expiry fencing', () {
    test('lets initial expiry win over a cached denial', () async {
      const cached = McpToolResult(
        toolName: 'run_python_script',
        result: '',
        isSuccess: false,
        errorMessage: 'cached denial',
      );
      const expired = McpToolResult(
        toolName: 'run_python_script',
        result: '',
        isSuccess: false,
        errorMessage: 'owner expired',
      );
      final fixture = _fixture();
      fixture.approval.cachedDenials[ownerA] = cached;
      fixture.approval.enqueueExpiry(ownerA, expired);

      expect(await fixture.handler.handle(_request(ownerA)), same(expired));
      expect(fixture.approval.lookups, isEmpty);
      expect(fixture.staging.calls, isEmpty);
    });

    test('rejects poisoned denial-cache completions before staging', () async {
      final wrongCall = _fixture()
        ..approval.lookupCompletionOverride = PythonScriptCompletion.completed(
          owner: ownerA,
          toolCallId: 'poisoned-call',
          toolName: 'run_python_script',
          value: null,
        );
      await expectLater(
        wrongCall.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Python denial cache lookup tool call mismatch.',
          ),
        ),
      );
      expect(wrongCall.staging.calls, isEmpty);

      final wrongTool = _fixture()
        ..approval.lookupCompletionOverride = PythonScriptCompletion.completed(
          owner: ownerA,
          toolCallId: 'python-call-owner-a',
          toolName: 'run_python_script',
          value: const McpToolResult(
            toolName: 'read_file',
            result: '{}',
            isSuccess: true,
          ),
        );
      await expectLater(
        wrongTool.handler.handle(_request(ownerA)),
        throwsA(isA<StateError>()),
      );
      expect(wrongTool.staging.calls, isEmpty);
    });

    test('does not let cache callbacks substitute terminal results', () async {
      const poison = McpToolResult(
        toolName: 'read_file',
        result: 'poison',
        isSuccess: true,
      );
      const executionResult = McpToolResult(
        toolName: 'run_python_script',
        result: 'trusted execution',
        isSuccess: true,
      );
      final resultFixture = _fixture()
        ..approval.rememberResultCompletionOverride =
            PythonScriptCompletion.completed(
              owner: ownerA,
              toolCallId: 'python-call-owner-a',
              toolName: 'run_python_script',
              value: poison,
            )
        ..execution.results[ownerA] = executionResult;
      final result = await resultFixture.handler.handle(_request(ownerA));
      expect(result, same(executionResult));
      expect(result.toolName, 'run_python_script');

      final denialFixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.denied('blocked')
        ..approval.rememberDenialCompletionOverride =
            PythonScriptCompletion.completed(
              owner: ownerA,
              toolCallId: 'python-call-owner-a',
              toolName: 'run_python_script',
              value: poison,
            );
      final denial = await denialFixture.handler.handle(_request(ownerA));
      expect(denial.toolName, 'run_python_script');
      expect(denial.errorMessage, 'Auto-review denied: blocked');
    });

    test('maps post-execution cache identity poison to uncertainty', () async {
      final fixture = _fixture()
        ..approval.rememberResultCompletionOverride =
            PythonScriptCompletion.completed(
              owner: ownerA,
              toolCallId: 'poisoned-call',
              toolName: 'run_python_script',
              value: null,
            );

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('possible side effects'));
      expect(fixture.execution.calls, hasLength(1));
      expect(fixture.staging.releaseCalls, hasLength(1));
    });

    test('maps owner clear during execution to uncertainty', () async {
      final fixture = _fixture();
      fixture.execution.beforeReturn = (_) async {
        final cleared = fixture.stagingLeases.clearOwner(ownerA);
        final claim = cleared.cleanupClaims.single;
        await fixture.staging.release(claim);
        fixture.stagingLeases.settleCleanup(claim: claim, succeeded: true);
      };

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('possible side effects'));
      expect(fixture.approval.rememberedResults, isEmpty);
      expect(fixture.staging.releaseCalls, hasLength(1));
    });

    test('rejects a tombstoned owner before staging', () async {
      final fixture = _fixture();
      fixture.stagingLeases.clearOwner(ownerA);

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('expired before execution'));
      expect(fixture.staging.calls, isEmpty);
      expect(fixture.execution.calls, isEmpty);
    });

    test('maps owner expiry at every pre-effect acknowledgement', () async {
      final initialFixture = _fixture();
      initialFixture.approval.expirations.add(
        PythonScriptCompletion.ownerExpired(
          owner: ownerA,
          toolCallId: 'python-call-owner-a',
          toolName: 'run_python_script',
        ),
      );
      expect(
        (await initialFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );

      final lookupFixture = _fixture()
        ..approval.lookupCompletionOverride =
            PythonScriptCompletion.ownerExpired(
              owner: ownerA,
              toolCallId: 'python-call-owner-a',
              toolName: 'run_python_script',
            );
      expect(
        (await lookupFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );

      final stagingFixture = _fixture()
        ..staging.completionOverride = PythonScriptCompletion.ownerExpired(
          owner: ownerA,
          toolCallId: 'python-call-owner-a',
          toolName: 'run_python_script',
        );
      expect(
        (await stagingFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );

      final gateFixture = _fixture()
        ..approval.gateCompletionOverride = PythonScriptCompletion.ownerExpired(
          owner: ownerA,
          toolCallId: 'python-call-owner-a',
          toolName: 'run_python_script',
        );
      expect(
        (await gateFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );

      final manualFixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.needsManualApproval
        ..approval.manualCompletionOverride =
            PythonScriptCompletion.ownerExpired(
              owner: ownerA,
              toolCallId: 'python-call-owner-a',
              toolName: 'run_python_script',
            );
      expect(
        (await manualFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );
    });

    test('rejects conflicting and incomplete staging allocations', () async {
      final conflictFixture = _fixture();
      conflictFixture.stagingLeases.reserve(_request(ownerA).attempt);
      expect(
        (await conflictFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('already active'),
      );

      final missingFixture = _fixture()..staging.skipAllocationCallback = true;
      await expectLater(
        missingFixture.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('settled before reporting'),
          ),
        ),
      );

      final repeatedFixture = _fixture()
        ..staging.allocateTwice = true
        ..staging.repeatExactAllocation = true;
      await expectLater(
        repeatedFixture.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('more than one allocation'),
          ),
        ),
      );
    });

    test('rechecks owner and lease before each execution boundary', () async {
      Future<void> retireOwner(_Fixture fixture) async {
        final cleared = fixture.stagingLeases.clearOwner(ownerA);
        final claim = cleared.cleanupClaims.single;
        await fixture.staging.release(claim);
        expect(
          fixture.stagingLeases.settleCleanup(claim: claim, succeeded: true),
          PythonStagingCleanupSettleStatus.settled,
        );
      }

      final gateFixture = _fixture();
      gateFixture.approval.afterGate = (_) => retireOwner(gateFixture);
      expect(
        (await gateFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );

      final manualFixture = _fixture();
      manualFixture.approval.gates[ownerA] =
          ToolApprovalGateDecision.needsManualApproval;
      manualFixture.approval.afterManual = (_) => retireOwner(manualFixture);
      expect(
        (await manualFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );

      final expiredProbe = _fixture();
      expiredProbe.approval
        ..enqueueExpiry(ownerA, null)
        ..expirations.add(
          PythonScriptCompletion.ownerExpired(
            owner: ownerA,
            toolCallId: 'python-call-owner-a',
            toolName: 'run_python_script',
          ),
        );
      expect(
        (await expiredProbe.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );

      const expired = McpToolResult(
        toolName: 'run_python_script',
        result: '',
        isSuccess: false,
        errorMessage: 'owner expired at an exact boundary',
      );
      final beforeExecution = _fixture();
      beforeExecution.approval
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, expired);
      expect(
        await beforeExecution.handler.handle(_request(ownerA)),
        same(expired),
      );

      final afterExecution = _fixture();
      afterExecution.approval
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, expired);
      expect(
        (await afterExecution.handler.handle(_request(ownerA))).errorMessage,
        contains('possible side effects'),
      );

      final beforeCache = _fixture();
      beforeCache.approval
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, null)
        ..enqueueExpiry(ownerA, expired);
      expect(
        (await beforeCache.handler.handle(_request(ownerA))).errorMessage,
        contains('possible side effects'),
      );
    });

    test('maps expired result and denial cache writes', () async {
      final resultFixture = _fixture()
        ..approval.rememberResultCompletionOverride =
            PythonScriptCompletion.ownerExpired(
              owner: ownerA,
              toolCallId: 'python-call-owner-a',
              toolName: 'run_python_script',
            );
      expect(
        (await resultFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('possible side effects'),
      );

      final denialFixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.denied('blocked')
        ..approval.rememberDenialCompletionOverride =
            PythonScriptCompletion.ownerExpired(
              owner: ownerA,
              toolCallId: 'python-call-owner-a',
              toolName: 'run_python_script',
            );
      expect(
        (await denialFixture.handler.handle(_request(ownerA))).errorMessage,
        contains('expired before execution'),
      );
    });

    test('fences owner retirement before and during staging commit', () async {
      final fixture = _fixture();
      fixture.staging.beforeAllocated = (_) {
        fixture.stagingLeases.clearOwner(ownerA);
      };

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.errorMessage, contains('expired before execution'));
      expect(fixture.execution.calls, isEmpty);
      expect(fixture.staging.releaseCalls, hasLength(1));
    });

    test('surfaces pre-effect cleanup and settlement races', () async {
      final releaseFailure = _fixture()
        ..approval.gateCompletionOverride = PythonScriptCompletion.ownerExpired(
          owner: ownerA,
          toolCallId: 'python-call-owner-a',
          toolName: 'run_python_script',
        )
        ..staging.releaseError = StateError('cleanup failed before execution');
      await expectLater(
        releaseFailure.handler.handle(_request(ownerA)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'cleanup failed before execution',
          ),
        ),
      );

      final settlementRace = _fixture();
      settlementRace.staging.beforeReleaseCompletion = (claim) {
        expect(
          settlementRace.stagingLeases.settleCleanup(
            claim: claim,
            succeeded: true,
          ),
          PythonStagingCleanupSettleStatus.settled,
        );
      };
      expect(
        (await settlementRace.handler.handle(_request(ownerA))).errorMessage,
        contains('possible side effects'),
      );
    });
  });

  group('PythonScriptToolHandler approvals', () {
    test('returns cached denial before staging', () async {
      const cached = McpToolResult(
        toolName: 'run_python_script',
        result: '',
        isSuccess: false,
        errorMessage: 'cached Python denial',
      );
      final fixture = _fixture();
      fixture.approval.cachedDenials[ownerA] = cached;

      final result = await fixture.handler.handle(
        _request(
          ownerA,
          arguments: const {
            'code': '  print("same key")  ',
            'reason': 'This must not change the cache key.',
          },
        ),
      );

      expect(result, same(cached));
      expect(fixture.approval.lookups.single.key.cacheArguments, {
        'code': 'print("same key")',
      });
      expect(fixture.staging.calls, isEmpty);
    });

    test('stages before exact auto-review and manual denial mapping', () async {
      final autoFixture = _fixture();
      autoFixture.approval.gates[ownerA] = ToolApprovalGateDecision.denied(
        'script is unsafe',
      );
      final autoDenied = await autoFixture.handler.handle(_request(ownerA));
      expect(
        autoDenied.result,
        'Auto-review denied this action. Rationale: script is unsafe',
      );
      expect(autoDenied.errorMessage, 'Auto-review denied: script is unsafe');
      expect(autoFixture.execution.calls, isEmpty);
      expect(
        autoFixture.approval.rememberedDenials.single.result,
        same(autoDenied),
      );

      final manualFixture = _fixture();
      manualFixture.approval.gates[ownerA] =
          ToolApprovalGateDecision.needsManualApproval;
      manualFixture.approval.manualDecisions[ownerA] = false;
      final manualDenied = await manualFixture.handler.handle(_request(ownerA));
      expect(manualDenied.errorMessage, 'User denied Python script execution');
      expect(manualFixture.execution.calls, isEmpty);
      expect(
        manualFixture.events.indexOf('staging.stage:conversation-a:8'),
        lessThan(
          manualFixture.events.indexOf('approval.resolve:conversation-a:8'),
        ),
      );
    });

    test('supports manual allow, expiration, and full-access bypass', () async {
      final manualFixture = _fixture();
      manualFixture.approval.gates[ownerA] =
          ToolApprovalGateDecision.needsManualApproval;
      final manualResult = await manualFixture.handler.handle(_request(ownerA));
      expect(manualResult.isSuccess, isTrue);
      final manualRequest =
          manualFixture.approval.manualRequests.single.request;
      expect(manualRequest.toolCallId, 'python-call-owner-a');
      expect(manualRequest.code, 'print("ok")');
      expect(manualRequest.reason, 'Run the owner script.');
      expect(
        manualRequest.stagedInputs.workingDirectory,
        '/tmp/python-default',
      );

      const expired = McpToolResult(
        toolName: 'run_python_script',
        result: '',
        isSuccess: false,
        errorMessage: 'The approval turn expired before execution',
      );
      final expiredFixture = _fixture();
      expiredFixture.approval.enqueueExpiry(ownerA, expired);
      expect(
        await expiredFixture.handler.handle(_request(ownerA)),
        same(expired),
      );
      expect(expiredFixture.execution.calls, isEmpty);

      final directFixture = _fixture();
      directFixture.approval.gates[ownerA] =
          ToolApprovalGateDecision.fullAccess;
      final direct = await directFixture.handler.handle(_request(ownerA));
      expect(direct.isSuccess, isTrue);
      expect(directFixture.approval.rememberedResults, isEmpty);
    });
  });
}

Message _message({
  required String id,
  required MessageRole role,
  String? imageBase64,
  String? imageMimeType,
  String? originalImagePath,
  String? originalImageMimeType,
}) {
  return Message(
    id: id,
    content: id,
    role: role,
    timestamp: DateTime.utc(2026, 7, 30),
    imageBase64: imageBase64,
    imageMimeType: imageMimeType,
    originalImagePath: originalImagePath,
    originalImageMimeType: originalImageMimeType,
  );
}

PythonScriptToolRequest _request(
  ChatTurnOwner owner, {
  List<Message> messages = const [],
  String toolCallId = 'python-call-owner-a',
  String toolName = 'run_python_script',
  Map<String, dynamic> arguments = const {
    'code': 'print("ok")',
    'reason': 'Run the owner script.',
  },
}) {
  return PythonScriptToolRequest(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
    ownerMessages: PythonOwnerMessageSnapshot(owner: owner, messages: messages),
    arguments: arguments,
  );
}

typedef _Fixture = ({
  PythonScriptToolHandler handler,
  _StagingPort staging,
  _ExecutionPort execution,
  _ApprovalPort approval,
  PythonStagingLeaseRegistry stagingLeases,
  List<String> events,
});

_Fixture _fixture() {
  final events = <String>[];
  final staging = _StagingPort(events);
  final execution = _ExecutionPort(events);
  final approval = _ApprovalPort(events);
  final stagingLeases = PythonStagingLeaseRegistry();
  return (
    handler: PythonScriptToolHandler(
      stagingPort: staging,
      executionPort: execution,
      approvalPort: approval,
      stagingLeases: stagingLeases,
    ),
    staging: staging,
    execution: execution,
    approval: approval,
    stagingLeases: stagingLeases,
    events: events,
  );
}

typedef _StageCall = ({
  PythonStagingAttempt attempt,
  PythonStagingLeaseToken token,
  PythonInputAttachment? attachment,
});
typedef _ReleaseCall = ({PythonStagingCleanupClaim claim});

final class _StagingPort implements PythonInputStagingPort {
  _StagingPort(this.events);

  final List<String> events;
  final Map<ChatTurnOwner, PythonStagedInputs> results = {};
  final Map<ChatTurnOwner, Object> errors = {};
  final List<_StageCall> calls = [];
  final List<_ReleaseCall> releaseCalls = [];
  final List<PythonStagingAllocation> portCleanups = [];
  final List<PythonStagingAllocationAcknowledgement> lateAcknowledgements = [];
  PythonScriptCompletion<Object?>? completionOverride;
  PythonScriptCompletion<PythonStagingCleanupOutcome>?
  releaseCompletionOverride;
  FutureOr<void> Function(PythonStagingAttempt attempt)? afterAllocated;
  PythonStagedInputs? secondAllocation;
  bool allocateTwice = false;
  bool repeatExactAllocation = false;
  bool allocateAfterSettlement = false;
  bool skipAllocationCallback = false;
  Object? releaseError;
  FutureOr<void> Function(PythonStagingAttempt attempt)? beforeAllocated;
  void Function(PythonStagingCleanupClaim claim)? beforeReleaseCompletion;
  final Map<ChatTurnOwner, Object> errorsAfterAllocation = {};

  List<ChatTurnOwner> get owners =>
      calls.map((call) => call.attempt.owner).toList();

  @override
  Future<PythonScriptCompletion<Object?>> stage(
    PythonStagingAttempt attempt,
    PythonStagingLeaseToken token,
    PythonInputAttachment? attachment,
    PythonStagingAllocationCallback onAllocated,
  ) async {
    events.add(_event('staging.stage', attempt.owner));
    calls.add((attempt: attempt, token: token, attachment: attachment));
    final error = errors[attempt.owner];
    if (error != null) {
      throw error;
    }
    final staged =
        results[attempt.owner] ??
        PythonStagedInputs(
          workingDirectory: '/tmp/python-default',
          inputs: const [],
        );
    final allocation = _allocation(
      staged,
      markerNonce:
          'marker-${attempt.owner.conversationId}-${attempt.toolCallId}',
    );
    if (beforeAllocated case final callback?) await callback(attempt);
    if (!skipAllocationCallback) {
      final acknowledgement = onAllocated(allocation);
      if (acknowledgement.portMustCleanup) portCleanups.add(allocation);
    }
    if (afterAllocated case final callback?) await callback(attempt);
    final lateError = errorsAfterAllocation[attempt.owner];
    if (lateError != null) throw lateError;
    if (allocateTwice) {
      final second = repeatExactAllocation
          ? allocation
          : _allocation(
              secondAllocation ??
                  PythonStagedInputs(
                    workingDirectory: '/tmp/python-second',
                    inputs: const [],
                  ),
              markerNonce: 'marker-second-${attempt.toolCallId}',
            );
      final acknowledgement = onAllocated(second);
      if (acknowledgement.portMustCleanup) portCleanups.add(second);
    }
    if (completionOverride case final completion?) return completion;
    final completion = PythonScriptCompletion.completed(
      owner: attempt.owner,
      toolCallId: attempt.toolCallId,
      toolName: attempt.toolName,
      value: null,
    );
    if (allocateAfterSettlement) {
      Timer.run(() {
        final late = _allocation(
          PythonStagedInputs(
            workingDirectory: '/tmp/python-late',
            inputs: const [],
          ),
          markerNonce: 'marker-late-${attempt.toolCallId}',
        );
        final acknowledgement = onAllocated(late);
        lateAcknowledgements.add(acknowledgement);
        if (acknowledgement.portMustCleanup) portCleanups.add(late);
      });
    }
    return completion;
  }

  @override
  Future<PythonScriptCompletion<PythonStagingCleanupOutcome>> release(
    PythonStagingCleanupClaim claim,
  ) async {
    final lease = claim.lease;
    final attempt = lease.attempt;
    events.add(_event('staging.release', attempt.owner));
    releaseCalls.add((claim: claim));
    if (releaseError case final error?) throw error;
    beforeReleaseCompletion?.call(claim);
    return releaseCompletionOverride ??
        PythonScriptCompletion.completed(
          owner: attempt.owner,
          toolCallId: attempt.toolCallId,
          toolName: attempt.toolName,
          value: PythonStagingCleanupOutcome.deleted,
        );
  }
}

typedef _ExecutionCall = ({
  PythonStagingAttempt attempt,
  PythonScriptExecutionRequest request,
});

final class _ExecutionPort implements PythonScriptExecutionPort {
  _ExecutionPort(this.events);

  final List<String> events;
  final Map<ChatTurnOwner, McpToolResult> results = {};
  final Map<ChatTurnOwner, Object> errors = {};
  final List<_ExecutionCall> calls = [];
  PythonScriptCompletion<McpToolResult>? completionOverride;
  FutureOr<void> Function(PythonStagingAttempt attempt)? beforeReturn;

  List<ChatTurnOwner> get owners =>
      calls.map((call) => call.attempt.owner).toList();

  @override
  Future<PythonScriptCompletion<McpToolResult>> execute(
    PythonStagingAttempt attempt,
    PythonScriptExecutionRequest request,
  ) async {
    events.add(_event('execution.execute', attempt.owner));
    calls.add((attempt: attempt, request: request));
    final error = errors[attempt.owner];
    if (error != null) {
      throw error;
    }
    if (beforeReturn case final callback?) await callback(attempt);
    if (completionOverride case final completion?) return completion;
    return PythonScriptCompletion.completed(
      owner: attempt.owner,
      toolCallId: attempt.toolCallId,
      toolName: attempt.toolName,
      value:
          results[attempt.owner] ??
          const McpToolResult(
            toolName: 'run_python_script',
            result: '{"language":"python","stdout":"ok\\n","stderr":""}',
            isSuccess: true,
          ),
    );
  }
}

typedef _ApprovalLookup = ({
  PythonStagingAttempt attempt,
  PythonScriptApprovalKey key,
});
typedef _ApprovalRequestUse = ({
  PythonStagingAttempt attempt,
  PythonScriptApprovalRequest request,
});
typedef _RememberedResult = ({
  PythonStagingAttempt attempt,
  PythonScriptApprovalKey key,
  McpToolResult result,
});

final class _ApprovalPort implements PythonScriptApprovalPort {
  _ApprovalPort(this.events);

  final List<String> events;
  final Map<ChatTurnOwner, McpToolResult> cachedDenials = {};
  final Map<ChatTurnOwner, ToolApprovalGateDecision> gates = {};
  final Map<ChatTurnOwner, bool> manualDecisions = {};
  final List<_ApprovalLookup> lookups = [];
  final List<_ApprovalRequestUse> gateRequests = [];
  final List<_ApprovalRequestUse> manualRequests = [];
  final List<_RememberedResult> rememberedDenials = [];
  final List<_RememberedResult> rememberedResults = [];
  final List<PythonStagingAttempt> expirationAttempts = [];
  final List<PythonScriptCompletion<McpToolResult?>> expirations = [];
  PythonScriptCompletion<McpToolResult?>? lookupCompletionOverride;
  PythonScriptCompletion<ToolApprovalGateDecision>? gateCompletionOverride;
  PythonScriptCompletion<bool>? manualCompletionOverride;
  PythonScriptCompletion<Object?>? rememberDenialCompletionOverride;
  PythonScriptCompletion<Object?>? rememberResultCompletionOverride;
  FutureOr<void> Function(PythonStagingAttempt attempt)? afterGate;
  FutureOr<void> Function(PythonStagingAttempt attempt)? afterManual;

  List<ChatTurnOwner> get owners => [
    ...lookups.map((entry) => entry.attempt.owner),
    ...gateRequests.map((entry) => entry.attempt.owner),
    ...manualRequests.map((entry) => entry.attempt.owner),
    ...rememberedDenials.map((entry) => entry.attempt.owner),
    ...rememberedResults.map((entry) => entry.attempt.owner),
    ...expirationAttempts.map((attempt) => attempt.owner),
  ];

  void enqueueExpiry(ChatTurnOwner owner, McpToolResult? result) {
    expirations.add(
      PythonScriptCompletion.completed(
        owner: owner,
        toolCallId: 'python-call-owner-a',
        toolName: 'run_python_script',
        value: result,
      ),
    );
  }

  @override
  PythonScriptCompletion<McpToolResult?> lookupDenial(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
  ) {
    events.add(_event('approval.lookup', attempt.owner));
    lookups.add((attempt: attempt, key: key));
    return lookupCompletionOverride ??
        PythonScriptCompletion.completed(
          owner: attempt.owner,
          toolCallId: attempt.toolCallId,
          toolName: attempt.toolName,
          value: cachedDenials[attempt.owner],
        );
  }

  @override
  Future<PythonScriptCompletion<ToolApprovalGateDecision>> resolveGate(
    PythonStagingAttempt attempt,
    PythonScriptApprovalRequest request,
  ) async {
    events.add(_event('approval.resolve', attempt.owner));
    gateRequests.add((attempt: attempt, request: request));
    if (gateCompletionOverride case final completion?) return completion;
    if (afterGate case final callback?) await callback(attempt);
    return PythonScriptCompletion.completed(
      owner: attempt.owner,
      toolCallId: attempt.toolCallId,
      toolName: attempt.toolName,
      value: gates[attempt.owner] ?? ToolApprovalGateDecision.autoReviewAllowed,
    );
  }

  @override
  Future<PythonScriptCompletion<bool>> requestManualApproval(
    PythonStagingAttempt attempt,
    PythonScriptApprovalRequest request,
  ) async {
    events.add(_event('approval.manual', attempt.owner));
    manualRequests.add((attempt: attempt, request: request));
    if (manualCompletionOverride case final completion?) return completion;
    if (afterManual case final callback?) await callback(attempt);
    return PythonScriptCompletion.completed(
      owner: attempt.owner,
      toolCallId: attempt.toolCallId,
      toolName: attempt.toolName,
      value: manualDecisions[attempt.owner] ?? true,
    );
  }

  @override
  PythonScriptCompletion<Object?> rememberDenial(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
    McpToolResult result,
  ) {
    events.add(_event('approval.rememberDenial', attempt.owner));
    rememberedDenials.add((attempt: attempt, key: key, result: result));
    return rememberDenialCompletionOverride ??
        PythonScriptCompletion.completed(
          owner: attempt.owner,
          toolCallId: attempt.toolCallId,
          toolName: attempt.toolName,
          value: null,
        );
  }

  @override
  PythonScriptCompletion<Object?> rememberResult(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
    McpToolResult result,
  ) {
    events.add(_event('approval.rememberResult', attempt.owner));
    rememberedResults.add((attempt: attempt, key: key, result: result));
    return rememberResultCompletionOverride ??
        PythonScriptCompletion.completed(
          owner: attempt.owner,
          toolCallId: attempt.toolCallId,
          toolName: attempt.toolName,
          value: null,
        );
  }

  @override
  PythonScriptCompletion<McpToolResult?> expiredResult(
    PythonStagingAttempt attempt,
  ) {
    events.add(_event('approval.expired', attempt.owner));
    expirationAttempts.add(attempt);
    return expirations.isEmpty
        ? PythonScriptCompletion.completed(
            owner: attempt.owner,
            toolCallId: attempt.toolCallId,
            toolName: attempt.toolName,
            value: null,
          )
        : expirations.removeAt(0);
  }
}

String _event(String name, ChatTurnOwner owner) {
  return '$name:${owner.conversationId}:${owner.interactionGeneration}';
}

final class _MutableValue {}

PythonStagingAllocation _allocation(
  PythonStagedInputs stagedInputs, {
  required String markerNonce,
}) {
  return PythonStagingAllocation(
    stagedInputs: stagedInputs,
    directoryIdentity: PythonStagingDirectoryIdentity(
      canonicalPath: stagedInputs.workingDirectory,
      markerNonce: markerNonce,
    ),
  );
}
