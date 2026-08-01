import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import 'immutable_json_snapshot.dart';
import 'python_staging_lease_registry.dart';

Map<String, dynamic> freezePythonToolMap(Map<String, dynamic> value) {
  return ImmutableJsonSnapshot.freezeMap(value);
}

final class PythonOwnerMessageSnapshot {
  PythonOwnerMessageSnapshot({
    required this.owner,
    required List<Message> messages,
  }) : messages = List<Message>.unmodifiable(messages);

  final ChatTurnOwner owner;
  final List<Message> messages;
}

final class PythonScriptToolRequest {
  PythonScriptToolRequest({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required this.ownerMessages,
    required Map<String, dynamic> arguments,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = _requiredValue(toolName, 'toolName'),
       arguments = freezePythonToolMap(arguments) {
    if (ownerMessages.owner != owner) {
      throw ArgumentError.value(
        ownerMessages.owner,
        'ownerMessages',
        'Python message snapshot must match the tool owner.',
      );
    }
  }

  static const canonicalToolName = 'run_python_script';

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final PythonOwnerMessageSnapshot ownerMessages;
  final Map<String, dynamic> arguments;

  String get code => (arguments['code'] as String?)?.trim() ?? '';

  String? get reason {
    final normalized = arguments['reason']?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  PythonStagingAttempt get attempt => PythonStagingAttempt(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
  );

  PythonInputAttachment? get latestEligibleAttachment {
    for (final message in ownerMessages.messages.reversed) {
      if (message.role == MessageRole.user &&
          ((message.originalImagePath?.isNotEmpty ?? false) ||
              (message.imageBase64?.isNotEmpty ?? false))) {
        return PythonInputAttachment.fromMessage(message);
      }
    }
    return null;
  }
}

enum PythonScriptCompletionDisposition { completed, ownerExpired }

final class PythonScriptCompletion<T> {
  const PythonScriptCompletion.completed({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required this.value,
  }) : disposition = PythonScriptCompletionDisposition.completed;

  const PythonScriptCompletion.ownerExpired({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
  }) : disposition = PythonScriptCompletionDisposition.ownerExpired,
       value = null;

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final PythonScriptCompletionDisposition disposition;
  final T? value;
}

/// Validates that asynchronous completions belong to one exact tool attempt.
abstract final class PythonCompletionFence {
  static bool expired<T>(
    PythonScriptCompletion<T> completion,
    PythonScriptToolRequest request,
    String source,
  ) {
    if (completion.owner != request.owner) {
      throw StateError('$source owner mismatch.');
    }
    if (completion.toolCallId != request.toolCallId) {
      throw StateError('$source tool call mismatch.');
    }
    if (completion.toolName != request.toolName) {
      throw StateError('$source tool name mismatch.');
    }
    return completion.disposition ==
        PythonScriptCompletionDisposition.ownerExpired;
  }

  static T requiredValue<T>(
    PythonScriptCompletion<T> completion,
    String source,
  ) {
    final value = completion.value;
    if (value == null) throw StateError('$source returned no value.');
    return value;
  }

  static McpToolResult validResult(
    PythonScriptToolRequest request,
    McpToolResult result,
  ) {
    if (result.toolName != request.toolName) {
      throw StateError('Python result tool name mismatch.');
    }
    return result;
  }
}

abstract final class PythonToolResults {
  static McpToolResult failure(String toolName, String message) =>
      McpToolResult(
        toolName: toolName,
        result: '',
        isSuccess: false,
        errorMessage: message,
      );

  static McpToolResult expiredBefore(PythonScriptToolRequest request) =>
      failure(
        request.toolName,
        'The Python tool turn expired before execution',
      );

  static McpToolResult expiredAfter(PythonScriptToolRequest request) => failure(
    request.toolName,
    'The Python execution may have completed after its owner expired; '
    'inspect possible side effects before retrying',
  );

  static McpToolResult autoReviewDenied(String toolName, String rationale) =>
      McpToolResult(
        toolName: toolName,
        result: 'Auto-review denied this action. Rationale: $rationale',
        isSuccess: false,
        errorMessage: 'Auto-review denied: $rationale',
      );
}

final class PythonInputAttachment {
  const PythonInputAttachment({
    required this.messageId,
    required this.imageBase64,
    required this.imageMimeType,
    required this.originalImagePath,
    required this.originalImageMimeType,
  });

  factory PythonInputAttachment.fromMessage(Message message) {
    return PythonInputAttachment(
      messageId: message.id,
      imageBase64: message.imageBase64,
      imageMimeType: message.imageMimeType,
      originalImagePath: message.originalImagePath,
      originalImageMimeType: message.originalImageMimeType,
    );
  }

  final String messageId;
  final String? imageBase64;
  final String? imageMimeType;
  final String? originalImagePath;
  final String? originalImageMimeType;
}

final class PythonStagedInputs {
  PythonStagedInputs({
    required String workingDirectory,
    required List<Map<String, dynamic>> inputs,
  }) : workingDirectory = _requiredValue(workingDirectory, 'workingDirectory'),
       inputs = List<Map<String, dynamic>>.unmodifiable(
         inputs.map(freezePythonToolMap),
       );

  final String workingDirectory;
  final List<Map<String, dynamic>> inputs;
}

/// One staged directory paired with its replacement-resistant identity.
final class PythonStagingAllocation {
  PythonStagingAllocation({
    required this.stagedInputs,
    required this.directoryIdentity,
  }) {
    if (stagedInputs.workingDirectory != directoryIdentity.canonicalPath) {
      throw ArgumentError.value(
        directoryIdentity,
        'directoryIdentity',
        'The staging identity must match the working directory.',
      );
    }
  }

  final PythonStagedInputs stagedInputs;
  final PythonStagingDirectoryIdentity directoryIdentity;
}

enum PythonStagingAllocationDisposition {
  accepted,
  rejectedHandlerCleanup,
  rejectedPortCleanup,
}

/// Synchronous ownership transfer returned to the staging adapter.
final class PythonStagingAllocationAcknowledgement {
  const PythonStagingAllocationAcknowledgement(this.disposition);

  final PythonStagingAllocationDisposition disposition;

  bool get isAccepted =>
      disposition == PythonStagingAllocationDisposition.accepted;
  bool get portMustCleanup =>
      disposition == PythonStagingAllocationDisposition.rejectedPortCleanup;
}

final class PythonScriptApprovalKey {
  PythonScriptApprovalKey(this.code)
    : cacheArguments = Map<String, dynamic>.unmodifiable({'code': code});

  final String code;
  final Map<String, dynamic> cacheArguments;
}

final class PythonScriptApprovalRequest {
  const PythonScriptApprovalRequest({
    required this.toolRequest,
    required this.key,
    required this.stagedInputs,
  });

  final PythonScriptToolRequest toolRequest;
  final PythonScriptApprovalKey key;
  final PythonStagedInputs stagedInputs;

  String get toolCallId => toolRequest.toolCallId;
  String get code => key.code;
  String? get reason => toolRequest.reason;
}

final class PythonScriptExecutionRequest {
  PythonScriptExecutionRequest({
    required this.code,
    required this.allocation,
    required Object? timeoutSeconds,
  }) : arguments = freezePythonToolMap({
         'code': code,
         'working_directory': allocation.stagedInputs.workingDirectory,
         'inputs': allocation.stagedInputs.inputs,
         'timeout_seconds': ?timeoutSeconds,
       });

  final String code;
  final PythonStagingAllocation allocation;
  final Map<String, dynamic> arguments;

  PythonStagedInputs get stagedInputs => allocation.stagedInputs;
  PythonStagingDirectoryIdentity get directoryIdentity =>
      allocation.directoryIdentity;
}

/// Reports each allocation before the staging Future settles.
///
/// The port must call this exactly once for every created directory. It must
/// synchronously clean an allocation when the acknowledgement requires port
/// cleanup, and it must never invoke this callback after its Future settles.
typedef PythonStagingAllocationCallback =
    PythonStagingAllocationAcknowledgement Function(
      PythonStagingAllocation allocation,
    );

abstract interface class PythonInputStagingPort {
  Future<PythonScriptCompletion<Object?>> stage(
    PythonStagingAttempt attempt,
    PythonStagingLeaseToken token,
    PythonInputAttachment? attachment,
    PythonStagingAllocationCallback onAllocated,
  );

  Future<PythonScriptCompletion<PythonStagingCleanupOutcome>> release(
    PythonStagingCleanupClaim claim,
  );
}

enum PythonStagingCleanupOutcome {
  deleted,
  alreadyAbsent,
  identityMismatch,
  failed;

  bool get isSettled => this == deleted || this == alreadyAbsent;
}

abstract interface class PythonScriptExecutionPort {
  Future<PythonScriptCompletion<McpToolResult>> execute(
    PythonStagingAttempt attempt,
    PythonScriptExecutionRequest request,
  );
}

abstract interface class PythonScriptApprovalPort {
  PythonScriptCompletion<McpToolResult?> lookupDenial(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
  );

  Future<PythonScriptCompletion<ToolApprovalGateDecision>> resolveGate(
    PythonStagingAttempt attempt,
    PythonScriptApprovalRequest request,
  );

  Future<PythonScriptCompletion<bool>> requestManualApproval(
    PythonStagingAttempt attempt,
    PythonScriptApprovalRequest request,
  );

  PythonScriptCompletion<Object?> rememberDenial(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
    McpToolResult result,
  );

  PythonScriptCompletion<Object?> rememberResult(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
    McpToolResult result,
  );

  PythonScriptCompletion<McpToolResult?> expiredResult(
    PythonStagingAttempt attempt,
  );
}

/// Internal handler outcome kept separate from the bounded collaborator.
final class PythonStagedHandlerOutcome {
  const PythonStagedHandlerOutcome._({
    required this.result,
    required this.executed,
    required this.effectsUncertain,
    required this.cacheResult,
  });

  factory PythonStagedHandlerOutcome.before(McpToolResult result) =>
      PythonStagedHandlerOutcome._(
        result: result,
        executed: false,
        effectsUncertain: false,
        cacheResult: false,
      );

  factory PythonStagedHandlerOutcome.executed(
    McpToolResult result, {
    required bool cacheResult,
  }) => PythonStagedHandlerOutcome._(
    result: result,
    executed: true,
    effectsUncertain: false,
    cacheResult: cacheResult,
  );

  factory PythonStagedHandlerOutcome.uncertain(McpToolResult result) =>
      PythonStagedHandlerOutcome._(
        result: result,
        executed: true,
        effectsUncertain: true,
        cacheResult: false,
      );

  final McpToolResult result;
  final bool executed;
  final bool effectsUncertain;
  final bool cacheResult;
}

String _requiredValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name);
  return normalized;
}
