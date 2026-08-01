import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/file_turn_rollback_service.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _unusedRollbackResult = McpToolResult(
  toolName: 'rollback_last_turn_file_changes',
  result: '',
  isSuccess: false,
);

final class _FakeFileCheckpointPort implements FileCheckpointPort {
  _FakeFileCheckpointPort({
    this.previewResult,
    this.rollbackResult = _unusedRollbackResult,
  });

  final FileTurnRollbackPreview? previewResult;
  final McpToolResult rollbackResult;

  int previewCallCount = 0;
  String? previewConversationId;
  ChatTurnOwner? rollbackOwner;
  int? rollbackCheckpointToken;

  @override
  Future<FileTurnRollbackPreview?> previewLastFileTurn({
    required String? conversationId,
  }) async {
    previewCallCount += 1;
    previewConversationId = conversationId;
    return previewResult;
  }

  @override
  Future<McpToolResult> rollbackLastFileTurn({
    required ChatTurnOwner owner,
    required int checkpointToken,
  }) async {
    rollbackOwner = owner;
    rollbackCheckpointToken = checkpointToken;
    return rollbackResult;
  }
}

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );

  test(
    'returns compatible unavailable results when the port is absent',
    () async {
      const service = FileTurnRollbackService();

      expect(
        await service.preview(conversationId: owner.conversationId),
        isNull,
      );

      final result = await service.rollback(owner: owner, checkpointToken: 41);
      expect(result.toolName, 'rollback_last_turn_file_changes');
      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(result.isExternalMcpResult, isFalse);
      expect(result.errorMessage, 'No file checkpoint service is available');
      expect(result.outcome, isNull);
    },
  );

  test(
    'returns an absent preview without changing the conversation ID',
    () async {
      final checkpointPort = _FakeFileCheckpointPort();
      final service = FileTurnRollbackService(checkpointPort: checkpointPort);

      expect(await service.preview(conversationId: ' conversation-a '), isNull);
      expect(checkpointPort.previewCallCount, 1);
      expect(checkpointPort.previewConversationId, ' conversation-a ');
    },
  );

  test('propagates a successful preview from the checkpoint port', () async {
    final sourcePaths = <String>['/workspace/lib/main.dart'];
    final preview = FileTurnRollbackPreview(
      owner: owner,
      checkpointToken: 41,
      turnId: 'turn-7',
      paths: sourcePaths,
      preview: 'diff --git a/lib/main.dart b/lib/main.dart',
      summary: 'Revert the last agent turn file change.',
      currentStateFingerprint: 'preview-state-41',
    );
    final checkpointPort = _FakeFileCheckpointPort(previewResult: preview);
    final service = FileTurnRollbackService(checkpointPort: checkpointPort);

    final result = await service.preview(conversationId: owner.conversationId);
    sourcePaths[0] = '/workspace/lib/poisoned.dart';

    expect(result, isNot(same(preview)));
    expect(result!.owner, owner);
    expect(result.checkpointToken, 41);
    expect(result.turnId, 'turn-7');
    expect(result.paths, ['/workspace/lib/main.dart']);
    expect(
      () => result.paths.add('/workspace/lib/later-poison.dart'),
      throwsUnsupportedError,
    );
    expect(result.preview, 'diff --git a/lib/main.dart b/lib/main.dart');
    expect(result.summary, 'Revert the last agent turn file change.');
    expect(result.currentStateFingerprint, 'preview-state-41');
  });

  test('forwards the exact owner and token for successful rollback', () async {
    const rollbackResult = McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: '{"ok":true,"turn_id":"turn-7"}',
      isSuccess: true,
    );
    final checkpointPort = _FakeFileCheckpointPort(
      rollbackResult: rollbackResult,
    );
    final service = FileTurnRollbackService(checkpointPort: checkpointPort);

    final result = await service.rollback(owner: owner, checkpointToken: 41);

    expect(checkpointPort.rollbackOwner, same(owner));
    expect(checkpointPort.rollbackCheckpointToken, 41);
    expect(result, same(rollbackResult));
    expect(result.isSuccess, isTrue);
  });

  test('propagates a failed rollback without rewriting its error', () async {
    const rollbackResult = McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: '{"ok":false,"restored":[]}',
      isSuccess: false,
      errorMessage: 'Failed to roll back the last turn file checkpoint',
    );
    final service = FileTurnRollbackService(
      checkpointPort: _FakeFileCheckpointPort(rollbackResult: rollbackResult),
    );

    final result = await service.rollback(owner: owner, checkpointToken: 41);

    expect(result, same(rollbackResult));
    expect(result.isSuccess, isFalse);
    expect(
      result.errorMessage,
      'Failed to roll back the last turn file checkpoint',
    );
  });

  test('preserves every tool result field supplied by the port', () async {
    const rollbackResult = McpToolResult(
      toolName: 'custom_rollback_result',
      result: '{"custom":true}',
      isSuccess: false,
      isExternalMcpResult: true,
      errorMessage: 'custom failure',
      outcome: ToolOutcome(exitCode: 9, fileChanged: true),
    );
    final service = FileTurnRollbackService(
      checkpointPort: _FakeFileCheckpointPort(rollbackResult: rollbackResult),
    );

    final result = await service.rollback(owner: owner, checkpointToken: 99);

    expect(result, same(rollbackResult));
    expect(result.toolName, 'custom_rollback_result');
    expect(result.result, '{"custom":true}');
    expect(result.isSuccess, isFalse);
    expect(result.isExternalMcpResult, isTrue);
    expect(result.errorMessage, 'custom failure');
    expect(result.outcome, const ToolOutcome(exitCode: 9, fileChanged: true));
  });

  test(
    'keeps preview and rollback ownership isolated across conversations',
    () async {
      final ownerB = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: 7,
      );
      final checkpointPort = _RoutingFileCheckpointPort({
        owner.conversationId: FileTurnRollbackPreview(
          owner: owner,
          checkpointToken: 41,
          turnId: 'turn-a',
          paths: const ['/workspace/a.dart'],
          preview: 'preview-a',
          summary: 'summary-a',
        ),
        ownerB.conversationId: FileTurnRollbackPreview(
          owner: ownerB,
          checkpointToken: 99,
          turnId: 'turn-b',
          paths: const ['/workspace/b.dart'],
          preview: 'preview-b',
          summary: 'summary-b',
        ),
      });
      final service = FileTurnRollbackService(checkpointPort: checkpointPort);

      final previewB = (await service.preview(
        conversationId: ownerB.conversationId,
      ))!;
      final previewA = (await service.preview(
        conversationId: owner.conversationId,
      ))!;
      await service.rollback(
        owner: previewA.owner,
        checkpointToken: previewA.checkpointToken,
      );
      await service.rollback(
        owner: previewB.owner,
        checkpointToken: previewB.checkpointToken,
      );

      expect(previewB.owner, ownerB);
      expect(previewB.checkpointToken, 99);
      expect(previewA.owner, owner);
      expect(previewA.checkpointToken, 41);
      expect(checkpointPort.previewConversationIds, [
        'conversation-b',
        'conversation-a',
      ]);
      expect(checkpointPort.rollbackCalls, [
        (owner: owner, checkpointToken: 41),
        (owner: ownerB, checkpointToken: 99),
      ]);
    },
  );

  test(
    'callback factory forwards exact preview and rollback identities',
    () async {
      String? previewConversationId;
      ChatTurnOwner? rollbackOwner;
      int? rollbackToken;
      final preview = FileTurnRollbackPreview(
        owner: owner,
        checkpointToken: 41,
        turnId: 'turn-a',
        paths: const ['/workspace/a.dart'],
        preview: 'preview-a',
        summary: 'summary-a',
      );
      const rollbackResult = McpToolResult(
        toolName: 'rollback_last_turn_file_changes',
        result: '{"ok":true}',
        isSuccess: true,
      );
      final service = FileTurnRollbackService.fromCallbacks(
        (conversationId) async {
          previewConversationId = conversationId;
          return preview;
        },
        (receivedOwner, checkpointToken) async {
          rollbackOwner = receivedOwner;
          rollbackToken = checkpointToken;
          return rollbackResult;
        },
      );

      final receivedPreview = await service.preview(
        conversationId: 'conversation-a',
      );
      expect(receivedPreview, isNot(same(preview)));
      expect(receivedPreview!.owner, same(owner));
      expect(
        await service.rollback(owner: owner, checkpointToken: 41),
        same(rollbackResult),
      );
      expect(previewConversationId, 'conversation-a');
      expect(rollbackOwner, same(owner));
      expect(rollbackToken, 41);
    },
  );

  test('callback factory preserves unavailable-service behavior', () async {
    final service = FileTurnRollbackService.fromCallbacks(null, null);

    expect(await service.preview(conversationId: 'conversation-a'), isNull);
    expect(
      (await service.rollback(owner: owner, checkpointToken: 41)).errorMessage,
      'No file checkpoint service is available',
    );
  });
}

typedef _RollbackCall = ({ChatTurnOwner owner, int checkpointToken});

final class _RoutingFileCheckpointPort implements FileCheckpointPort {
  _RoutingFileCheckpointPort(this.previewsByConversation);

  final Map<String, FileTurnRollbackPreview> previewsByConversation;
  final List<String?> previewConversationIds = [];
  final List<_RollbackCall> rollbackCalls = [];

  @override
  Future<FileTurnRollbackPreview?> previewLastFileTurn({
    required String? conversationId,
  }) async {
    previewConversationIds.add(conversationId);
    return previewsByConversation[conversationId];
  }

  @override
  Future<McpToolResult> rollbackLastFileTurn({
    required ChatTurnOwner owner,
    required int checkpointToken,
  }) async {
    rollbackCalls.add((owner: owner, checkpointToken: checkpointToken));
    return const McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: '{"ok":true}',
      isSuccess: true,
    );
  }
}
