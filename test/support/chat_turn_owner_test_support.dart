import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/file_mutation_runtime_contract.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/subagent_task_notifier.dart';

extension StreamedChatCompletionTestExtension on Stream<String> {
  StreamedChatCompletion asCompletion([String? finishReason = 'stop']) =>
      StreamedChatCompletion.fromStream(this, finishReason: finishReason);
}

void registerChatTurnOwnerFallback() {
  registerFallbackValue(
    ChatTurnOwner(
      conversationId: 'mock-conversation',
      interactionGeneration: 1,
    ),
  );
}

mixin OwnerAwareMcpToolTestDelegate on McpToolService {
  final Map<FileMutationRuntimeIdentity, String> _fileMutationFingerprints = {};
  final Set<FileMutationRuntimeIdentity> _fileMutationEffectsApplied = {};

  @override
  Future<McpToolResult> executeFileTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => executeTool(name: name, arguments: arguments);

  @override
  Future<FileMutationRuntimeAcknowledgement<String>>
  readFileMutationFingerprint(FileMutationRuntimeIdentity identity) async {
    if (_fileMutationEffectsApplied.contains(identity)) {
      return FileMutationRuntimeAcknowledgement(
        identity: identity,
        disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        value: _fileMutationFingerprints[identity]!,
      );
    }
    final snapshot = await FilesystemTools.captureTextSnapshot(
      identity.canonicalPath,
    );
    final fingerprint = FilesystemTools.textSnapshotFingerprintForSnapshot(
      snapshot,
    );
    _fileMutationFingerprints[identity] = fingerprint;
    return FileMutationRuntimeAcknowledgement(
      identity: identity,
      disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
      value: fingerprint,
    );
  }

  @override
  Future<
    FileMutationRuntimeAcknowledgement<
      FileMutationRollbackCapture<TextFileSnapshot>
    >
  >
  captureFileMutationBefore(FileMutationRuntimeIdentity identity) async {
    final snapshot = await FilesystemTools.captureTextSnapshot(
      identity.canonicalPath,
    );
    final fingerprint = _fileMutationFingerprints[identity] ??=
        FilesystemTools.textSnapshotFingerprintForSnapshot(snapshot);
    return FileMutationRuntimeAcknowledgement(
      identity: identity,
      disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
      value: FileMutationRollbackCapture(
        identity: identity,
        snapshot: snapshot,
        beforeFingerprint: fingerprint,
        compensationToken: fileMutationJsonDigest({
          'toolCallId': identity.toolCallId,
          'before': fingerprint,
        }),
      ),
    );
  }

  @override
  Future<FileMutationExecutionAcknowledgement> executeRawFileMutation(
    FileMutationEffectRequest<TextFileSnapshot> request,
    FileMutationEffectAuthorization authorization,
  ) async {
    if (!authorization.beginEffectHandoff()) {
      throw StateError('The fixture mutation authorization expired.');
    }
    final result = await executeTool(
      name: request.identity.toolName,
      arguments: request.operationRequest.operation.arguments,
    );
    final afterFingerprint = fileMutationJsonDigest({
      'toolCallId': request.identity.toolCallId,
      'result': result.result,
    });
    _fileMutationFingerprints[request.identity] = afterFingerprint;
    _fileMutationEffectsApplied.add(request.identity);
    return FileMutationExecutionAcknowledgement(
      identity: request.identity,
      result: result,
      effectDisposition: FileMutationRawEffectDisposition.applied,
      postcondition: FileMutationEffectPostcondition(
        identity: request.identity,
        afterFingerprint: afterFingerprint,
        compensationToken: request.capture.compensationToken,
      ),
    );
  }

  @override
  Future<FileMutationRuntimeAcknowledgement<FileMutationRollbackRecordReceipt>>
  recordFileMutation(
    FileMutationRollbackRecordRequest<TextFileSnapshot> request,
  ) async {
    return FileMutationRuntimeAcknowledgement(
      identity: request.identity,
      disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
      value: FileMutationRollbackRecordReceipt(
        identity: request.identity,
        compensationToken: request.capture.compensationToken,
        recordToken: fileMutationJsonDigest({
          'toolCallId': request.identity.toolCallId,
          'record': request.expectedAfterFingerprint,
        }),
      ),
    );
  }

  @override
  Future<FileMutationCompensationAcknowledgement> compensateFileMutation(
    FileMutationCompensationRequest<TextFileSnapshot> request,
  ) async {
    _fileMutationFingerprints[request.identity] =
        request.capture.beforeFingerprint;
    _fileMutationEffectsApplied.remove(request.identity);
    return FileMutationCompensationAcknowledgement(
      identity: request.identity,
      compensationToken: request.capture.compensationToken,
      disposition: FileMutationRuntimeCompensationDisposition.reverted,
    );
  }

  @override
  Future<McpToolResult> executeProcessTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => executeTool(name: name, arguments: arguments);

  @override
  Future<McpToolResult> executeSshTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => executeTool(name: name, arguments: arguments);
}

void registerRunningBackgroundSubagentTask(
  ProviderContainer container, {
  required String taskId,
  required String description,
}) {
  final conversation = container
      .read(conversationsNotifierProvider.notifier)
      .ensureCurrentConversation();
  if (conversation == null) {
    throw StateError('A current conversation is required.');
  }
  final owner = ChatTurnOwner(
    conversationId: conversation.id,
    interactionGeneration: 1,
  );
  container
      .read(subagentTaskNotifierProvider.notifier)
      .register(
        owner,
        SubagentTask(
          id: taskId,
          conversationId: owner.conversationId,
          interactionGeneration: owner.interactionGeneration,
          status: SubagentTaskStatus.running,
          description: description,
          isBackground: true,
          startedAt: DateTime.now(),
        ),
      );
}
