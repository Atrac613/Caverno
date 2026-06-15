import '../../../core/types/workspace_mode.dart';
import '../../chat/data/datasources/chat_datasource.dart';
import '../../chat/data/datasources/llm_session_log_store.dart';
import '../../chat/domain/entities/mcp_tool_entity.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/entities/tool_call_info.dart';
import '../../routines/data/routine_tool_runner.dart';
import '../domain/entities/personal_eval_case.dart';
import '../domain/services/live_personal_eval_case_runner.dart';

/// LL19: a live [PersonalEvalReplayTurnDriver] that drives the candidate model
/// through a case end-to-end and captures the scoped session log.
///
/// When tool capabilities are provided ([toolDefinitions] + [dispatchToolCall])
/// it runs the full non-interactive agent loop via [RoutineToolRunner] — the
/// candidate can actually read/edit files and run commands, dispatched through
/// the same raw [McpToolService] execution routines use. This obeys the
/// RoutineToolPolicy trust model (no interactive approval), matching how LL18
/// will replay cases unattended.
///
/// With no tool capabilities it falls back to a single completion: the
/// candidate's response is still logged for scoring. Verification runs against
/// [workingDirectory] in both modes.
class PersonalEvalChatReplayTurnDriver implements PersonalEvalReplayTurnDriver {
  PersonalEvalChatReplayTurnDriver({
    required ChatDataSource dataSource,
    required LlmSessionLogStore sessionLogStore,
    required String model,
    required String workingDirectory,
    List<Map<String, dynamic>> Function()? toolDefinitions,
    Future<McpToolResult> Function(ToolCallInfo toolCall)? dispatchToolCall,
    RoutineToolRunner? toolRunner,
    String runId = '',
    double temperature = 0.2,
    int maxTokens = 4096,
    DateTime Function() now = DateTime.now,
  }) : _dataSource = dataSource,
       _sessionLogStore = sessionLogStore,
       _model = model,
       _workingDirectory = workingDirectory,
       _toolDefinitions = toolDefinitions,
       _dispatchToolCall = dispatchToolCall,
       _toolRunner = toolRunner ?? RoutineToolRunner(dataSource: dataSource),
       _runId = runId,
       _temperature = temperature,
       _maxTokens = maxTokens,
       _now = now;

  static const _systemPrompt =
      'You are replaying a recorded coding task to evaluate a model. Complete '
      'the task described by the user exactly as you normally would.';

  final ChatDataSource _dataSource;
  final LlmSessionLogStore _sessionLogStore;
  final String _model;
  final String _workingDirectory;
  final List<Map<String, dynamic>> Function()? _toolDefinitions;
  final Future<McpToolResult> Function(ToolCallInfo toolCall)?
  _dispatchToolCall;
  final RoutineToolRunner _toolRunner;
  final String _runId;
  final double _temperature;
  final int _maxTokens;
  final DateTime Function() _now;

  @override
  Future<PersonalEvalReplayTurnResult> drive(PersonalEvalCase evalCase) async {
    final context = LlmSessionLogContext(
      workspaceMode: _workspaceModeFor(evalCase),
      sessionId: _sessionId(evalCase),
      sessionTitle: evalCase.title.trim().isEmpty
          ? null
          : evalCase.title.trim(),
      phase: 'personal_eval_replay',
    );

    return LlmSessionLogContext.run(context, () async {
      String? error;
      try {
        await _runTurn(evalCase);
      } catch (e) {
        // A failed turn never aborts the replay run: the error is surfaced and
        // the orchestrator records the case as inconclusive.
        error = e.toString();
      }

      // The session log is written by SessionLoggingChatDataSource within this
      // zone; read it back for the summary. It is absent when session logging
      // is disabled, in which case the summary is simply empty.
      final file = await _sessionLogStore.fileForContext(context);
      final logContents = file.existsSync() ? await file.readAsString() : '';

      return PersonalEvalReplayTurnResult(
        logPath: file.path,
        logContents: logContents,
        workingDirectory: _workingDirectory,
        error: error,
      );
    });
  }

  Future<void> _runTurn(PersonalEvalCase evalCase) async {
    final messages = _buildMessages(evalCase);
    final tools = _toolDefinitions?.call() ?? const <Map<String, dynamic>>[];
    final dispatch = _dispatchToolCall;

    if (tools.isNotEmpty && dispatch != null) {
      await _toolRunner.execute(
        messages: messages,
        tools: tools,
        dispatchToolCall: dispatch,
        model: _model,
        temperature: _temperature,
        maxTokens: _maxTokens,
      );
      return;
    }

    await _dataSource.createChatCompletion(
      messages: messages,
      model: _model,
      temperature: _temperature,
      maxTokens: _maxTokens,
    );
  }

  List<Message> _buildMessages(PersonalEvalCase evalCase) {
    final startedAt = _now();
    return [
      Message(
        id: 'personal_eval_replay_system',
        role: MessageRole.system,
        content: _systemPrompt,
        timestamp: startedAt,
      ),
      Message(
        id: 'personal_eval_replay_user',
        role: MessageRole.user,
        content: evalCase.normalizedPrompt,
        timestamp: startedAt,
      ),
    ];
  }

  String _sessionId(PersonalEvalCase evalCase) {
    final suffix = _runId.trim().isEmpty ? '' : '-$_runId';
    return 'personal-eval-replay-${evalCase.caseId}$suffix';
  }

  WorkspaceMode _workspaceModeFor(PersonalEvalCase evalCase) {
    final recorded = evalCase.workspaceMode?.trim();
    return WorkspaceMode.values.firstWhere(
      (mode) => mode.name == recorded,
      orElse: () => WorkspaceMode.coding,
    );
  }
}
