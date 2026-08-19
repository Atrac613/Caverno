import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/file_mutation_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/data/datasources/project_mutation_path_fence.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/file_mutation_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );

  group('FileMutationToolRuntimeAdapter', () {
    test('commits an exact write effect and rollback record', () async {
      final fixture = _Fixture(owner);

      final completion = await fixture.run();

      expect(completion.disposition, FileMutationRuntimeDisposition.completed);
      expect(completion.result.isSuccess, isTrue);
      expect(fixture.executionCalls, 1);
      expect(fixture.recordCalls, 1);
      expect(fixture.compensationCalls, 0);
      expect(fixture.fingerprint, 'after');
      expect(fixture.authorizationAttempts, 1);
      expect(fixture.identities, isNotEmpty);
      expect(
        fixture.identities.every((identity) => identity == completion.identity),
        isTrue,
      );
      expect(fixture.recordRequests.single.expectedAfterFingerprint, 'after');
      expect(
        () =>
            fixture
                    .effectRequests
                    .single
                    .operationRequest
                    .operation
                    .arguments['content'] =
                'poisoned',
        throwsUnsupportedError,
      );
    });

    test('preserves exact edit and delete tool identities', () async {
      for (final toolName in ['edit_file', 'delete_file']) {
        final fixture = _Fixture(owner)
          ..executionResult = McpToolResult(
            toolName: toolName,
            result: '{"ok":true,"path":"/workspace/a/lib/main.dart"}',
            isSuccess: true,
          );

        final completion = await fixture.run(toolName: toolName);

        expect(
          completion.disposition,
          FileMutationRuntimeDisposition.completed,
        );
        expect(completion.identity.toolName, toolName);
        expect(fixture.effectRequests.single.identity.toolName, toolName);
        expect(fixture.recordCalls, 1);
      }
    });

    test(
      'freezes strict raw and resolved arguments before callbacks',
      () async {
        final fixture = _Fixture(owner);
        final rawMetadata = <String, dynamic>{
          'tags': <Object?>['safe'],
        };
        final rawArguments = <String, dynamic>{
          'path': 'lib/main.dart',
          'content': 'new',
          'metadata': rawMetadata,
        };
        final resolvedArguments = <String, dynamic>{
          ...rawArguments,
          'path': '/workspace/a/lib/main.dart',
        };

        final future = fixture.run(
          rawArguments: rawArguments,
          resolvedArguments: resolvedArguments,
        );
        rawMetadata['poisoned'] = true;
        (rawMetadata['tags']! as List<Object?>).add('poisoned');
        rawArguments['content'] = 'poisoned';
        resolvedArguments['path'] = '/workspace/b/main.dart';
        final completion = await future;

        expect(
          completion.disposition,
          FileMutationRuntimeDisposition.completed,
        );
        final operation =
            fixture.effectRequests.single.operationRequest.operation;
        expect(operation.content, 'new');
        expect(operation.path, '/workspace/a/lib/main.dart');
        expect(operation.arguments['metadata'], {
          'tags': ['safe'],
        });
        expect(completion.identity.projectRoot, '/workspace/a');
        expect(completion.identity.canonicalPath, '/workspace/a/lib/main.dart');
      },
    );

    test('rejects non-JSON arguments before runtime callbacks', () async {
      final fixture = _Fixture(owner);

      await expectLater(
        fixture.run(
          rawArguments: {
            'path': 'lib/main.dart',
            'content': 'new',
            'metadata': <Object?>{'invalid'},
          },
        ),
        throwsArgumentError,
      );

      expect(fixture.identities, isEmpty);
      expect(fixture.executionCalls, 0);
    });

    test('rejects an unresolved relative runtime path', () async {
      final fixture = _Fixture(owner);

      await expectLater(
        fixture.run(
          resolvedArguments: const {'path': 'lib/main.dart', 'content': 'new'},
        ),
        throwsArgumentError,
      );

      expect(fixture.executionCalls, 0);
    });

    test('expires after rollback capture without starting an effect', () async {
      final fixture = _Fixture(owner)..expireAfterCapture = true;

      final completion = await fixture.run();

      expect(
        completion.disposition,
        FileMutationRuntimeDisposition.ownerExpired,
      );
      expect(
        jsonDecode(completion.result.result),
        containsPair('code', 'turn_owner_expired'),
      );
      expect(fixture.executionCalls, 0);
      expect(fixture.recordCalls, 0);
      expect(fixture.compensationCalls, 0);
    });

    test(
      'preserves an exact owner-expiry result before effect start',
      () async {
        const expired = McpToolResult(
          toolName: 'write_file',
          result: '{"ok":false,"code":"custom_expiry"}',
          isSuccess: false,
          errorMessage: 'The owning approval expired',
        );
        final fixture = _Fixture(owner)
          ..expireAfterCapture = true
          ..expiredResult = expired;

        final completion = await fixture.run();

        expect(
          completion.disposition,
          FileMutationRuntimeDisposition.ownerExpired,
        );
        expect(completion.result, same(expired));
        expect(fixture.executionCalls, 0);
      },
    );

    test('compensates an applied effect when its owner expires', () async {
      final fixture = _Fixture(owner)..expireAfterExecution = true;

      final completion = await fixture.run();

      expect(
        completion.disposition,
        FileMutationRuntimeDisposition.ownerExpired,
      );
      expect(fixture.executionCalls, 1);
      expect(fixture.recordCalls, 0);
      expect(fixture.compensationCalls, 1);
      expect(fixture.compensationRequests.single.recordToken, isNull);
      expect(fixture.fingerprint, 'before');
      expect(
        jsonDecode(completion.result.result),
        containsPair('code', 'turn_owner_expired'),
      );
    });

    test(
      'compensates a coordinator-retired owner before rollback record',
      () async {
        final fixture = _Fixture(owner)..retireOwnerAfterExecution = true;

        final completion = await fixture.run();

        expect(
          completion.disposition,
          FileMutationRuntimeDisposition.ownerExpired,
        );
        expect(fixture.recordCalls, 0);
        expect(fixture.compensationCalls, 1);
        expect(fixture.fingerprint, 'before');
      },
    );

    test('reports and compensates a partial effect explicitly', () async {
      final fixture = _Fixture(owner)
        ..effectDisposition = FileMutationRawEffectDisposition.partialOrUnknown;

      final completion = await fixture.run();

      expect(
        completion.disposition,
        FileMutationRuntimeDisposition.effectUncertain,
      );
      expect(fixture.compensationCalls, 1);
      expect(fixture.fingerprint, 'before');
      expect(
        jsonDecode(completion.result.result),
        containsPair('code', 'file_mutation_effect_uncertain'),
      );
      expect(completion.result.errorMessage, contains('partial or ambiguous'));
    });

    test('reports a changed no-effect acknowledgement as uncertain', () async {
      final fixture = _Fixture(owner)
        ..effectDisposition = FileMutationRawEffectDisposition.noEffect
        ..startEffectForNoEffect = true
        ..afterFingerprint = 'unexpected-change'
        ..executionResult = const McpToolResult(
          toolName: 'write_file',
          result: '{"ok":false}',
          isSuccess: false,
          errorMessage: 'write failed',
        );

      final completion = await fixture.run();

      expect(
        completion.disposition,
        FileMutationRuntimeDisposition.effectUncertain,
      );
      expect(fixture.compensationCalls, 1);
      expect(fixture.fingerprint, 'before');
      expect(
        completion.result.errorMessage,
        contains('no-effect mutation acknowledgement'),
      );
    });

    test(
      'accepts a proven no-effect rejection without rollback record',
      () async {
        final fixture = _Fixture(owner)
          ..effectDisposition = FileMutationRawEffectDisposition.noEffect
          ..startEffectForNoEffect = false
          ..executionResult = const McpToolResult(
            toolName: 'write_file',
            result: '{"ok":false}',
            isSuccess: false,
            errorMessage: 'write rejected',
          );

        final completion = await fixture.run();

        expect(completion.disposition, FileMutationRuntimeDisposition.rejected);
        expect(completion.result.errorMessage, 'write rejected');
        expect(fixture.recordCalls, 0);
        expect(fixture.compensationCalls, 0);
        expect(fixture.fingerprint, 'before');
      },
    );

    test(
      'rejects a postcondition receipt with the wrong argument identity',
      () async {
        final fixture = _Fixture(owner)..mismatchExecutionIdentity = true;

        final completion = await fixture.run();

        expect(
          completion.disposition,
          FileMutationRuntimeDisposition.boundaryMismatch,
        );
        expect(
          jsonDecode(completion.result.result),
          containsPair('code', 'file_mutation_effect_uncertain'),
        );
        expect(fixture.recordCalls, 0);
        expect(fixture.compensationCalls, 1);
      },
    );

    test('does not compensate across a successor fingerprint', () async {
      final fixture = _Fixture(owner)
        ..expireAfterExecution = true
        ..successorBeforeCompensation = true;

      final completion = await fixture.run();

      expect(
        completion.disposition,
        FileMutationRuntimeDisposition.effectUncertain,
      );
      expect(fixture.compensationCalls, 0);
      expect(fixture.fingerprint, 'successor');
      expect(
        jsonDecode(completion.result.result),
        containsPair('code', 'file_mutation_effect_uncertain'),
      );
    });
  });
}

final class _Fixture {
  _Fixture(this.owner) {
    adapter = FileMutationToolRuntimeAdapter<String>(
      authorizePath: _allowAdapterMutationPath,
      acknowledgeLifecycle: (identity) {
        identities.add(identity);
        final remaining = lifecycleChecksUntilExpiry;
        if (remaining != null) {
          if (remaining == 0) {
            current = false;
            lifecycleChecksUntilExpiry = null;
          } else {
            lifecycleChecksUntilExpiry = remaining - 1;
          }
        }
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition: current
              ? FileMutationRuntimeAcknowledgementDisposition.completed
              : FileMutationRuntimeAcknowledgementDisposition.ownerExpired,
          value: current ? null : expiredResult,
        );
      },
      preflightEdit: (request) async {
        identities.add(request.identity);
        return FileMutationRuntimeAcknowledgement(
          identity: request.identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        );
      },
      fingerprint: (identity) async {
        identities.add(identity);
        if (executionReturned) {
          postEffectFingerprintReads++;
          if (successorBeforeCompensation && postEffectFingerprintReads == 2) {
            fingerprint = 'successor';
          }
        }
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
          value: fingerprint,
        );
      },
      isRegularFile: (identity) async {
        identities.add(identity);
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
          value: true,
        );
      },
      captureDeleteSnapshot: (identity) async {
        identities.add(identity);
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
          value: const FileMutationDeleteSnapshot(content: 'before'),
        );
      },
      buildPreview: (request) async {
        identities.add(request.identity);
        return FileMutationRuntimeAcknowledgement(
          identity: request.identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
          value: 'diff preview',
        );
      },
      lookupDenial: (request) {
        identities.add(request.identity);
        return FileMutationRuntimeAcknowledgement(
          identity: request.identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        );
      },
      resolveGate: (request, {required buildPreview}) async {
        identities.add(request.identity);
        expect(await buildPreview(), 'diff preview');
        return FileMutationRuntimeAcknowledgement(
          identity: request.identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
          value: ToolApprovalGateDecision.autoReviewAllowed,
        );
      },
      requestManualApproval: (request, {required preview}) async {
        identities.add(request.identity);
        return FileMutationRuntimeAcknowledgement(
          identity: request.identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
          value: true,
        );
      },
      rememberDenial: (request) {
        identities.add(request.identity);
        return FileMutationRuntimeAcknowledgement(
          identity: request.identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        );
      },
      rememberResult: (request) {
        identities.add(request.identity);
        return FileMutationRuntimeAcknowledgement(
          identity: request.identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        );
      },
      captureBefore: (identity) async {
        identities.add(identity);
        final capture = FileMutationRollbackCapture(
          identity: identity,
          snapshot: 'snapshot-before',
          beforeFingerprint: fingerprint,
          compensationToken: 'restore-before',
        );
        if (expireAfterCapture) lifecycleChecksUntilExpiry = 1;
        return FileMutationRuntimeAcknowledgement(
          identity: identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
          value: capture,
        );
      },
      recordMutation: (request) async {
        identities.add(request.identity);
        recordCalls++;
        recordRequests.add(request);
        return FileMutationRuntimeAcknowledgement(
          identity: request.identity,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
          value: FileMutationRollbackRecordReceipt(
            identity: request.identity,
            compensationToken: request.capture.compensationToken,
            recordToken: 'record-1',
          ),
        );
      },
      execute: (request, authorization) async {
        identities.add(request.identity);
        executionCalls++;
        effectRequests.add(request);
        authorizationAttempts++;
        final shouldStart =
            effectDisposition != FileMutationRawEffectDisposition.noEffect ||
            startEffectForNoEffect;
        if (shouldStart) {
          expect(authorization.beginEffectHandoff(), isTrue);
          fingerprint = afterFingerprint;
        }
        if (expireAfterExecution) current = false;
        if (retireOwnerAfterExecution) adapter.retireOwner(owner);
        executionReturned = true;
        final acknowledgementIdentity = mismatchExecutionIdentity
            ? _mismatchedIdentity(request.identity)
            : request.identity;
        return FileMutationExecutionAcknowledgement(
          identity: acknowledgementIdentity,
          result: executionResult,
          effectDisposition: effectDisposition,
          postcondition:
              effectDisposition == FileMutationRawEffectDisposition.noEffect
              ? null
              : FileMutationEffectPostcondition(
                  identity: acknowledgementIdentity,
                  afterFingerprint:
                      reportedAfterFingerprint ?? afterFingerprint,
                  compensationToken: request.capture.compensationToken,
                ),
        );
      },
      compensate: (request) async {
        identities.add(request.identity);
        compensationCalls++;
        compensationRequests.add(request);
        fingerprint = 'before';
        return FileMutationCompensationAcknowledgement(
          identity: request.identity,
          compensationToken: request.capture.compensationToken,
          disposition: FileMutationRuntimeCompensationDisposition.reverted,
        );
      },
    );
  }

  final ChatTurnOwner owner;
  late final FileMutationToolRuntimeAdapter<String> adapter;
  bool current = true;
  bool expireAfterCapture = false;
  bool expireAfterExecution = false;
  bool mismatchExecutionIdentity = false;
  bool startEffectForNoEffect = false;
  bool successorBeforeCompensation = false;
  bool retireOwnerAfterExecution = false;
  bool executionReturned = false;
  int? lifecycleChecksUntilExpiry;
  McpToolResult? expiredResult;
  String fingerprint = 'before';
  String afterFingerprint = 'after';
  String? reportedAfterFingerprint;
  FileMutationRawEffectDisposition effectDisposition =
      FileMutationRawEffectDisposition.applied;
  McpToolResult executionResult = const McpToolResult(
    toolName: 'write_file',
    result: '{"ok":true,"path":"/workspace/a/lib/main.dart"}',
    isSuccess: true,
  );
  int executionCalls = 0;
  int postEffectFingerprintReads = 0;
  int authorizationAttempts = 0;
  int recordCalls = 0;
  int compensationCalls = 0;
  final List<FileMutationRuntimeIdentity> identities = [];
  final List<FileMutationEffectRequest<String>> effectRequests = [];
  final List<FileMutationRollbackRecordRequest<String>> recordRequests = [];
  final List<FileMutationCompensationRequest<String>> compensationRequests = [];

  Future<FileMutationRuntimeCompletion> run({
    String toolName = 'write_file',
    Map<String, dynamic>? rawArguments,
    Map<String, dynamic>? resolvedArguments,
  }) {
    final defaultRawArguments = switch (toolName) {
      'edit_file' => const <String, dynamic>{
        'path': 'lib/main.dart',
        'old_text': 'old',
        'new_text': 'new',
      },
      'delete_file' => const <String, dynamic>{'path': 'lib/main.dart'},
      _ => const <String, dynamic>{'path': 'lib/main.dart', 'content': 'new'},
    };
    final defaultResolvedArguments = <String, dynamic>{
      ...defaultRawArguments,
      'path': '/workspace/a/lib/main.dart',
    };
    return adapter.handle(
      owner: owner,
      toolCall: ToolCallInfo(
        id: 'mutation-call-1',
        name: toolName,
        arguments: rawArguments ?? defaultRawArguments,
      ),
      approvalMode: ToolApprovalMode.autoReview,
      projectRoot: '/workspace/a',
      resolvedArguments: resolvedArguments ?? defaultResolvedArguments,
      conversationMessages: [
        Message(
          id: 'message-1',
          content: 'Update the file.',
          role: MessageRole.user,
          timestamp: DateTime.utc(2026, 7, 31, 12),
        ),
      ],
      hasUntrustedInfluence: false,
    );
  }
}

FileMutationRuntimeIdentity _mismatchedIdentity(
  FileMutationRuntimeIdentity identity,
) {
  return FileMutationRuntimeIdentity(
    owner: identity.owner,
    toolCallId: identity.toolCallId,
    toolName: identity.toolName,
    argumentDigest: identity.argumentDigest,
    resolvedArgumentDigest: '${identity.resolvedArgumentDigest}mismatch',
    projectRoot: identity.projectRoot,
    canonicalPath: identity.canonicalPath,
    approvalContextDigest: identity.approvalContextDigest,
  );
}

Future<ProjectMutationPathAuthorization> _allowAdapterMutationPath({
  required String toolName,
  required String? projectRoot,
  required String rawPath,
}) async {
  final path = rawPath.trim();
  final root = projectRoot?.trim() ?? '/workspace/a';
  if (path.isEmpty) {
    return ProjectMutationPathAuthorization.denied(
      ProjectMutationPathDenial.outsideProject,
      toolName: toolName,
      canonicalRoot: root,
      rawPath: path,
    );
  }
  return ProjectMutationPathAuthorization.allowed(
    canonicalRoot: root,
    canonicalPath: path,
  );
}
