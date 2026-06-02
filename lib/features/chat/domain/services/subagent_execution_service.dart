import '../../data/datasources/chat_datasource.dart';
import '../../../routines/data/routine_tool_runner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import '../entities/subagent_task.dart';
import '../entities/tool_call_info.dart';
import 'subagent_tool_policy.dart';

/// Runs a single subagent delegation.
///
/// Reuses [RoutineToolRunner] — the existing non-interactive agent tool loop —
/// so subagents share the parent's tool execution semantics. The parent's
/// `_dispatchToolCall` is injected directly, which means high-risk tools are
/// escalated to the same user-approval dialog as the main loop.
class SubagentExecutionService {
  SubagentExecutionService({
    required ChatDataSource dataSource,
    RoutineToolRunner? toolRunner,
  }) : _toolRunner = toolRunner ?? RoutineToolRunner(dataSource: dataSource);

  final RoutineToolRunner _toolRunner;

  /// Upper bound on the summary returned to the parent, so a runaway child
  /// cannot blow up the parent's context window.
  static const int _maxOutputLength = 16000;

  /// Executes the delegated task and returns a settled [SubagentTask].
  ///
  /// [tools] must already be filtered through
  /// [SubagentToolPolicy.filterInheritedToolDefinitions] by the caller.
  Future<SubagentTask> run({
    required String id,
    required String description,
    required String prompt,
    required List<Map<String, dynamic>> tools,
    required Future<McpToolResult> Function(ToolCallInfo toolCall)
    dispatchToolCall,
    required String model,
    required double temperature,
    required int maxTokens,
    String? parentToolUseId,
    bool isBackground = false,
  }) async {
    final startedAt = DateTime.now();
    final messages = <Message>[
      Message(
        id: 'subagent_system_$id',
        content: _buildSystemPrompt(description: description, tools: tools),
        role: MessageRole.system,
        timestamp: startedAt,
      ),
      Message(
        id: 'subagent_user_$id',
        content: prompt,
        role: MessageRole.user,
        timestamp: startedAt,
      ),
    ];

    try {
      final result = await _toolRunner.execute(
        messages: messages,
        tools: tools,
        dispatchToolCall: dispatchToolCall,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      final output = _capOutput(result.output);
      return SubagentTask(
        id: id,
        status: SubagentTaskStatus.completed,
        description: description,
        parentToolUseId: parentToolUseId,
        prompt: prompt,
        output: output,
        resultSummary: output,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        isBackground: isBackground,
      );
    } catch (error) {
      return SubagentTask(
        id: id,
        status: SubagentTaskStatus.failed,
        description: description,
        parentToolUseId: parentToolUseId,
        prompt: prompt,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        isBackground: isBackground,
        error: error.toString(),
      );
    }
  }

  String _buildSystemPrompt({
    required String description,
    required List<Map<String, dynamic>> tools,
  }) {
    final toolNames = tools
        .map(SubagentToolPolicy.toolName)
        .where((name) => name.isNotEmpty)
        .join(', ');
    return [
      'You are a focused subagent delegated a single sub-task by the main '
          'assistant.',
      'Task: $description',
      'Complete the task autonomously using the available tools, then return a '
          'concise result summary. Do not ask the user questions; work with '
          'what you have and state any assumptions you made.',
      if (toolNames.isNotEmpty) 'Available tools: $toolNames',
      'Keep the final answer self-contained: the main assistant only sees your '
          'summary, not your intermediate steps.',
    ].join('\n');
  }

  String _capOutput(String output) {
    final trimmed = output.trim();
    if (trimmed.length <= _maxOutputLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, _maxOutputLength)}\n...[truncated]';
  }
}
