import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'local_command_tool_handler.dart';

typedef BackgroundProcessIdentity = ({
  String externalProcessId,
  String backendProcessId,
  bool isRunning,
});

typedef BackgroundProcessStartResult = ({
  McpToolResult result,
  BackgroundProcessIdentity? identity,
  bool startedByRequest,
});

abstract interface class BackgroundProcessExecutionPort {
  /// Owner-expired completions compensate starts; new starts include identity.
  Future<LocalCommandCompletion<BackgroundProcessStartResult>> start(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest operation,
  );

  /// Required-termination completions guarantee the target is no longer active.
  Future<LocalCommandCompletion<McpToolResult>> cancel(
    ChatTurnOwner owner,
    String toolCallId,
    BackgroundProcessIdentity identity, {
    bool requireTermination = false,
  });
}

/// A missing ID and an ID owned by another turn both complete with null.
abstract interface class BackgroundProcessLookupPort {
  Future<LocalCommandCompletion<BackgroundProcessIdentity?>> lookup(
    ChatTurnOwner owner,
    String toolCallId,
    String externalProcessId,
  );
}

final class BackgroundProcessToolRequest {
  BackgroundProcessToolRequest({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required this.allowedWorkingDirectoryRoot,
    required Map<String, dynamic> arguments,
    this.defaultWorkingDirectory,
    this.isRemoteInteraction = false,
  }) : arguments = freezeLocalCommandArguments(arguments);

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String allowedWorkingDirectoryRoot;
  final String? defaultWorkingDirectory;
  final Map<String, dynamic> arguments;
  final bool isRemoteInteraction;
}
