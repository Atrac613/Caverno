import 'dart:convert';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'git_tools.dart';

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
      final failureMessage = _commandResultFailureMessage(result);
      if (failureMessage != null) {
        appLog(
          '[McpToolService] Finish worktree session failed: $failureMessage',
        );
        return McpToolResult(
          toolName: toolName,
          result: result,
          isSuccess: false,
          errorMessage: failureMessage,
        );
      }
      appLog('[McpToolService] Worktree session finished successfully');
      return McpToolResult(toolName: toolName, result: result, isSuccess: true);
    } catch (error) {
      appLog('[McpToolService] Finish worktree session error: $error');
      return McpToolResult(
        toolName: toolName,
        result: '',
        isSuccess: false,
        errorMessage: error.toString(),
      );
    }
  }

  static String? _commandResultFailureMessage(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is! Map<String, dynamic>) return null;

      final error = decoded['error'];
      if (error is String && error.trim().isNotEmpty) {
        return error.trim();
      }

      final exitCode = decoded['exit_code'];
      if (exitCode is num && exitCode.toInt() != 0) {
        final stderr = decoded['stderr'];
        final stdout = decoded['stdout'];
        final detail = stderr is String && stderr.trim().isNotEmpty
            ? stderr.trim()
            : stdout is String && stdout.trim().isNotEmpty
            ? stdout.trim()
            : null;
        return detail == null
            ? 'Finish worktree session exited with code ${exitCode.toInt()}'
            : 'Finish worktree session exited with code '
                  '${exitCode.toInt()}: $detail';
      }
    } catch (_) {
      return null;
    }
    return null;
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
