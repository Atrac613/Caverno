import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'git_tools.dart';
import 'mcp_tool_result_normalizer.dart';

class GitFinishWorktreeSessionTool {
  const GitFinishWorktreeSessionTool._();

  static const String toolName = 'git_finish_worktree_session';

  static Map<String, dynamic> get toolDefinition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Finish a coding session running in a git worktree. This inspects '
          'git worktree list --porcelain, finds the worktree where the base '
          'branch is checked out, merges the current worktree branch from '
          'that base worktree, and optionally removes the finished worktree. '
          'Use this when the user asks to merge or close the current worktree '
          'session instead of guessing where main is checked out.',
      'parameters': {
        'type': 'object',
        'properties': {
          'worktree_path': {
            'type': 'string',
            'description':
                'Absolute path to the feature worktree to finish. Optional '
                'when the current coding conversation is already associated '
                'with a worktree.',
          },
          'base_branch': {
            'type': 'string',
            'description':
                'Destination branch to merge into. Defaults to "main".',
          },
          'remove_worktree': {
            'type': 'boolean',
            'description':
                'Remove the feature worktree after a successful merge. '
                'Defaults to true.',
          },
          'merge_message': {
            'type': 'string',
            'description':
                'Optional merge commit message. Usually omit this and let git '
                'use its default message.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable explanation shown to the user in the '
                'confirmation dialog.',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Future<McpToolResult> execute(Map<String, dynamic> arguments) async {
    final worktreePath = (arguments['worktree_path'] as String?)?.trim() ?? '';
    final baseBranchValue = (arguments['base_branch'] as String?)?.trim();
    final baseBranch = (baseBranchValue?.isNotEmpty ?? false)
        ? baseBranchValue!
        : 'main';
    final removeWorktree = arguments.containsKey('remove_worktree')
        ? _asBool(arguments['remove_worktree'])
        : true;
    final mergeMessage = (arguments['merge_message'] as String?)?.trim();
    if (worktreePath.isEmpty) {
      return const McpToolResult(
        toolName: toolName,
        result: '',
        isSuccess: false,
        errorMessage: 'worktree_path is required',
      );
    }
    try {
      final result = await GitTools.finishWorktreeSession(
        worktreePath: worktreePath,
        baseBranch: baseBranch,
        removeWorktree: removeWorktree,
        mergeMessage: mergeMessage,
      );
      final normalizedResult = McpToolResultNormalizer.fromCommandPayload(
        toolName: toolName,
        result: result,
        toolLabel: 'Finish worktree session',
      );
      if (!normalizedResult.isSuccess) {
        appLog(
          '[McpToolService] Finish worktree session failed: '
          '${normalizedResult.errorMessage}',
        );
        return normalizedResult;
      }
      appLog('[McpToolService] Worktree session finished successfully');
      return normalizedResult;
    } catch (error) {
      appLog('[McpToolService] Finish worktree session error: $error');
      return McpToolResultNormalizer.failure(
        toolName: toolName,
        errorMessage: error.toString(),
      );
    }
  }

  static bool _asBool(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'y';
    }
    return false;
  }
}
