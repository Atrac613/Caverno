import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/project_mutation_path_fence.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/dart_project_tooling.dart';
import 'package:caverno/features/chat/domain/services/file_mutation_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 3,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 7,
  );

  group('FileMutationToolHandler', () {
    test('handles create and overwrite writes with frozen arguments', () async {
      for (final before in ['missing-before', 'existing-before']) {
        final fixture = _fixture(rollbackBefore: before);
        final rawTags = <Object?>['owner-a'];
        final rawMetadata = <String, dynamic>{'tags': rawTags};
        final sourceArguments = <String, dynamic>{
          'path': '/workspace/a/lib/new.dart',
          'content': 'void main() {}',
          'create_parents': true,
          'metadata': {
            'paths': <Object?>['/workspace/a/lib/new.dart'],
            'raw_metadata': rawMetadata,
          },
        };
        final operation = FileMutationOperation(
          kind: FileMutationKind.writeFile,
          arguments: sourceArguments,
          reason: 'Create the entrypoint.',
        );
        sourceArguments['content'] = 'changed after capture';
        final sourceMetadata =
            sourceArguments['metadata']! as Map<String, dynamic>;
        (sourceMetadata['paths']! as List<Object?>).add(
          '/workspace/b/lib/poison.dart',
        );
        rawMetadata['poisoned'] = true;
        rawTags.add('poisoned');

        final result = await fixture.handler.handle(
          _request(ownerA, operation),
        );

        expect(result.toolName, 'write_file');
        expect(result.isSuccess, isTrue);
        expect(
          fixture.execution.executed.single.operation.content,
          'void main() {}',
        );
        expect(
          fixture.execution.executed.single.operation.reason,
          'Create the entrypoint.',
        );
        final frozenMetadata =
            operation.arguments['metadata'] as Map<String, dynamic>;
        final frozenRawMetadata =
            frozenMetadata['raw_metadata'] as Map<String, dynamic>;
        final frozenTags = frozenRawMetadata['tags'] as List<Object?>;
        expect(frozenRawMetadata.keys, ['tags']);
        expect(frozenTags, ['owner-a']);
        expect(fixture.rollback.recorded.single.before, before);
        expect(
          fixture.approval.requests.single.operation.kind.approvalTitle,
          'Write File',
        );
        expect(
          () => operation.arguments['content'] = 'mutated',
          throwsUnsupportedError,
        );
        expect(
          () =>
              ((operation.arguments['metadata']
                          as Map<String, dynamic>)['paths']
                      as List<Object?>)
                  .add('/workspace/b/lib/other.dart'),
          throwsUnsupportedError,
        );
        expect(
          () => frozenRawMetadata['late'] = 'changed',
          throwsUnsupportedError,
        );
        expect(() => frozenTags.add('changed'), throwsUnsupportedError);
      }
    });

    test('rejects non-JSON operation arguments before side effects', () {
      final invalidValues = <Object?>[
        <Object?, Object?>{7: 'invalid'},
        <Object?>{'not-json'},
        Object(),
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final invalidValue in invalidValues) {
        expect(
          () => FileMutationOperation(
            kind: FileMutationKind.writeFile,
            arguments: {
              'path': '/workspace/a/lib/new.dart',
              'content': 'void main() {}',
              'metadata': invalidValue,
            },
          ),
          throwsArgumentError,
          reason: invalidValue.toString(),
        );
      }
    });

    test(
      'carries the complete immutable approval-coordinator snapshot',
      () async {
        final messages = <Message>[
          Message(
            id: 'user-a',
            content: 'Update the entrypoint.',
            role: MessageRole.user,
            timestamp: DateTime.utc(2026, 7, 31, 12),
          ),
        ];
        final operation = FileMutationOperation(
          kind: FileMutationKind.writeFile,
          arguments: const {
            'path': '/workspace/a/lib/main.dart',
            'content': 'void main() {}',
          },
          reason: 'Apply the requested entrypoint update.',
        );
        final toolArguments = <String, dynamic>{
          'path': 'lib/main.dart',
          'contents': 'void main() {}',
          'reason': 'Apply the requested entrypoint update.',
        };
        final request = _request(
          ownerA,
          operation,
          toolCallId: 'mutation-call-41',
          approvalMode: ToolApprovalMode.autoReview,
          toolArguments: toolArguments,
          conversationMessages: messages,
          hasUntrustedInfluence: true,
        );
        messages.clear();
        toolArguments['path'] = 'lib/poison.dart';
        final fixture = _fixture();

        await fixture.handler.handle(request);

        final approval = fixture.approval.requests.single;
        expect(approval.toolRequest, same(request));
        expect(approval.toolCallId, 'mutation-call-41');
        expect(approval.approvalMode, ToolApprovalMode.autoReview);
        expect(approval.stateFingerprint, 'same');
        expect(approval.arguments, {
          'path': 'lib/main.dart',
          'contents': 'void main() {}',
          'reason': 'Apply the requested entrypoint update.',
        });
        expect(approval.cacheArguments['path'], '/workspace/a/lib/main.dart');
        expect(approval.path, '/workspace/a/lib/main.dart');
        expect(approval.toolName, 'write_file');
        expect(approval.reason, 'Apply the requested entrypoint update.');
        expect(approval.conversationMessages.map((message) => message.id), [
          'user-a',
        ]);
        expect(approval.hasUntrustedInfluence, isTrue);
        expect(
          () => approval.conversationMessages.add(
            Message(
              id: 'poison',
              content: 'Poison',
              role: MessageRole.user,
              timestamp: DateTime.utc(2026, 7, 31, 13),
            ),
          ),
          throwsUnsupportedError,
        );
      },
    );

    test('preserves single and replace-all edit requests', () async {
      for (final replaceAll in [false, true]) {
        final fixture = _fixture();
        final operation = FileMutationOperation(
          kind: FileMutationKind.editFile,
          arguments: {
            'path': '/workspace/a/lib/main.dart',
            'old_text': 'old',
            'new_text': 'new',
            'replace_all': replaceAll,
          },
        );

        final result = await fixture.handler.handle(
          _request(ownerA, operation),
        );

        expect(result.toolName, 'edit_file');
        expect(fixture.execution.preflighted.single.owner, ownerA);
        final executed = fixture.execution.executed.single.operation;
        expect(executed.oldText, 'old');
        expect(executed.newText, 'new');
        expect(executed.replaceAll, replaceAll);
        expect(
          fixture.approval.requests.single.operation.kind.approvalTitle,
          'Edit File',
        );
      }
    });

    test(
      'validates and executes delete with its captured preview content',
      () async {
        final fixture = _fixture(
          deleteSnapshot: const FileMutationDeleteSnapshot(
            content: 'obsolete\n',
          ),
          executionResult: const McpToolResult(
            toolName: 'delete_file',
            result: '{"deleted":true}',
            isSuccess: true,
          ),
        );
        final operation = FileMutationOperation(
          kind: FileMutationKind.deleteFile,
          arguments: const {'path': '/workspace/a/obsolete.txt'},
        );

        final result = await fixture.handler.handle(
          _request(ownerA, operation),
        );

        expect(result.result, '{"deleted":true}');
        expect(fixture.execution.regularFileChecks.single.owner, ownerA);
        expect(fixture.execution.deleteSnapshots.single.owner, ownerA);
        expect(fixture.execution.previewDeleteContents, ['obsolete\n']);
        expect(
          fixture.execution.executed.single.operation.toolName,
          'delete_file',
        );
        expect(
          fixture.approval.requests.single.operation.kind.approvalTitle,
          'Delete File',
        );
      },
    );

    test('maps missing and invalid arguments without execution', () async {
      final missingFixture = _fixture();
      final missing = await missingFixture.handler.handle(
        _request(
          ownerA,
          FileMutationOperation(
            kind: FileMutationKind.writeFile,
            arguments: const {'path': ''},
          ),
        ),
      );
      expect(missing.result, isEmpty);
      expect(missing.errorMessage, 'path is required');
      expect(missingFixture.events, isEmpty);

      final editFixture = _fixture(
        preflightResult: jsonEncode({
          'error': 'old_text must not be empty',
          'path': '/workspace/a/lib/main.dart',
        }),
      );
      final invalidEdit = await editFixture.handler.handle(
        _request(
          ownerA,
          FileMutationOperation(
            kind: FileMutationKind.editFile,
            arguments: const {
              'path': '/workspace/a/lib/main.dart',
              'old_text': '',
              'new_text': 'new',
            },
          ),
        ),
      );
      expect(invalidEdit.isSuccess, isFalse);
      expect(invalidEdit.errorMessage, 'old_text must not be empty');
      expect(editFixture.execution.executed, isEmpty);

      final outsideFixture = _fixture();
      final outsideDelete = await outsideFixture.handler.handle(
        _request(
          ownerA,
          FileMutationOperation(
            kind: FileMutationKind.deleteFile,
            arguments: const {'path': '/workspace/b/keep.txt'},
          ),
        ),
      );
      expect(
        jsonDecode(outsideDelete.result),
        containsPair('code', 'project_mutation_outside_root'),
      );
      expect(
        jsonDecode(outsideDelete.result),
        containsPair('path', '/workspace/b/keep.txt'),
      );
      expect(outsideFixture.events, isEmpty);

      final emptyDelete = await outsideFixture.handler.handle(
        _request(
          ownerA,
          FileMutationOperation(
            kind: FileMutationKind.deleteFile,
            arguments: const {'path': ''},
          ),
        ),
      );
      expect(jsonDecode(emptyDelete.result), isNot(contains('path')));
    });

    test('maps invalid delete targets and unavailable snapshots', () async {
      final nonFileFixture = _fixture(isRegularFile: false);
      final operation = FileMutationOperation(
        kind: FileMutationKind.deleteFile,
        arguments: const {'path': '/workspace/a/folder'},
      );

      final nonFile = await nonFileFixture.handler.handle(
        _request(ownerA, operation),
      );

      expect(
        jsonDecode(nonFile.result),
        containsPair('code', 'delete_target_not_regular_file'),
      );
      expect(nonFileFixture.execution.deleteSnapshots, isEmpty);

      final snapshotFixture = _fixture(
        deleteSnapshot: const FileMutationDeleteSnapshot(
          content: null,
          error: 'binary file',
        ),
      );
      final noSnapshot = await snapshotFixture.handler.handle(
        _request(ownerA, operation),
      );
      expect(
        jsonDecode(noSnapshot.result),
        containsPair('code', 'delete_snapshot_unavailable'),
      );
      expect(
        noSnapshot.errorMessage,
        'A rollback snapshot is required before deletion',
      );
    });

    test('rejects a target that changed after approval', () async {
      final fixture = _fixture(fingerprints: ['approved', 'changed']);
      final operation = FileMutationOperation(
        kind: FileMutationKind.writeFile,
        arguments: const {
          'path': '/workspace/a/lib/main.dart',
          'content': 'new',
        },
      );

      final result = await fixture.handler.handle(_request(ownerA, operation));

      expect(result.isSuccess, isFalse);
      expect(
        jsonDecode(result.result),
        containsPair('code', 'file_changed_since_approval'),
      );
      expect(
        jsonDecode(result.result),
        containsPair('path', '/workspace/a/lib/main.dart'),
      );
      expect(fixture.execution.executed, isEmpty);
      expect(fixture.rollback.captured, isEmpty);
    });

    test('returns cached, auto-review, and manual approval denials', () async {
      const cachedResult = McpToolResult(
        toolName: 'write_file',
        result: '',
        isSuccess: false,
        errorMessage: 'cached denial',
      );
      final cachedFixture = _fixture(cachedDenial: cachedResult);
      final write = FileMutationOperation(
        kind: FileMutationKind.writeFile,
        arguments: const {'path': '/workspace/a/new.txt', 'content': 'new'},
      );
      expect(
        await cachedFixture.handler.handle(_request(ownerA, write)),
        cachedResult,
      );
      expect(cachedFixture.execution.previews, isEmpty);

      final autoFixture = _fixture(
        gate: ToolApprovalGateDecision.denied('unsafe mutation'),
        gateLoadsPreview: false,
      );
      final autoDenied = await autoFixture.handler.handle(
        _request(ownerA, write),
      );
      expect(
        autoDenied.result,
        'Auto-review denied this action. Rationale: unsafe mutation',
      );
      expect(autoDenied.errorMessage, 'Auto-review denied: unsafe mutation');
      expect(autoFixture.approval.rememberedDenials, hasLength(1));

      for (final kind in FileMutationKind.values) {
        final manualFixture = _fixture(
          gate: ToolApprovalGateDecision.needsManualApproval,
          gateLoadsPreview: false,
          manualApproved: false,
        );
        final operation = _validOperation(kind);
        final denied = await manualFixture.handler.handle(
          _request(ownerA, operation),
        );
        expect(denied.errorMessage, kind.manualDenialMessage);
        expect(
          manualFixture.approval.manualRequests.single.request.operation.kind,
          kind,
        );
        expect(manualFixture.execution.executed, isEmpty);
      }
    });

    test('contains expiration after capturing before-state', () async {
      const expired = McpToolResult(
        toolName: 'write_file',
        result: '',
        isSuccess: false,
        errorMessage: 'The approval turn expired before execution',
      );
      final fixture = _fixture(expiredResult: expired);

      final result = await fixture.handler.handle(
        _request(ownerA, _validOperation(FileMutationKind.writeFile)),
      );

      expect(result, expired);
      expect(fixture.rollback.captured, hasLength(1));
      expect(fixture.execution.executed, isEmpty);
      expect(
        fixture.events.indexOf('rollback.capture:conversation-a'),
        lessThan(fixture.events.indexOf('approval.expired:conversation-a')),
      );
    });

    test(
      'detects successful payloads and does not capture failed effects',
      () async {
        final fixture = _fixture();
        const failedResult = McpToolResult(
          toolName: 'write_file',
          result: '{"path":"a"}',
          isSuccess: false,
        );
        const errorPayload = McpToolResult(
          toolName: 'write_file',
          result: '{"error":"failed"}',
          isSuccess: true,
        );
        const alreadyApplied = McpToolResult(
          toolName: 'edit_file',
          result: '{"already_applied":true}',
          isSuccess: true,
        );
        const successPayload = McpToolResult(
          toolName: 'write_file',
          result: '{"path":"a"}',
          isSuccess: true,
        );
        const nonMapPayload = McpToolResult(
          toolName: 'write_file',
          result: 'true',
          isSuccess: true,
        );
        const malformedPayload = McpToolResult(
          toolName: 'write_file',
          result: 'not-json',
          isSuccess: true,
        );

        expect(
          fixture.handler.isSuccessfulMutationResult(failedResult),
          isFalse,
        );
        expect(
          fixture.handler.isSuccessfulMutationResult(errorPayload),
          isFalse,
        );
        expect(
          fixture.handler.isSuccessfulMutationResult(alreadyApplied),
          isFalse,
        );
        expect(
          fixture.handler.isSuccessfulMutationResult(successPayload),
          isTrue,
        );
        expect(
          fixture.handler.isSuccessfulMutationResult(nonMapPayload),
          isTrue,
        );
        expect(
          fixture.handler.isSuccessfulMutationResult(malformedPayload),
          isTrue,
        );

        final failedFixture = _fixture(executionResult: errorPayload);
        await failedFixture.handler.handle(
          _request(ownerA, _validOperation(FileMutationKind.writeFile)),
        );
        expect(failedFixture.rollback.recorded, isEmpty);
      },
    );

    test('propagates execution errors without recording a mutation', () async {
      final fixture = _fixture(
        executionError: StateError('filesystem unavailable'),
        gate: ToolApprovalGateDecision.fullAccess,
        gateLoadsPreview: false,
      );

      await expectLater(
        fixture.handler.handle(
          _request(ownerA, _validOperation(FileMutationKind.writeFile)),
        ),
        throwsA(isA<StateError>()),
      );

      expect(fixture.rollback.captured, hasLength(1));
      expect(fixture.rollback.recorded, isEmpty);
    });

    test('captures before execution and records only after success', () async {
      final fixture = _fixture();

      await fixture.handler.handle(
        _request(ownerA, _validOperation(FileMutationKind.writeFile)),
      );

      expect(fixture.events, [
        'execution.fingerprint:conversation-a',
        'approval.lookup:conversation-a',
        'approval.resolve:conversation-a',
        'execution.preview:conversation-a',
        'execution.fingerprint:conversation-a',
        'rollback.capture:conversation-a',
        'approval.expired:conversation-a',
        'execution.execute:conversation-a',
        'rollback.record:conversation-a',
        'approval.rememberResult:conversation-a',
      ]);
    });

    test(
      'uses only owning root and approvals when another owner conflicts',
      () async {
        final fixture = _fixture(
          decisionsByOwner: {
            ownerA: ToolApprovalGateDecision.autoReviewAllowed,
            ownerB: ToolApprovalGateDecision.denied('visible owner denied'),
          },
        );
        final operation = FileMutationOperation(
          kind: FileMutationKind.deleteFile,
          arguments: const {'path': '/workspace/a/owner.txt'},
        );
        final visibleOperation = FileMutationOperation(
          kind: FileMutationKind.deleteFile,
          arguments: const {'path': '/workspace/b/visible.txt'},
        );
        final visibleResult = await fixture.handler.handle(
          FileMutationToolRequest(
            owner: ownerB,
            toolCallId: 'mutation-call-owner-b',
            approvalMode: ToolApprovalMode.autoReview,
            projectRoot: '/workspace/b',
            operation: visibleOperation,
          ),
        );

        final result = await fixture.handler.handle(
          FileMutationToolRequest(
            owner: ownerA,
            toolCallId: 'mutation-call-owner-a',
            approvalMode: ToolApprovalMode.autoReview,
            projectRoot: ' /workspace/a ',
            operation: operation,
          ),
        );

        expect(visibleResult.isSuccess, isFalse);
        expect(
          visibleResult.errorMessage,
          'Auto-review denied: visible owner denied',
        );
        expect(result.isSuccess, isTrue);
        expect(fixture.approval.owners.toSet(), {ownerA, ownerB});
        expect(fixture.execution.owners.toSet(), {ownerA, ownerB});
        expect(fixture.rollback.owners.toSet(), {ownerA});
        expect(
          fixture.execution.executed.single.operation.path,
          '/workspace/a/owner.txt',
        );
        expect(
          fixture.execution.executed.single.operation.path,
          isNot('/workspace/b/visible.txt'),
        );
      },
    );

    test('preserves a successful non-error preflight payload', () async {
      final fixture = _fixture(
        preflightResult: '{"already_applied":true,"replacements":0}',
      );

      final result = await fixture.handler.handle(
        _request(ownerA, _validOperation(FileMutationKind.editFile)),
      );

      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(fixture.execution.executed, isEmpty);
    });
  });
}

typedef _Fixture = ({
  FileMutationToolHandler<String> handler,
  _ExecutionPort execution,
  _ApprovalPort approval,
  _RollbackPort rollback,
  List<String> events,
});

_Fixture _fixture({
  List<String> fingerprints = const ['same'],
  String? preflightResult,
  bool isRegularFile = true,
  FileMutationDeleteSnapshot deleteSnapshot = const FileMutationDeleteSnapshot(
    content: 'old content',
  ),
  McpToolResult? executionResult,
  Object? executionError,
  McpToolResult? cachedDenial,
  ToolApprovalGateDecision gate = ToolApprovalGateDecision.autoReviewAllowed,
  Map<ChatTurnOwner, ToolApprovalGateDecision> decisionsByOwner = const {},
  bool gateLoadsPreview = true,
  bool manualApproved = true,
  McpToolResult? expiredResult,
  String rollbackBefore = 'before',
}) {
  final events = <String>[];
  final execution = _ExecutionPort(
    events: events,
    fingerprints: fingerprints,
    preflightResult: preflightResult,
    regularFile: isRegularFile,
    deleteSnapshot: deleteSnapshot,
    result: executionResult,
    error: executionError,
  );
  final approval = _ApprovalPort(
    events: events,
    cachedDenial: cachedDenial,
    gate: gate,
    decisionsByOwner: decisionsByOwner,
    gateLoadsPreview: gateLoadsPreview,
    manualApproved: manualApproved,
    expired: expiredResult,
  );
  final rollback = _RollbackPort(events: events, before: rollbackBefore);
  return (
    handler: FileMutationToolHandler(
      executionPort: execution,
      approvalPort: approval,
      rollbackCapturePort: rollback,
      authorizePath: _lexicalMutationAuthorizer,
    ),
    execution: execution,
    approval: approval,
    rollback: rollback,
    events: events,
  );
}

Future<ProjectMutationPathAuthorization> _lexicalMutationAuthorizer({
  required String toolName,
  required String? projectRoot,
  required String rawPath,
}) async {
  final root = projectRoot?.trim() ?? '';
  final path = rawPath.trim();
  if (root.isEmpty) {
    return ProjectMutationPathAuthorization.denied(
      ProjectMutationPathDenial.projectRootRequired,
      toolName: toolName,
    );
  }
  if (path.isEmpty || !DartProjectPath.isInsideRoot(path, root)) {
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

FileMutationToolRequest _request(
  ChatTurnOwner owner,
  FileMutationOperation operation, {
  String toolCallId = 'mutation-call-a',
  ToolApprovalMode approvalMode = ToolApprovalMode.autoReview,
  String? projectRoot = '/workspace/a',
  Map<String, dynamic>? toolArguments,
  List<Message> conversationMessages = const [],
  bool hasUntrustedInfluence = false,
}) {
  return FileMutationToolRequest(
    owner: owner,
    toolCallId: toolCallId,
    approvalMode: approvalMode,
    projectRoot: projectRoot,
    operation: operation,
    toolArguments: toolArguments,
    conversationMessages: conversationMessages,
    hasUntrustedInfluence: hasUntrustedInfluence,
  );
}

FileMutationOperation _validOperation(FileMutationKind kind) {
  return switch (kind) {
    FileMutationKind.writeFile => FileMutationOperation(
      kind: kind,
      arguments: const {'path': '/workspace/a/file.txt', 'content': 'new'},
    ),
    FileMutationKind.editFile => FileMutationOperation(
      kind: kind,
      arguments: const {
        'path': '/workspace/a/file.txt',
        'old_text': 'old',
        'new_text': 'new',
      },
    ),
    FileMutationKind.deleteFile => FileMutationOperation(
      kind: kind,
      arguments: const {'path': '/workspace/a/file.txt'},
    ),
  };
}

typedef _OwnedOperation = ({
  ChatTurnOwner owner,
  FileMutationOperation operation,
});

final class _ExecutionPort implements FileMutationExecutionPort {
  _ExecutionPort({
    required this.events,
    required this.fingerprints,
    required this.preflightResult,
    required this.regularFile,
    required this.deleteSnapshot,
    required this.result,
    required this.error,
  });

  final List<String> events;
  final List<String> fingerprints;
  final String? preflightResult;
  final bool regularFile;
  final FileMutationDeleteSnapshot deleteSnapshot;
  final McpToolResult? result;
  final Object? error;
  final List<ChatTurnOwner> owners = [];
  final List<_OwnedOperation> preflighted = [];
  final List<_OwnedOperation> executed = [];
  final List<({ChatTurnOwner owner, String path})> regularFileChecks = [];
  final List<({ChatTurnOwner owner, String path})> deleteSnapshots = [];
  final List<String?> previewDeleteContents = [];
  final List<FileMutationOperation> previews = [];
  int _fingerprintIndex = 0;

  void _record(String event, ChatTurnOwner owner) {
    owners.add(owner);
    events.add('$event:${owner.conversationId}');
  }

  @override
  Future<String?> preflightEdit(
    ChatTurnOwner owner,
    FileMutationOperation operation,
  ) async {
    _record('execution.preflight', owner);
    preflighted.add((owner: owner, operation: operation));
    return preflightResult;
  }

  @override
  Future<String> fingerprint(ChatTurnOwner owner, String path) async {
    _record('execution.fingerprint', owner);
    final index = _fingerprintIndex++;
    return index < fingerprints.length
        ? fingerprints[index]
        : fingerprints.last;
  }

  @override
  Future<bool> isRegularFile(ChatTurnOwner owner, String path) async {
    _record('execution.isRegularFile', owner);
    regularFileChecks.add((owner: owner, path: path));
    return regularFile;
  }

  @override
  Future<FileMutationDeleteSnapshot> captureDeleteSnapshot(
    ChatTurnOwner owner,
    String path,
  ) async {
    _record('execution.deleteSnapshot', owner);
    deleteSnapshots.add((owner: owner, path: path));
    return deleteSnapshot;
  }

  @override
  Future<String> buildPreview(
    ChatTurnOwner owner,
    FileMutationOperation operation, {
    String? deleteContent,
  }) async {
    _record('execution.preview', owner);
    previews.add(operation);
    previewDeleteContents.add(deleteContent);
    switch (operation.kind) {
      case FileMutationKind.writeFile:
        operation.content;
      case FileMutationKind.editFile:
        operation.oldText;
        operation.newText;
        operation.replaceAll;
      case FileMutationKind.deleteFile:
        deleteContent;
    }
    return 'preview:${operation.kind.approvalTitle}';
  }

  @override
  Future<McpToolResult> execute(
    ChatTurnOwner owner,
    FileMutationOperation operation,
  ) async {
    _record('execution.execute', owner);
    executed.add((owner: owner, operation: operation));
    if (error case final error?) {
      throw error;
    }
    return result ??
        McpToolResult(
          toolName: operation.toolName,
          result: '{"ok":true}',
          isSuccess: true,
        );
  }
}

typedef _ManualRequest = ({
  ChatTurnOwner owner,
  FileMutationApprovalRequest request,
  String preview,
});

final class _ApprovalPort implements FileMutationApprovalPort {
  _ApprovalPort({
    required this.events,
    required this.cachedDenial,
    required this.gate,
    required this.decisionsByOwner,
    required this.gateLoadsPreview,
    required this.manualApproved,
    required this.expired,
  });

  final List<String> events;
  final McpToolResult? cachedDenial;
  final ToolApprovalGateDecision gate;
  final Map<ChatTurnOwner, ToolApprovalGateDecision> decisionsByOwner;
  final bool gateLoadsPreview;
  final bool manualApproved;
  final McpToolResult? expired;
  final List<ChatTurnOwner> owners = [];
  final List<FileMutationApprovalRequest> requests = [];
  final List<_ManualRequest> manualRequests = [];
  final List<McpToolResult> rememberedDenials = [];
  final List<McpToolResult> rememberedResults = [];

  void _record(String event, ChatTurnOwner owner) {
    owners.add(owner);
    events.add('$event:${owner.conversationId}');
  }

  @override
  McpToolResult? lookupDenial(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
  ) {
    _record('approval.lookup', owner);
    requests.add(request);
    return cachedDenial;
  }

  @override
  Future<ToolApprovalGateDecision> resolveGate(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request, {
    required FileMutationPreviewLoader buildPreview,
  }) async {
    _record('approval.resolve', owner);
    if (gateLoadsPreview) {
      await buildPreview();
    }
    return decisionsByOwner[owner] ?? gate;
  }

  @override
  Future<bool> requestManualApproval(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request, {
    required String preview,
  }) async {
    _record('approval.manual', owner);
    manualRequests.add((owner: owner, request: request, preview: preview));
    return manualApproved;
  }

  @override
  McpToolResult rememberDenial(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
    McpToolResult result,
  ) {
    _record('approval.rememberDenial', owner);
    rememberedDenials.add(result);
    return result;
  }

  @override
  McpToolResult rememberResult(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
    McpToolResult result,
  ) {
    _record('approval.rememberResult', owner);
    rememberedResults.add(result);
    return result;
  }

  @override
  McpToolResult? expiredResult(ChatTurnOwner owner, String toolName) {
    _record('approval.expired', owner);
    return expired;
  }
}

typedef _CapturedBefore = ({ChatTurnOwner owner, String path, String before});

final class _RollbackPort implements FileMutationRollbackCapturePort<String> {
  _RollbackPort({required this.events, required this.before});

  final List<String> events;
  final String before;
  final List<ChatTurnOwner> owners = [];
  final List<_CapturedBefore> captured = [];
  final List<_CapturedBefore> recorded = [];

  void _record(String event, ChatTurnOwner owner) {
    owners.add(owner);
    events.add('$event:${owner.conversationId}');
  }

  @override
  Future<String> captureBefore(ChatTurnOwner owner, String path) async {
    _record('rollback.capture', owner);
    captured.add((owner: owner, path: path, before: before));
    return before;
  }

  @override
  Future<void> recordSuccessfulMutation(
    ChatTurnOwner owner, {
    required String before,
    required String path,
  }) async {
    _record('rollback.record', owner);
    recorded.add((owner: owner, path: path, before: before));
  }
}
