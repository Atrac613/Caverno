import 'dart:async';

import 'package:caverno/features/chat/data/datasources/python_script_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/python_script_tool_contract.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

final testPythonOwner = ChatTurnOwner(
  conversationId: 'python-conversation',
  interactionGeneration: 9,
);

Message testPythonMessage({
  String id = 'owner-message',
  String? originalImagePath = '/owner/input.png',
}) {
  return Message(
    id: id,
    content: 'Inspect my attachment.',
    role: MessageRole.user,
    timestamp: DateTime.utc(2026, 7, 31),
    originalImagePath: originalImagePath,
    originalImageMimeType: 'image/png',
  );
}

ToolCallInfo testPythonToolCall({
  String id = 'python-call',
  String name = 'run_python_script',
  Map<String, dynamic> arguments = const {
    'code': 'print("ok")',
    'timeout_seconds': 7,
    'reason': 'Inspect the attachment',
  },
}) {
  return ToolCallInfo(id: id, name: name, arguments: arguments);
}

final class PythonRuntimeFixture {
  PythonRuntimeFixture({
    List<Message>? messages,
    this.ownerMessageDisposition =
        PythonRuntimeAcknowledgementDisposition.completed,
    this.lifecycleDisposition =
        PythonRuntimeAcknowledgementDisposition.completed,
    this.stagingDisposition = PythonRuntimeAcknowledgementDisposition.completed,
    this.cleanupDisposition = PythonRuntimeAcknowledgementDisposition.completed,
    this.gateDisposition = PythonRuntimeAcknowledgementDisposition.completed,
    this.manualDisposition = PythonRuntimeAcknowledgementDisposition.completed,
    this.executionDisposition =
        PythonRuntimeAcknowledgementDisposition.completed,
    this.cacheWriteDisposition =
        PythonRuntimeAcknowledgementDisposition.completed,
    this.gate = ToolApprovalGateDecision.autoReviewAllowed,
    this.manualApproved = true,
    this.cachedDenial,
    this.executionResult,
    this.wrongOwnerMessageIdentity = false,
    this.wrongStagingIdentity = false,
    this.wrongGateIdentity = false,
    this.wrongExecutionIdentity = false,
    this.wrongCleanupIdentity = false,
    this.wrongCacheWriteIdentity = false,
    this.throwDuringExecution = false,
    this.throwDuringCleanup = false,
    this.throwDuringCacheWrite = false,
    this.invokeExecutionEffect = true,
    this.executionStarted,
    this.executionRelease,
    PythonScriptExecutionAuthority? executionAuthority,
  }) : messages = List.unmodifiable(messages ?? [testPythonMessage()]),
       executionAuthority =
           executionAuthority ?? PythonScriptExecutionAuthority();

  final List<Message> messages;
  final PythonRuntimeAcknowledgementDisposition ownerMessageDisposition;
  PythonRuntimeAcknowledgementDisposition lifecycleDisposition;
  final PythonRuntimeAcknowledgementDisposition stagingDisposition;
  PythonRuntimeAcknowledgementDisposition cleanupDisposition;
  final PythonRuntimeAcknowledgementDisposition gateDisposition;
  final PythonRuntimeAcknowledgementDisposition manualDisposition;
  final PythonRuntimeAcknowledgementDisposition executionDisposition;
  final PythonRuntimeAcknowledgementDisposition cacheWriteDisposition;
  final ToolApprovalGateDecision gate;
  final bool manualApproved;
  final McpToolResult? cachedDenial;
  final McpToolResult? executionResult;
  final bool wrongOwnerMessageIdentity;
  final bool wrongStagingIdentity;
  final bool wrongGateIdentity;
  final bool wrongExecutionIdentity;
  final bool wrongCleanupIdentity;
  final bool wrongCacheWriteIdentity;
  final bool throwDuringExecution;
  final bool throwDuringCleanup;
  final bool throwDuringCacheWrite;
  final bool invokeExecutionEffect;
  final Completer<void>? executionStarted;
  final Completer<void>? executionRelease;
  final PythonScriptExecutionAuthority executionAuthority;

  int ownerMessageCalls = 0;
  int lifecycleCalls = 0;
  int stagingCalls = 0;
  int cleanupCalls = 0;
  int gateCalls = 0;
  int manualCalls = 0;
  int executionCalls = 0;
  int denialLookupCalls = 0;
  int cacheWriteCalls = 0;
  int executionEffectCalls = 0;
  PythonRuntimeStagingRequest? stagingRequest;
  PythonRuntimeApprovalRequest? approvalRequest;
  PythonRuntimeExecutionRequest? executionRequest;
  PythonRuntimeCleanupRequest? cleanupRequest;
  PythonRuntimeCacheWriteRequest? cacheWriteRequest;
  final PythonStagingLeaseRegistry stagingLeases = PythonStagingLeaseRegistry();

  late final PythonScriptToolRuntimeAdapter adapter =
      PythonScriptToolRuntimeAdapter(
        stagingLeases: stagingLeases,
        executionAuthority: executionAuthority,
        resolveOwnerMessages: (identity) {
          ownerMessageCalls += 1;
          return PythonRuntimeAcknowledgement(
            identity: wrongOwnerMessageIdentity
                ? _wrongInvocation(identity)
                : identity,
            disposition: ownerMessageDisposition,
            value: messages,
          );
        },
        acknowledgeLifecycle: (identity) {
          lifecycleCalls += 1;
          return PythonRuntimeAcknowledgement(
            identity: identity,
            disposition: lifecycleDisposition,
          );
        },
        stage: (request) async {
          stagingCalls += 1;
          stagingRequest = request;
          final allocation = _allocation(request.identity.toolCallId);
          return PythonRuntimeAcknowledgement(
            identity: wrongStagingIdentity
                ? _wrongRuntime(request.identity)
                : request.identity,
            disposition: stagingDisposition,
            value:
                stagingDisposition ==
                    PythonRuntimeAcknowledgementDisposition.completed
                ? allocation
                : null,
          );
        },
        cleanup: (request) async {
          cleanupCalls += 1;
          cleanupRequest = request;
          if (throwDuringCleanup) {
            throw StateError('cleanup acknowledgement lost');
          }
          return PythonRuntimeAcknowledgement(
            identity: wrongCleanupIdentity
                ? PythonStagingCleanupIdentity(
                    runtime: request.identity.runtime,
                    attempt: request.identity.attempt,
                    directoryIdentity: PythonStagingDirectoryIdentity(
                      canonicalPath:
                          request.identity.directoryIdentity.canonicalPath,
                      markerNonce: 'wrong-marker',
                    ),
                  )
                : request.identity,
            disposition: cleanupDisposition,
            value:
                cleanupDisposition ==
                    PythonRuntimeAcknowledgementDisposition.completed
                ? PythonStagingCleanupOutcome.deleted
                : PythonStagingCleanupOutcome.failed,
          );
        },
        lookupDenial: (request) {
          denialLookupCalls += 1;
          return PythonRuntimeAcknowledgement(
            identity: request.identity,
            disposition: PythonRuntimeAcknowledgementDisposition.completed,
            value: cachedDenial,
          );
        },
        resolveGate: (request) async {
          gateCalls += 1;
          approvalRequest = request;
          return PythonRuntimeAcknowledgement(
            identity: wrongGateIdentity
                ? _wrongApproval(request.identity)
                : request.identity,
            disposition: gateDisposition,
            value:
                gateDisposition ==
                    PythonRuntimeAcknowledgementDisposition.completed
                ? gate
                : null,
          );
        },
        requestManualApproval: (request) async {
          manualCalls += 1;
          approvalRequest = request;
          return PythonRuntimeAcknowledgement(
            identity: request.identity,
            disposition: manualDisposition,
            value:
                manualDisposition ==
                    PythonRuntimeAcknowledgementDisposition.completed
                ? manualApproved
                : null,
          );
        },
        rememberDenial: _remember,
        rememberResult: _remember,
        execute: (request) async {
          executionCalls += 1;
          executionRequest = request;
          final started = executionStarted;
          if (started != null && !started.isCompleted) {
            started.complete();
          }
          if (executionRelease case final release?) {
            await release.future;
          }
          Future<
            PythonRuntimeAcknowledgement<
              PythonExecutionRuntimeIdentity,
              McpToolResult
            >
          >
          buildAcknowledgement() async {
            if (throwDuringExecution) {
              throw StateError('transport completion lost');
            }
            return PythonRuntimeAcknowledgement(
              identity: wrongExecutionIdentity
                  ? PythonExecutionRuntimeIdentity(
                      runtime: _wrongRuntime(request.identity.runtime),
                      directoryIdentity: request.identity.directoryIdentity,
                      arguments: request.arguments,
                    )
                  : request.identity,
              disposition: executionDisposition,
              value:
                  executionResult ??
                  (executionDisposition ==
                          PythonRuntimeAcknowledgementDisposition.completed
                      ? McpToolResult(
                          toolName: request.toolName,
                          result: '{"ok":true}',
                          isSuccess: true,
                        )
                      : null),
            );
          }

          if (!invokeExecutionEffect) {
            return buildAcknowledgement();
          }
          return request.runEffect(() {
            executionEffectCalls += 1;
            return buildAcknowledgement();
          });
        },
      );

  PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, Object?>
  _remember(PythonRuntimeCacheWriteRequest request) {
    cacheWriteCalls += 1;
    cacheWriteRequest = request;
    if (throwDuringCacheWrite) {
      throw StateError('cache acknowledgement lost');
    }
    return PythonRuntimeAcknowledgement(
      identity: wrongCacheWriteIdentity
          ? _wrongApproval(request.identity)
          : request.identity,
      disposition: cacheWriteDisposition,
    );
  }

  Future<PythonScriptRuntimeCompletion> run({
    ChatTurnOwner? owner,
    ToolCallInfo? toolCall,
  }) {
    return adapter.handle(
      owner: owner ?? testPythonOwner,
      toolCall: toolCall ?? testPythonToolCall(),
    );
  }
}

PythonStagingAllocation _allocation(String callId) {
  final path = '/tmp/caverno_python_test_$callId';
  return PythonStagingAllocation(
    stagedInputs: PythonStagedInputs(
      workingDirectory: path,
      inputs: [
        {'name': 'input.png', 'path': '$path/input.png', 'mime': 'image/png'},
      ],
    ),
    directoryIdentity: PythonStagingDirectoryIdentity(
      canonicalPath: path,
      markerNonce: 'marker-$callId',
    ),
  );
}

PythonScriptInvocationIdentity _wrongInvocation(
  PythonScriptInvocationIdentity identity,
) {
  return PythonScriptInvocationIdentity(
    owner: identity.owner,
    toolCallId: '${identity.toolCallId}-wrong',
    toolName: identity.toolName,
    argumentDigest: identity.argumentDigest,
  );
}

PythonScriptRuntimeIdentity _wrongRuntime(
  PythonScriptRuntimeIdentity identity,
) {
  return PythonScriptRuntimeIdentity(
    invocation: _wrongInvocation(identity.invocation),
    ownerMessages: const [],
  );
}

PythonApprovalRuntimeIdentity _wrongApproval(
  PythonApprovalRuntimeIdentity identity,
) {
  return PythonApprovalRuntimeIdentity(
    runtime: _wrongRuntime(identity.runtime),
    cacheArguments: const {'code': 'print("ok")'},
  );
}
