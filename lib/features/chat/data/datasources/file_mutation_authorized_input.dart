import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import 'file_mutation_runtime_contract.dart';
import 'project_mutation_path_fence.dart';

export 'file_mutation_runtime_contract.dart';
export 'project_mutation_path_fence.dart';

/// Builds the runtime input, then re-binds it to the path the fence cleared.
///
/// Two constraints meet here and neither can move. The snapshot has to freeze
/// before the first `await`, or a caller mutating its own argument map
/// mid-flight poisons it. And SEC4.4b rewrites the operation path to the
/// fence's canonical form before any effect, which resolves symlinks the
/// caller's path did not.
///
/// Minting the identity once, up front, satisfied the first and broke the
/// second: `_requirePath` then compared a resolved path against an unresolved
/// one, so every mutation under a symlinked root failed as "File mutation path
/// identity mismatch" -- on macOS that is anything under `/tmp`. Freezing
/// first and re-binding afterwards satisfies both. The second snapshot is
/// taken from the first, never from the caller's map, so the race stays shut.
///
/// Re-binding also strengthens the guard it repairs: the attempt is now bound
/// to the file the fence actually authorized rather than to the string the
/// model supplied.
Future<FileMutationRuntimeInput> authorizedFileMutationInput({
  required ChatTurnOwner owner,
  required ToolCallInfo toolCall,
  required ToolApprovalMode approvalMode,
  required String? projectRoot,
  required Map<String, dynamic> resolvedArguments,
  required List<Message> conversationMessages,
  required bool hasUntrustedInfluence,
  required FileMutationPathAuthorizer authorizePath,
}) async {
  final input = FileMutationRuntimeInput(
    owner: owner,
    toolCall: toolCall,
    approvalMode: approvalMode,
    projectRoot: projectRoot,
    resolvedArguments: resolvedArguments,
    conversationMessages: conversationMessages,
    hasUntrustedInfluence: hasUntrustedInfluence,
  );
  final authorization = await authorizePath(
    toolName: toolCall.name,
    projectRoot: projectRoot,
    rawPath: (input.resolvedArguments['path'] as String?)?.trim() ?? '',
  );
  final authorized = authorization.canonicalPath?.trim() ?? '';
  if (!authorization.isAllowed || authorized.isEmpty) {
    // Denial is the handler's to report, with its stable project_mutation_*
    // code. Hand back the untouched snapshot and let it fail closed there.
    return input;
  }
  return FileMutationRuntimeInput(
    owner: owner,
    toolCall: ToolCallInfo(
      id: input.identity.toolCallId,
      name: input.identity.toolName,
      arguments: input.rawArguments,
    ),
    approvalMode: approvalMode,
    projectRoot: projectRoot,
    resolvedArguments: {...input.resolvedArguments, 'path': authorized},
    conversationMessages: input.conversationMessages,
    hasUntrustedInfluence: hasUntrustedInfluence,
  );
}
