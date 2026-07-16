import '../entities/tool_call_info.dart';
import 'tool_call_execution_policy.dart';

class SuccessfulReadResultReplayCache {
  SuccessfulReadResultReplayCache({
    ToolCallExecutionPolicy executionPolicy = const ToolCallExecutionPolicy(),
  }) : _executionPolicy = executionPolicy;

  final ToolCallExecutionPolicy _executionPolicy;
  final Map<String, String> _resultsByKey = <String, String>{};
  final Map<String, int> _replayCountsByKey = <String, int>{};
  int? _interactionGeneration;

  bool shouldSuppressAdditionalReplay({
    required ToolCallInfo toolCall,
    required int interactionGeneration,
    required int mutationGeneration,
    ProjectPathResolver? resolveProjectPath,
  }) {
    _resetForInteraction(interactionGeneration);
    final key = _keyFor(
      toolCall,
      mutationGeneration: mutationGeneration,
      resolveProjectPath: resolveProjectPath,
    );
    if (key == null || !_resultsByKey.containsKey(key)) {
      return false;
    }
    return (_replayCountsByKey[key] ?? 0) >= 1;
  }

  String? lookup({
    required ToolCallInfo toolCall,
    required int interactionGeneration,
    required int mutationGeneration,
    ProjectPathResolver? resolveProjectPath,
  }) {
    _resetForInteraction(interactionGeneration);
    final key = _keyFor(
      toolCall,
      mutationGeneration: mutationGeneration,
      resolveProjectPath: resolveProjectPath,
    );
    if (key == null) {
      return null;
    }
    final result = _resultsByKey[key];
    if (result != null) {
      _replayCountsByKey[key] = (_replayCountsByKey[key] ?? 0) + 1;
    }
    return result;
  }

  void record({
    required ToolCallInfo toolCall,
    required String result,
    required bool isSuccess,
    required int interactionGeneration,
    required int mutationGeneration,
    ProjectPathResolver? resolveProjectPath,
  }) {
    _resetForInteraction(interactionGeneration);
    if (!isSuccess) {
      return;
    }
    final key = _keyFor(
      toolCall,
      mutationGeneration: mutationGeneration,
      resolveProjectPath: resolveProjectPath,
    );
    if (key != null) {
      _resultsByKey[key] = result;
      _replayCountsByKey.putIfAbsent(key, () => 0);
    }
  }

  String? _keyFor(
    ToolCallInfo toolCall, {
    required int mutationGeneration,
    ProjectPathResolver? resolveProjectPath,
  }) {
    if (toolCall.name.trim().toLowerCase() != 'read_file') {
      return null;
    }
    final semanticKey = _executionPolicy.toolCallDedupKey(
      toolCall.name,
      toolCall.arguments,
      resolveProjectPath: resolveProjectPath,
      excludeNonSemanticKeys: true,
    );
    return '$mutationGeneration:$semanticKey';
  }

  void _resetForInteraction(int interactionGeneration) {
    if (_interactionGeneration == interactionGeneration) {
      return;
    }
    _interactionGeneration = interactionGeneration;
    _resultsByKey.clear();
    _replayCountsByKey.clear();
  }
}
