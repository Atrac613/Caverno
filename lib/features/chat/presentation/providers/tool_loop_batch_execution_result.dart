import '../../domain/entities/tool_call_info.dart';

enum ToolLoopBatchStatus { completed, textResponse, cancelled }

class ToolLoopBatchExecutionResult {
  const ToolLoopBatchExecutionResult({
    required this.status,
    required this.batchToolResults,
    required this.pendingBatchCalls,
    required this.commandRetryGeneration,
    required this.stateChangeGeneration,
    this.terminalSuccessMessage,
  });

  factory ToolLoopBatchExecutionResult.completed({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolCallInfo> pendingBatchCalls,
    required int commandRetryGeneration,
    required int stateChangeGeneration,
    String? terminalSuccessMessage,
  }) {
    return ToolLoopBatchExecutionResult(
      status: ToolLoopBatchStatus.completed,
      batchToolResults: batchToolResults,
      pendingBatchCalls: pendingBatchCalls,
      commandRetryGeneration: commandRetryGeneration,
      stateChangeGeneration: stateChangeGeneration,
      terminalSuccessMessage: terminalSuccessMessage,
    );
  }

  factory ToolLoopBatchExecutionResult.textResponse({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolCallInfo> pendingBatchCalls,
    required int commandRetryGeneration,
    required int stateChangeGeneration,
  }) {
    return ToolLoopBatchExecutionResult(
      status: ToolLoopBatchStatus.textResponse,
      batchToolResults: batchToolResults,
      pendingBatchCalls: pendingBatchCalls,
      commandRetryGeneration: commandRetryGeneration,
      stateChangeGeneration: stateChangeGeneration,
    );
  }

  factory ToolLoopBatchExecutionResult.cancelled({
    required int commandRetryGeneration,
    required int stateChangeGeneration,
  }) {
    return ToolLoopBatchExecutionResult(
      status: ToolLoopBatchStatus.cancelled,
      batchToolResults: const [],
      pendingBatchCalls: const [],
      commandRetryGeneration: commandRetryGeneration,
      stateChangeGeneration: stateChangeGeneration,
    );
  }

  final ToolLoopBatchStatus status;
  final List<ToolResultInfo> batchToolResults;
  final List<ToolCallInfo> pendingBatchCalls;
  final int commandRetryGeneration;
  final int stateChangeGeneration;
  final String? terminalSuccessMessage;

  bool get didCancel => status == ToolLoopBatchStatus.cancelled;

  bool get hasTextResponse => status == ToolLoopBatchStatus.textResponse;
}
