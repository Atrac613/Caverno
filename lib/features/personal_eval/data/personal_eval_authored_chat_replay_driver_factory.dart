import 'dart:io';

import '../../chat/data/datasources/chat_datasource.dart';
import '../../chat/data/datasources/llm_session_log_store.dart';
import '../domain/entities/personal_eval_case.dart';
import '../domain/services/live_personal_eval_case_runner.dart';
import '../domain/services/personal_eval_verification_runner.dart';
import 'personal_eval_authored_tool_dispatcher.dart';
import 'personal_eval_chat_replay_turn_driver.dart';

/// Builds a live replay driver whose tools are scoped to one authored fixture.
class PersonalEvalAuthoredChatReplayDriverFactory {
  const PersonalEvalAuthoredChatReplayDriverFactory({
    required ChatDataSource dataSource,
    required LlmSessionLogStore sessionLogStore,
    required String model,
    required PersonalEvalVerificationRunner verificationRunner,
    int maxTokens = 4096,
    required int maxTurns,
    required int maxToolCalls,
    double temperature = 0.2,
    String runId = '',
  }) : _dataSource = dataSource,
       _sessionLogStore = sessionLogStore,
       _model = model,
       _verificationRunner = verificationRunner,
       _maxTokens = maxTokens,
       _maxTurns = maxTurns,
       _maxToolCalls = maxToolCalls,
       _temperature = temperature,
       _runId = runId;

  final ChatDataSource _dataSource;
  final LlmSessionLogStore _sessionLogStore;
  final String _model;
  final PersonalEvalVerificationRunner _verificationRunner;
  final int _maxTokens;
  final int _maxTurns;
  final int _maxToolCalls;
  final double _temperature;
  final String _runId;

  PersonalEvalReplayTurnDriver call(
    String workingDirectory,
    PersonalEvalCase evalCase,
  ) {
    final dispatcher = PersonalEvalAuthoredToolDispatcher(
      root: Directory(workingDirectory),
      verificationCommand: evalCase.verificationCommand ?? '',
      verificationRunner: _verificationRunner,
    );
    return PersonalEvalChatReplayTurnDriver(
      dataSource: _dataSource,
      sessionLogStore: _sessionLogStore,
      model: _model,
      workingDirectory: workingDirectory,
      maxTokens: _maxTokens,
      maxTurns: _maxTurns,
      maxToolCalls: _maxToolCalls,
      temperature: _temperature,
      runId: _runId,
      toolDefinitions: dispatcher.getOpenAiToolDefinitions,
      dispatchToolCall: dispatcher.dispatch,
    );
  }
}
