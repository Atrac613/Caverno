import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service_file_rollback_facade.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );

  group('FileRollbackToolRuntimeAdapter', () {
    late Map<String, TextFileSnapshot> current;
    late bool ownerCurrent;
    late ToolApprovalGateDecision gate;
    late bool manualApproved;
    late McpToolResult? cachedDenial;
    late List<FileRollbackApprovalRequest> gateRequests;
    late List<FileRollbackApprovalRequest> manualRequests;
    late List<McpToolResult> denialRecords;
    late List<McpToolResult> resultRecords;
    late String Function(String path) restorePayload;
    late FileRollbackCheckpointStore store;
    late FileRollbackToolRuntimeAdapter adapter;
    late FileRollbackToolHandler handler;

    setUp(() {
      current = {
        '/a.txt': const TextFileSnapshot(
          path: '/a.txt',
          exists: true,
          content: 'after',
        ),
      };
      ownerCurrent = true;
      gate = ToolApprovalGateDecision.autoReviewAllowed;
      manualApproved = true;
      cachedDenial = null;
      gateRequests = [];
      manualRequests = [];
      denialRecords = [];
      resultRecords = [];
      restorePayload = (path) => jsonEncode({'path': path, 'restored': true});
      store = FileRollbackCheckpointStore(
        snapshotLoader: (path) async => current[path]!,
        snapshotRestorer:
            ({required path, required existedBefore, content}) async {
              return restorePayload(path);
            },
      );
      store.push(
        owner,
        const TextFileSnapshot(path: '/a.txt', exists: true, content: 'before'),
      );
      adapter = FileRollbackToolRuntimeAdapter(
        checkpointStore: store,
        lookupDenial: (_) => cachedDenial,
        resolveGate: (request) async {
          gateRequests.add(request);
          return gate;
        },
        requestManualApproval: (request) async {
          manualRequests.add(request);
          return manualApproved;
        },
        ownerIsCurrent: (identity) => identity.owner == owner && ownerCurrent,
        rememberDenial: (request, result) => denialRecords.add(result),
        rememberResult: (request, result) => resultRecords.add(result),
      );
      handler = FileRollbackToolHandler(
        historyPort: adapter,
        approvalPort: adapter,
        executionPort: adapter,
      );
    });

    FileRollbackToolRequest request({String call = 'rollback-a'}) {
      return FileRollbackToolRequest(
        owner: owner,
        toolCallId: call,
        toolName: canonicalFileRollbackToolName,
        arguments: const {},
      );
    }

    test(
      'binds preview, approval, execution, and result acknowledgement',
      () async {
        final toolRequest = request();

        final result = await handler.handle(toolRequest);

        expect(result.isSuccess, isTrue);
        expect(gateRequests, hasLength(1));
        final approval = gateRequests.single;
        expect(approval.identity, toolRequest.identity);
        expect(approval.target.identity, toolRequest.identity);
        expect(approval.checkpointToken, isNotEmpty);
        expect(manualRequests, isEmpty);
        expect(resultRecords, [same(result)]);
        expect(await store.previewFileRollbackCheckpoint(owner), isNull);
      },
    );

    test(
      'returns exact cached denial without touching rollback history',
      () async {
        cachedDenial = const McpToolResult(
          toolName: canonicalFileRollbackToolName,
          result: '',
          isSuccess: false,
          errorMessage: 'cached denial',
        );
        final before = await store.previewFileRollbackCheckpoint(owner);

        final result = await handler.handle(request());

        expect(result, same(cachedDenial));
        expect(gateRequests, isEmpty);
        expect(
          (await store.previewFileRollbackCheckpoint(owner))!.checkpointToken,
          before!.checkpointToken,
        );
      },
    );

    test('binds manual denial and its cache acknowledgement', () async {
      gate = ToolApprovalGateDecision.needsManualApproval;
      manualApproved = false;
      final toolRequest = request();

      final result = await handler.handle(toolRequest);

      expect(result.errorMessage, 'User denied file rollback');
      expect(manualRequests, hasLength(1));
      expect(manualRequests.single.identity, toolRequest.identity);
      expect(
        manualRequests.single.checkpointToken,
        gateRequests.single.checkpointToken,
      );
      expect(denialRecords, [same(result)]);
      expect(resultRecords, isEmpty);
    });

    test('owner acknowledgement prevents execution after expiration', () async {
      ownerCurrent = false;
      final before = await store.previewFileRollbackCheckpoint(owner);

      final result = await handler.handle(request());

      expect(result.errorMessage, 'Tool approval expired before execution');
      expect(resultRecords, isEmpty);
      expect(
        (await store.previewFileRollbackCheckpoint(owner))!.checkpointToken,
        before!.checkpointToken,
      );
    });

    test(
      'maps a changed approved file state to a known no-effect failure',
      () async {
        adapter = FileRollbackToolRuntimeAdapter(
          checkpointStore: store,
          lookupDenial: (_) => null,
          resolveGate: (approval) async {
            current['/a.txt'] = const TextFileSnapshot(
              path: '/a.txt',
              exists: true,
              content: 'external successor',
            );
            return ToolApprovalGateDecision.autoReviewAllowed;
          },
          requestManualApproval: (_) async => true,
          ownerIsCurrent: (_) => true,
          rememberDenial: (_, _) {},
          rememberResult: (_, result) => resultRecords.add(result),
        );
        handler = FileRollbackToolHandler(
          historyPort: adapter,
          approvalPort: adapter,
          executionPort: adapter,
        );

        final result = await handler.handle(request());

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('preview it again'));
        expect(resultRecords, [same(result)]);
        expect(await store.previewFileRollbackCheckpoint(owner), isNotNull);
      },
    );

    test(
      'production facade rejects a successor created after approval preview',
      () async {
        var restoreCalls = 0;
        final facadeStore = FileRollbackCheckpointStore(
          snapshotLoader: (path) async => current[path]!,
          snapshotRestorer:
              ({required path, required existedBefore, content}) async {
                restoreCalls++;
                return jsonEncode({'path': path, 'restored': true});
              },
        );
        facadeStore.push(
          owner,
          const TextFileSnapshot(
            path: '/a.txt',
            exists: true,
            content: 'before',
          ),
        );
        final facade = _TestOwnerFacade(
          BuiltInFilesystemToolHandler(checkpointStore: facadeStore),
        );

        final result = await facade.executeExactFileRollback(
          request: request(call: 'facade-successor'),
          lookupDenial: (_) => null,
          resolveGate: (_) async {
            facadeStore.push(
              owner,
              const TextFileSnapshot(
                path: '/a.txt',
                exists: true,
                content: 'after',
              ),
            );
            current['/a.txt'] = const TextFileSnapshot(
              path: '/a.txt',
              exists: true,
              content: 'successor',
            );
            return ToolApprovalGateDecision.autoReviewAllowed;
          },
          requestManualApproval: (_) async => true,
          ownerIsCurrent: (_) => true,
          rememberDenial: (_, _) {},
          rememberResult: (_, _) {},
        );

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('preview it again'));
        expect(restoreCalls, 0);
        expect(current['/a.txt']!.content, 'successor');
      },
    );

    test(
      'maps restoration exceptions to possible-side-effect uncertainty',
      () async {
        restorePayload = (_) => throw StateError('failed after dispatch');

        final result = await handler.handle(request());

        expect(result.errorMessage, contains('may have been rolled back'));
        expect(resultRecords, isEmpty);
        expect(await store.previewFileRollbackCheckpoint(owner), isNotNull);
      },
    );

    test(
      'classifies retirement during restoration as a retained effect',
      () async {
        restorePayload = (path) {
          store.clear(owner);
          return jsonEncode({'path': path, 'restored': true});
        };

        final result = await handler.handle(request());

        expect(result.errorMessage, contains('may have been rolled back'));
        expect(resultRecords, isEmpty);
        expect(await store.previewFileRollbackCheckpoint(owner), isNull);
      },
    );

    test(
      'post-effect owner expiry becomes an uncertain acknowledgement',
      () async {
        adapter = FileRollbackToolRuntimeAdapter(
          checkpointStore: store,
          lookupDenial: (_) => null,
          resolveGate: (_) async => ToolApprovalGateDecision.autoReviewAllowed,
          requestManualApproval: (_) async => true,
          ownerIsCurrent: (_) => ownerCurrent,
          rememberDenial: (_, _) {},
          rememberResult: (_, result) {
            resultRecords.add(result);
            ownerCurrent = false;
          },
        );
        handler = FileRollbackToolHandler(
          historyPort: adapter,
          approvalPort: adapter,
          executionPort: adapter,
        );

        final result = await handler.handle(request());

        expect(result.errorMessage, contains('may have been rolled back'));
        expect(resultRecords, hasLength(1));
      },
    );

    test('full-access execution rechecks owner after the effect', () async {
      gate = ToolApprovalGateDecision.fullAccess;
      restorePayload = (path) {
        ownerCurrent = false;
        return jsonEncode({'path': path, 'restored': true});
      };

      final result = await handler.handle(request());

      expect(result.errorMessage, contains('may have been rolled back'));
      expect(resultRecords, isEmpty);
    });

    test('direct execution maps pre-effect owner retirement exactly', () async {
      final toolRequest = request();
      final preview = (await adapter.previewLatest(toolRequest.identity))!;
      store.clear(owner);

      final execution = await adapter.rollback(
        toolRequest.identity,
        preview.checkpointToken,
      );

      expect(
        execution.disposition,
        FileRollbackExecutionDisposition.ownerExpired,
      );
      expect(
        execution.expiredEffectDisposition,
        FileRollbackExpiredEffectDisposition.notApplied,
      );
      expect(execution.identity, toolRequest.identity);
      expect(execution.checkpointToken, preview.checkpointToken);
    });
  });
}

final class _TestOwnerFacade with McpToolServiceFileRollbackFacade {
  _TestOwnerFacade(this.filesystemToolHandler);

  @override
  final BuiltInFilesystemToolHandler filesystemToolHandler;
}
