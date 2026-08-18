import 'dart:convert';
import 'dart:io';

import '../../data/datasources/project_read_tool_authorizer.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';

/// Files outside the project root that a person has explicitly released.
///
/// The project read fence exists so a prompt injection or a model slip cannot
/// ship `~/.ssh` to a cloud endpoint, and that job is worth keeping. What it
/// lacked was any way for the person who understands a file to say yes to it,
/// which made "investigate this log" impossible from a coding session -- in
/// session 12b739d6 the turn spent eight LLM calls hunting for a read tool
/// that could reach outside the root before aborting.
///
/// A grant is deliberately narrow. It names one resolved file, never a
/// directory or a prefix, so releasing one log does not open the folder it
/// sits in. It is keyed on the canonical path, so a symlink repointed after
/// the prompt resolves to a target nobody approved. And it lives only in
/// memory, scoped to one conversation: investigating a directory of logs takes
/// several reads and re-prompting per turn only trains the reader to click
/// through, but nothing here outlives the session.
final class OutsideRootReadGrants {
  final Map<String, Set<String>> _byConversation = {};

  /// Canonical paths released in [conversationId], empty when it is unknown.
  Set<String> forConversation(String? conversationId) => conversationId == null
      ? const {}
      : _byConversation[conversationId] ?? const {};

  void grant({required String conversationId, required String canonicalPath}) =>
      _byConversation
          .putIfAbsent(conversationId, () => <String>{})
          .add(canonicalPath);

  /// Authorizes one read, asking [requestApproval] to release a file that
  /// sits outside the root.
  ///
  /// Only an out-of-root denial reaches the prompt: a missing file or a
  /// `~`/`..` path is a mistake to fix, not a decision to take. Requiring an
  /// absolute path is deliberate -- the prompt then shows the exact file, with
  /// no `~` for the reader to expand in their head. Callers with no live turn
  /// pass a null [owner] and the fence stays absolute.
  ///
  /// [onDecision] receives every release decision, approved or refused, so it
  /// reaches the same audit trail as every automated one. Without it this
  /// grant is the only approval in the app leaving no record, which is
  /// backwards for the narrowest permission Caverno asks for:
  /// `tool/sec_verify_logs.sh` would show the unbounded shell path and not
  /// this one.
  Future<ProjectReadToolAuthorization> authorizeRead({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String? projectRoot,
    required ChatTurnOwner? owner,
    required Future<bool> Function({
      required ChatTurnOwner owner,
      required String operation,
      required String path,
      required String preview,
      String? reason,
    })
    requestApproval,
    void Function({required String path, required bool approved})? onDecision,
    ProjectReadToolAuthorizer authorizer = const ProjectReadToolAuthorizer(),
  }) async {
    final authorization = await authorizer.authorize(
      toolName: toolName,
      arguments: arguments,
      projectRoot: projectRoot,
      approvedOutsideRootPaths: forConversation(owner?.conversationId),
    );
    if (owner == null || !authorization.isApprovable) return authorization;

    final canonicalPath = authorization.canonicalPath!;
    final approved = await requestApproval(
      owner: owner,
      operation: 'Read outside the project',
      path: canonicalPath,
      preview: await previewOf(canonicalPath),
      reason:
          'The assistant asked to read this file with $toolName. It is '
          'outside the open project, so its contents would be sent to the '
          'configured model endpoint.',
    );
    onDecision?.call(path: canonicalPath, approved: approved);
    if (!approved) {
      return ProjectReadToolAuthorization.denied(
        declinedResult(toolName: toolName, canonicalPath: canonicalPath),
      );
    }
    grant(conversationId: owner.conversationId, canonicalPath: canonicalPath);
    return authorizer.authorize(
      toolName: toolName,
      arguments: arguments,
      projectRoot: projectRoot,
      approvedOutsideRootPaths: {canonicalPath},
    );
  }

  /// A bounded head sample of [path], so the prompt shows what would actually
  /// be released rather than only its name.
  static Future<String> previewOf(String path) async {
    const maxPreviewChars = 2000;
    try {
      final file = File(path);
      if (!file.existsSync()) return '(the file no longer exists)';
      final length = await file.length();
      final head = length < maxPreviewChars ? length : maxPreviewChars;
      final bytes = await file.openRead(0, head).first;
      final text = utf8.decode(bytes, allowMalformed: true);
      return length > maxPreviewChars
          ? '$text\n... ($length bytes total)'
          : text;
    } on Object {
      // A preview is a courtesy; failing to build one must not decide the
      // approval either way.
      return '(preview unavailable)';
    }
  }

  /// The result returned when a person refuses to release [canonicalPath].
  ///
  /// Says plainly that another read tool will not help. The refusal that
  /// preceded this feature said only that the target was outside the project,
  /// and the model read that as a routing problem worth searching around.
  static McpToolResult declinedResult({
    required String toolName,
    required String canonicalPath,
  }) {
    const message = 'The user declined to release this file.';
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        'code': 'project_read_outside_root_denied',
        'error':
            '$message It is outside the project root, and every local read '
            'tool is bound to that root, so do not ask again for this path in '
            'this turn and do not try another tool. Continue without the file '
            'or ask the user what to do instead.',
        'path': canonicalPath,
      }),
      isSuccess: false,
      errorMessage: message,
    );
  }
}
