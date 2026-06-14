// Same-library extension for tool-result observation and profile telemetry.
//
// Riverpod marks `ref` as `@protected`, which is not aware of extensions even
// in the same library.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierToolResultTelemetry on ChatNotifier {
  Future<void> _recordModelEditApplyTelemetry(ToolResultInfo toolResult) async {
    final editObservation = ModelEditApplyTelemetryService.classifyToolResult(
      toolResult,
    );
    final baselineProfile =
        _settings.effectiveModelCapabilityProfile ??
        ModelCapabilityProfile(
          id: '',
          provider: _settings.llmProvider,
          baseUrl: _settings.baseUrl,
          model: _settings.effectiveModel,
        ).normalizedForPersistence();
    final updatedProfile = ModelEditApplyTelemetryService.recordToolResult(
      profile: baselineProfile,
      toolResult: toolResult,
    );
    if (updatedProfile == null || !ref.mounted) {
      return;
    }
    try {
      await ref
          .read(settingsNotifierProvider.notifier)
          .upsertModelCapabilityProfile(updatedProfile);
      if (ref.mounted) {
        _settings = ref.read(settingsNotifierProvider);
      }
      if (editObservation?.isFailure ?? false) {
        await _recordRuntimeSamplerFeedback(
          const LlmSamplerRuntimeFeedbackSignal(
            requestClass: LlmSamplerRequestClass.toolLoop,
            editApplyFailureCount: 1,
          ),
        );
      }
    } catch (_) {
      // Edit telemetry should never interrupt the primary chat/tool loop.
    }
  }

  Future<void> _recordMalformedToolCallRuntimeFeedback(String message) {
    if (!LlmSamplerRuntimeFeedbackService.looksLikeMalformedToolCallFailure(
      message,
    )) {
      return Future<void>.value();
    }
    return _recordRuntimeSamplerFeedback(
      const LlmSamplerRuntimeFeedbackSignal(
        requestClass: LlmSamplerRequestClass.toolLoop,
        malformedToolCallCount: 1,
      ),
    );
  }

  Future<void> _recordToolLoopRepetitionRuntimeFeedback() {
    return _recordRuntimeSamplerFeedback(
      const LlmSamplerRuntimeFeedbackSignal(
        requestClass: LlmSamplerRequestClass.toolLoop,
        repetitionDetected: true,
      ),
    );
  }

  Future<void> _recordRuntimeSamplerFeedback(
    LlmSamplerRuntimeFeedbackSignal signal,
  ) async {
    final baselineProfile =
        _settings.effectiveModelCapabilityProfile ??
        ModelCapabilityProfile(
          id: '',
          provider: _settings.llmProvider,
          baseUrl: _settings.baseUrl,
          model: _settings.effectiveModel,
        ).normalizedForPersistence();
    final result = const LlmSamplerRuntimeFeedbackService().recordSignal(
      profile: baselineProfile,
      signal: signal,
    );
    if (result == null || !ref.mounted) {
      return;
    }
    try {
      await ref
          .read(settingsNotifierProvider.notifier)
          .upsertModelCapabilityProfile(result.profile);
      if (ref.mounted) {
        _settings = ref.read(settingsNotifierProvider);
      }
    } catch (_) {
      // Runtime feedback must never interrupt the primary chat/tool loop.
    }
  }

  void _recordContentToolResult({
    required ToolCallInfo toolCall,
    required String result,
  }) {
    _recordContentToolResultInfo(
      ToolResultInfo(
        id: toolCall.id,
        name: toolCall.name,
        arguments: Map<String, dynamic>.unmodifiable(toolCall.arguments),
        result: result,
      ),
    );
  }

  void _recordContentToolResultInfo(ToolResultInfo toolResult) {
    _latestContentToolResults.add(toolResult);
  }

  String _buildContentToolFailureResult(String toolName, String? errorMessage) {
    final error = (errorMessage ?? 'Tool execution failed').trim();
    final code = _contentToolFailureCode(error);
    return jsonEncode({'toolName': toolName, 'error': error, 'code': code});
  }

  String _contentToolFailureCode(String errorMessage) {
    final normalized = errorMessage.toLowerCase();
    if (normalized.contains('no matching tool available')) {
      return 'tool_not_available';
    }
    if (normalized.contains('old_text was not found in the target file')) {
      return 'edit_mismatch';
    }
    if (normalized.contains('permission_denied')) {
      return 'permission_denied';
    }
    if (normalized.contains('timeout')) {
      return 'timeout';
    }
    return 'tool_execution_failed';
  }
}
