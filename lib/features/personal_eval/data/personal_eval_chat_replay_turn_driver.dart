import '../../../core/types/workspace_mode.dart';
import '../../chat/data/datasources/chat_datasource.dart';
import '../../chat/data/datasources/llm_session_log_store.dart';
import '../../chat/domain/entities/message.dart';
import '../domain/entities/personal_eval_case.dart';
import '../domain/services/live_personal_eval_case_runner.dart';

/// LL19: a lightweight live [PersonalEvalReplayTurnDriver].
///
/// Drives the candidate model through a case's prompt with a single
/// chat-datasource completion and captures the scoped session log so the LL12
/// summary parser can score it. This first cut intentionally runs no tool loop:
/// the full tool-executing driver (the candidate actually editing files) is a
/// later slice. Verification still runs against [workingDirectory], so a case
/// whose repo already reflects the recorded work can be scored end-to-end.
class PersonalEvalChatReplayTurnDriver implements PersonalEvalReplayTurnDriver {
  PersonalEvalChatReplayTurnDriver({
    required ChatDataSource dataSource,
    required LlmSessionLogStore sessionLogStore,
    required String model,
    required String workingDirectory,
    String runId = '',
    double temperature = 0.2,
    int maxTokens = 4096,
    DateTime Function() now = DateTime.now,
  }) : _dataSource = dataSource,
       _sessionLogStore = sessionLogStore,
       _model = model,
       _workingDirectory = workingDirectory,
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
      final startedAt = _now();
      try {
        await _dataSource.createChatCompletion(
          messages: [
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
          ],
          model: _model,
          temperature: _temperature,
          maxTokens: _maxTokens,
        );
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
