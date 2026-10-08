import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../data/datasources/git_tools.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_loop/recent_read_result_carry.dart';

/// What a `/review` turn may do, enforced rather than requested.
///
/// The review prompt says "do not edit files or change Git state", and until
/// this existed that sentence was the whole boundary. Session e3a9f3f0's review
/// turns were offered all 51 tools, `write_file`, `edit_file` and
/// `delete_file` among them, and the loop's own recovery prompts told the model
/// its "next reply must either modify a saved target file or run the saved
/// validation command" -- the saved task being one the thread had already
/// finished. The hosted reviewer ignored that; nothing stopped a weaker one.
///
/// A review inspects and verifies, which is what the Anabasis parent guard
/// also allows, and it stays closed the same way: an unclassified tool is not
/// proof of safety. Tests run, because a review may check its findings.
///
/// Lives here rather than in `domain/services` because that directory is at the
/// RAG2 development declaration's 512-file ceiling.
final class ReadOnlyReviewScope {
  const ReadOnlyReviewScope();

  static const refusedCode = 'read_only_review_refused';

  /// Tools whose authority the generic classifier cannot infer from a name.
  static const _namedExceptions = <String>{
    'tool_search',
    'ask_user_question',
    'load_skill',
  };

  /// Tools whose effect depends on the command they carry, so they are offered
  /// and judged per call by [evaluate].
  static const _commandTools = <String>{
    'local_execute_command',
    'git_execute_command',
  };

  /// Keep the fixed review catalog focused on repository inspection. Web
  /// readers cover URL and pull-request scopes; other read-only tools need a
  /// separate reason to join the catalog instead of riding the general list.
  static const _initialToolNames = <String>{
    'git_execute_command',
    'list_directory',
    'read_file',
    'inspect_file',
    'find_files',
    'search_files',
    'local_execute_command',
    'run_tests',
    'http_get',
    'search_web',
    'load_skill',
  };

  /// The follow-up carry for a review turn.
  ///
  /// A review needs the diff and the files it touches at once, which the
  /// default budget -- sized to the median turn's 4.6 KB read-only set --
  /// cannot hold. e3a9f3f0's review read 8 distinct results totalling 22.6 KB,
  /// and its two changed files alone were 12.2 KB against the 8 KB default, so
  /// each read evicted another and 17 requests went by re-reading them. 32 KB
  /// holds that set with room for one more file, at about 8k tokens of
  /// prefill against the dedicated review endpoint a `/review` always routes
  /// to. The per-result cap doubles so one ordinary source file still fits.
  static const readResultCarry = RecentReadResultCarry(
    budgetBytes: 32 * 1024,
    maxResultBytes: 16 * 1024,
  );

  static const _classifier = ToolCapabilityClassifier();

  /// Whether [toolName] belongs in a review turn's tool definitions.
  bool offers(String toolName) =>
      _namedExceptions.contains(toolName) ||
      _commandTools.contains(toolName) ||
      _isReadOnly(_classifier.classify(toolName).commandEffect);

  bool offersInitially(String toolName) =>
      _initialToolNames.contains(toolName) && offers(toolName);

  /// The refusal for [toolCall], or `null` when a review may run it.
  McpToolResult? evaluate(ToolCallInfo toolCall) {
    if (_namedExceptions.contains(toolCall.name)) return null;
    final effect = _classifier
        .classify(toolCall.name, arguments: _asExecuted(toolCall))
        .commandEffect;
    if (_isReadOnly(effect)) return null;
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        ...ToolResultOrigin.refusal.marker,
        'code': refusedCode,
        'effect': effect.name,
        'error':
            'This turn is a read-only code review. It may inspect and run '
            'verification, but it may not change files, Git state, or '
            'anything outside the workspace.',
        'required_action':
            'Write the review from what you have inspected. Report a change '
            'you would make as a finding instead of applying it.',
      }),
      isSuccess: false,
      errorMessage: 'A read-only review cannot run ${toolCall.name}.',
    );
  }

  /// The git tool strips a leading `git` before it runs, and the classifier
  /// reads the first word as the verb; judged raw, `git diff` is a mutation.
  Map<String, dynamic> _asExecuted(ToolCallInfo toolCall) {
    final command = toolCall.arguments['command'];
    if (toolCall.name != 'git_execute_command' || command is! String) {
      return toolCall.arguments;
    }
    return {
      ...toolCall.arguments,
      'command': GitTools.normalizeCommand(command),
    };
  }

  bool _isReadOnly(ToolCommandEffect effect) =>
      effect == ToolCommandEffect.inspection ||
      effect == ToolCommandEffect.verification;
}
