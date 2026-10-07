import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/system_prompt_constants.dart';
import '../../../../core/services/apple_foundation_models_platform_client.dart';
import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/data/datasources/embeddings_client.dart';
import '../../../chat/data/datasources/mcp_goal_routine_tool_definitions.dart';
import '../../../chat/data/datasources/mcp_tool_service.dart';
import '../../../chat/data/datasources/openai_modalities_probe.dart';
import '../../../chat/data/datasources/openai_parameter_support_probe.dart';
import '../../../chat/data/datasources/strict_tool_choice_policy.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/services/goal_update_ack.dart';
import '../../../chat/domain/services/tool_definition_search_service.dart';
import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_request_shape.dart';
import 'live_llm_diagnostic_response_scoring.dart';
import 'live_llm_diagnostic_thinking_observer.dart';
import 'live_llm_effective_context_probe.dart';
import 'live_llm_embedding_probe.dart';
import 'live_llm_exact_preservation_probe.dart';
import 'live_llm_multi_round_probe.dart';
import 'live_llm_sampler_calibration_trials.dart';
import 'live_llm_streaming_probe.dart';
import 'live_llm_structured_output_probe.dart';
import 'live_llm_tool_depth_probe.dart';
import 'live_llm_tool_recovery_probe.dart';
import 'live_llm_vision_probes.dart';
import 'llm_provider_capabilities.dart';

typedef LiveLlmDiagnosticReportCallback =
    void Function(LiveLlmDiagnosticReport report);
typedef RunEffectiveContextTrial =
    Future<ChatCompletionResult> Function(
      int requestedApproximateTokens,
      List<Message> messages,
    );

class LiveLlmDiagnosticService {
  LiveLlmDiagnosticService({
    required this.settings,
    required this.chatDataSource,
    required this.mcpToolService,
    this.embedTexts,
    this.effectiveContextMaxTokens = 0,
    this.runEffectiveContextTrial,
    this.thinkingModeDataSource,
  });

  final AppSettings settings;
  final ChatDataSource chatDataSource;
  final McpToolService? mcpToolService;
  final EmbedTexts? embedTexts;
  final int effectiveContextMaxTokens;
  final RunEffectiveContextTrial? runEffectiveContextTrial;

  /// A datasource pinned to one thinking mode, for the probe that switches
  /// thinking deliberately. Null skips that probe: [chatDataSource] holds a
  /// single mode fixed at construction and cannot send the other one.
  final ChatDataSource Function(LiveLlmDiagnosticThinkingMode mode)?
  thinkingModeDataSource;

  final _thinking = LiveLlmDiagnosticThinkingObserver();

  /// Every probe request goes through here so its response is counted by
  /// [_thinking]. [chatDataSource] stays the datasource itself, because probes
  /// type-test it for opt-in capabilities a wrapper would hide.
  late final _chat = LiveLlmDiagnosticObservedChatCalls(
    chatDataSource,
    _thinking,
  );
  late final _exactPreservationProbe = LiveLlmExactPreservationProbe(
    complete: ({required messages}) => _chat.createChatCompletion(
      messages: messages,
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    ),
    messages: (user) => _messages(user: user),
  );
  late final _streamingProbe = LiveLlmStreamingProbe(
    stream: () => chatDataSource.streamChatCompletion(
      messages: _messages(user: LiveLlmStreamingProbe.prompt),
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    ),
    recordThinking: _thinking.record,
  );
  late final _effectiveContextProbe = LiveLlmEffectiveContextProbe(
    complete: (target, messages) {
      final injected = runEffectiveContextTrial;
      if (injected != null) return injected(target, messages);
      return _chat.createChatCompletion(
        messages: messages,
        model: _diagnosticModel,
        temperature: _diagnosticTemperature,
        maxTokens: 32,
      );
    },
    messages: (user) => _messages(user: user),
    advertisedContextTokens: _advertisedContextTokens,
  );
  late final _visionProbes = LiveLlmVisionProbes(
    complete: ({required messages, required maxTokens}) =>
        _chat.createChatCompletion(
          messages: messages,
          model: _diagnosticModel,
          temperature: _diagnosticTemperature,
          maxTokens: maxTokens,
        ),
    completeWithToolResults: ({required messages, required toolResults}) =>
        _chat.createChatCompletionWithToolResults(
          messages: messages,
          toolResults: toolResults,
          model: _diagnosticModel,
          temperature: _diagnosticTemperature,
          maxTokens: _diagnosticMaxTokens,
        ),
    messages: (user) => _messages(user: user),
    answerMaxTokens: _diagnosticMaxTokens,
    reasoningMaxTokens: _reasoningProbeMaxTokens,
  );
  late final _multiRoundProbe = LiveLlmMultiRoundProbe(
    complete: ({required messages, required tools}) =>
        _chat.createChatCompletion(
          messages: messages,
          tools: tools,
          model: _diagnosticModel,
          temperature: _diagnosticTemperature,
          maxTokens: _diagnosticMaxTokens,
        ),
    completeWithToolResults:
        ({required messages, required toolResults, required tools}) =>
            _chat.createChatCompletionWithToolResults(
              messages: messages,
              toolResults: toolResults,
              tools: tools,
              model: _diagnosticModel,
              temperature: _diagnosticTemperature,
              maxTokens: _diagnosticMaxTokens,
            ),
    messages: (user) => _messages(user: user),
  );
  late final _toolDepthProbe = LiveLlmToolDepthProbe(
    complete: ({required messages, tools}) => _chat.createChatCompletion(
      messages: messages,
      tools: tools,
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    ),
    messages: (user) => _messages(user: user),
  );
  late final _toolRecoveryProbe = LiveLlmToolRecoveryProbe(
    complete: ({required messages, required tools}) =>
        _chat.createChatCompletion(
          messages: messages,
          tools: tools,
          model: _diagnosticModel,
          temperature: _diagnosticTemperature,
          maxTokens: _diagnosticMaxTokens,
        ),
    messages: (user) => _messages(user: user),
  );
  late final _samplerTrials = LiveLlmSamplerCalibrationTrials(
    complete: ({required messages, tools, required temperature}) =>
        _chat.createChatCompletion(
          messages: messages,
          tools: tools,
          model: _diagnosticModel,
          temperature: temperature,
          maxTokens: _diagnosticMaxTokens,
        ),
    messages: (user) => _messages(user: user),
  );

  static const probeDefinitions = <LiveLlmDiagnosticProbeDefinition>[
    LiveLlmDiagnosticProbeDefinition(
      id: _instructionProbeId,
      titleKey: 'settings.live_llm_diag_probe_instruction_title',
      descriptionKey: 'settings.live_llm_diag_probe_instruction_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _thinkingControlProbeId,
      titleKey: 'settings.live_llm_diag_probe_thinking_control_title',
      descriptionKey: 'settings.live_llm_diag_probe_thinking_control_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _structuredOutputProbeId,
      titleKey: 'settings.live_llm_diag_probe_structured_output_title',
      descriptionKey: 'settings.live_llm_diag_probe_structured_output_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _streamingProbeId,
      titleKey: 'settings.live_llm_diag_probe_streaming_title',
      descriptionKey: 'settings.live_llm_diag_probe_streaming_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _exactPreservationProbeId,
      titleKey: 'settings.live_llm_diag_probe_exact_preservation_title',
      descriptionKey: 'settings.live_llm_diag_probe_exact_preservation_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _editFormatProbeId,
      titleKey: 'settings.live_llm_diag_probe_edit_format_title',
      descriptionKey: 'settings.live_llm_diag_probe_edit_format_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _embeddingsProbeId,
      titleKey: 'settings.live_llm_diag_probe_embeddings_title',
      descriptionKey: 'settings.live_llm_diag_probe_embeddings_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _effectiveContextProbeId,
      titleKey: 'settings.live_llm_diag_probe_effective_context_title',
      descriptionKey: 'settings.live_llm_diag_probe_effective_context_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _foundationModelsLanguageMatrixProbeId,
      titleKey: 'settings.live_llm_diag_probe_fm_language_matrix_title',
      descriptionKey: 'settings.live_llm_diag_probe_fm_language_matrix_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _visionAttachmentProbeId,
      titleKey: 'settings.live_llm_diag_probe_vision_attachment_title',
      descriptionKey: 'settings.live_llm_diag_probe_vision_attachment_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _videoInputModalityProbeId,
      titleKey: 'settings.live_llm_diag_probe_video_input_title',
      descriptionKey: 'settings.live_llm_diag_probe_video_input_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _chartReadingProbeId,
      titleKey: 'settings.live_llm_diag_probe_chart_reading_title',
      descriptionKey: 'settings.live_llm_diag_probe_chart_reading_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _visionToolObservationProbeId,
      titleKey: 'settings.live_llm_diag_probe_vision_observation_title',
      descriptionKey: 'settings.live_llm_diag_probe_vision_observation_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _narrowToolCallProbeId,
      titleKey: 'settings.live_llm_diag_probe_tool_call_title',
      descriptionKey: 'settings.live_llm_diag_probe_tool_call_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _goalUpdateFidelityProbeId,
      titleKey: 'settings.live_llm_diag_probe_goal_update_title',
      descriptionKey: 'settings.live_llm_diag_probe_goal_update_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _toolResultProbeId,
      titleKey: 'settings.live_llm_diag_probe_tool_result_title',
      descriptionKey: 'settings.live_llm_diag_probe_tool_result_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _multiRoundToolLoopProbeId,
      titleKey: 'settings.live_llm_diag_probe_multi_round_title',
      descriptionKey: 'settings.live_llm_diag_probe_multi_round_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _initialHarnessProbeId,
      titleKey: 'settings.live_llm_diag_probe_harness_title',
      descriptionKey: 'settings.live_llm_diag_probe_harness_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _toolSearchProbeId,
      titleKey: 'settings.live_llm_diag_probe_tool_search_title',
      descriptionKey: 'settings.live_llm_diag_probe_tool_search_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _subagentProbeId,
      titleKey: 'settings.live_llm_diag_probe_subagent_title',
      descriptionKey: 'settings.live_llm_diag_probe_subagent_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _remoteMcpProbeId,
      titleKey: 'settings.live_llm_diag_probe_remote_mcp_title',
      descriptionKey: 'settings.live_llm_diag_probe_remote_mcp_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _toolDepthProbeId,
      titleKey: 'settings.live_llm_diag_probe_tool_depth_title',
      descriptionKey: 'settings.live_llm_diag_probe_tool_depth_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _toolRecoveryProbeId,
      titleKey: 'settings.live_llm_diag_probe_tool_recovery_title',
      descriptionKey: 'settings.live_llm_diag_probe_tool_recovery_desc',
    ),
  ];

  static const _instructionProbeId = 'instruction_echo';
  static const _structuredOutputProbeId = LiveLlmStructuredOutputProbe.probeId;
  static const _streamingProbeId = LiveLlmStreamingProbe.probeId;
  static const _thinkingControlProbeId = 'thinking_control';
  static const _exactPreservationProbeId =
      LiveLlmExactPreservationProbe.probeId;
  static const _editFormatProbeId = 'edit_format_fidelity';
  static const _embeddingsProbeId = LiveLlmEmbeddingProbe.probeId;
  static const _effectiveContextProbeId = LiveLlmEffectiveContextProbe.probeId;
  static const _foundationModelsLanguageMatrixProbeId =
      'foundation_models_language_matrix';
  static const _visionAttachmentProbeId = LiveLlmVisionProbes.attachmentProbeId;
  static const _chartReadingProbeId = LiveLlmVisionProbes.chartReadingProbeId;
  static const _videoInputModalityProbeId = 'video_input_modality';
  static const _visionToolObservationProbeId =
      LiveLlmVisionProbes.toolObservationProbeId;
  static const _narrowToolCallProbeId = 'narrow_tool_call';
  static const _goalUpdateFidelityProbeId = 'update_goal_fidelity';
  static const _toolResultProbeId = 'tool_result_integration';
  static const _multiRoundToolLoopProbeId = LiveLlmMultiRoundProbe.probeId;
  static const _initialHarnessProbeId = 'initial_harness_selection';
  static const _toolSearchProbeId = 'tool_search_catalog';
  static const _subagentProbeId = 'subagent_recognition';
  static const _remoteMcpProbeId = 'remote_mcp_exposure';
  static const _toolDepthProbeId = LiveLlmToolDepthProbe.probeId;
  static const _toolRecoveryProbeId = LiveLlmToolRecoveryProbe.probeId;

  static const modelCapabilityProbeIds = <String>{
    _instructionProbeId,
    _thinkingControlProbeId,
    _structuredOutputProbeId,
    _streamingProbeId,
    _editFormatProbeId,
    _embeddingsProbeId,
    _effectiveContextProbeId,
    _visionAttachmentProbeId,
    _chartReadingProbeId,
    _visionToolObservationProbeId,
    _videoInputModalityProbeId,
    _narrowToolCallProbeId,
    _goalUpdateFidelityProbeId,
    _toolResultProbeId,
    _initialHarnessProbeId,
  };

  /// A 384x384 PNG of four solid quadrants in a non-obvious reading order:
  /// yellow, blue, red, green. The shuffled layout prevents a model from
  /// passing by guessing the conventional red, green, blue, yellow sequence.
  /// It is embedded so the probe stays byte-identical on every platform and in
  /// tests.
  ///
  /// The size is load-bearing. This was a 64x64 image on the theory that solid
  /// colors survive any downscaling, and it made a vision-capable model
  /// (gpt-5.6-luna) look blind: measured over the same endpoint and payload,
  /// 64px and 128px scored 0/3 while 256px and 384px scored 3/3, and the same
  /// model counted shapes correctly at 512px. Tiny images are evidently padded
  /// or upscaled into a tile before the vision tower sees them, so quadrant
  /// geometry is lost. Do not shrink this to save tokens without re-measuring:
  /// the probe would report the harness's own limit as a model failure.
  @visibleForTesting
  static const visionProbeImageBase64 = LiveLlmVisionProbes.imageBase64;

  /// A larger budget for the probes whose answer follows a reasoning preamble.
  ///
  /// These ask for something a model narrates its way to -- four readings off a
  /// picture, a unified diff, a schema-constrained object -- and the preamble is
  /// charged to the same budget as the answer. Measured on the chart probe: 628
  /// completion tokens across its two arms, yet at 1024 one run in three still
  /// ended inside the think block with no answer at all, which the shared 512
  /// would have reported as a model that cannot read charts.
  ///
  /// The 2026-09-18 qwen/qwen3.8-flash run set the current value: the chart
  /// probe stopped at exactly 1024, the unified-diff and json_schema arms at
  /// 512. A cap is not an allocation, so the headroom costs nothing on a model
  /// that answers sooner.
  ///
  /// **Do not raise this again to chase the two arms it did not fix.** The run
  /// on 2048 is the measurement: the unified-diff arm converged at 946 tokens
  /// and scored full marks, while the chart probe and the json_schema arm each
  /// stopped at exactly 2048 again -- 2x and 4x their previous budgets bought
  /// nothing. Those two do not run short of room, they fail to terminate, and
  /// each retry costs ~50 s of wall clock for zero points. Bounding the
  /// reasoning is the remaining lever, not enlarging it.
  static const _reasoningProbeMaxTokens = 2048;

  static const _marker = 'CAVERNO_LIVE_DIAGNOSTIC';
  static const structuredOutputSupportMetadataKey =
      LiveLlmStructuredOutputProbe.supportMetadataKey;
  static const _foundationModelsEnglishMarker = 'CAVERNO_FM_LANG_EN';
  static const _foundationModelsJapaneseMarker = 'CAVERNO_FM_LANG_JA';
  static const _foundationModelsToolBridgeMarker = 'CAVERNO_FM_LANG_TOOL';
  static const _toolResultMarker = 'CAVERNO_TOOL_RESULT_OK';
  static const _subagentMarker = 'CAVERNO_SUBAGENT_DIAGNOSTIC';
  static const editFormatPreferenceMetadataKey = 'editFormatPreference';
  static const _editFormatPath = 'lib/greeting.dart';
  static const _editFormatOriginal = '''String buildLabel(String name) {
  final trimmed = name.trim();
  return 'Hello, \$trimmed!';
}''';
  static const _editFormatUpdated = '''String buildLabel(String name) {
  final trimmed = name.trim();
  return 'Welcome, \$trimmed!';
}''';
  static final _editFormatSearchReplace = [
    '<<<<<<< SEARCH',
    "  return 'Hello, \$trimmed!';",
    '=======',
    "  return 'Welcome, \$trimmed!';",
    '>>>>>>> REPLACE',
  ].join('\n');
  static const _editFormatUnifiedDiff = '''--- a/lib/greeting.dart
+++ b/lib/greeting.dart
@@ -1,4 +1,4 @@
 String buildLabel(String name) {
   final trimmed = name.trim();
-  return 'Hello, \$trimmed!';
+  return 'Welcome, \$trimmed!';
 }''';

  /// Vision outcome labels. Emitted into probe details so the profile builder
  /// and a human reading the report classify a miss the same way.
  static const _videoModalitySupported = 'video_input_supported';
  static const _videoModalityUnsupported = 'video_input_unsupported';
  static const _videoModalityUnknown = 'video_input_unknown';

  static const _diagnosticTemperature = 0.0;
  static const _diagnosticMaxTokens = 512;
  static const _samplerCalibrationTemperatures = <double>[0.0, 0.2, 0.4, 0.7];
  static const _samplerCalibrationRepeatCount = 2;
  static const _samplerCalibrationTemperatureIgnoredReason =
      'Not measured: this endpoint rejects the `temperature` parameter, so '
      'every request runs at the server default. A sweep would have repeated '
      'one identical request and reported it as a clean pass.';

  /// True when the endpoint has already proven it drops `temperature`.
  ///
  /// The flag is discovered from a 400 on some earlier request and is sticky
  /// from then on, so it can also flip in the middle of a sweep -- callers
  /// check it before starting and again before keeping the trials.
  bool get _temperatureSweepIsMeaningless =>
      RequestParameterFallbackAware.ignoresTemperature(chatDataSource);

  /// Records that the sweep was not a measurement, discarding whatever trials
  /// were collected before the endpoint revealed itself.
  LiveLlmDiagnosticReport _markSamplerCalibrationUnmeasured(
    LiveLlmDiagnosticReport report,
    LiveLlmDiagnosticReportCallback? onReport,
  ) {
    if (report.samplerCalibrationUnmeasuredReason.isNotEmpty &&
        report.samplerCalibrationTrials.isEmpty) {
      return report;
    }
    final updated = report.copyWith(
      samplerCalibrationTrials: const <LiveLlmDiagnosticSamplerTrial>[],
      samplerCalibrationUnmeasuredReason:
          _samplerCalibrationTemperatureIgnoredReason,
    );
    onReport?.call(updated);
    return updated;
  }

  Future<LiveLlmDiagnosticReport> run({
    LiveLlmDiagnosticReportCallback? onReport,
    Set<String>? probeIds,
  }) async {
    final selectedProbeIds = probeIds == null ? null : Set<String>.of(probeIds);
    _thinking.reset();
    final startedAt = DateTime.now();
    var report = LiveLlmDiagnosticReport(
      startedAt: startedAt,
      baseUrl: _diagnosticEndpoint,
      model: _diagnosticModel,
      demoMode: settings.demoMode,
      mcpEnabled: settings.mcpEnabled,
      results: [
        for (final definition in probeDefinitions)
          LiveLlmDiagnosticProbeResult(
            id: definition.id,
            status: LiveLlmDiagnosticStatus.pending,
            summary: 'Waiting to run.',
          ),
      ],
    );
    onReport?.call(report);

    final catalogContext = await _loadToolCatalog();
    report = report.copyWith(toolCatalog: catalogContext.catalog);
    onReport?.call(report);

    if (settings.demoMode) {
      report = _skipRemainingAfterLiveRequirement(report);
      report = _finishReport(report);
      onReport?.call(report);
      return report;
    }

    final capabilities = settings.llmCapabilities;
    report = await _runSelectedProbe(
      report: report,
      probeId: _instructionProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runInstructionProbe,
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _thinkingControlProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runThinkingControlProbe,
    );
    report = await _runStructuredOutputProbe(
      report: report,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    report = await _runStreamingProbe(
      report: report,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    report = await _appendRoutineSamplerCalibrationTrials(
      report: report,
      capabilities: capabilities,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    report = await _appendCodingPlanSamplerCalibrationTrials(
      report: report,
      capabilities: capabilities,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _exactPreservationProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _exactPreservationProbe.run,
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _editFormatProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runEditFormatProbe,
    );
    report = await _runEmbeddingsProbe(
      report: report,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    report = await _runEffectiveContextProbe(
      report: report,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    if (settings.llmProvider == LlmProvider.appleFoundationModels) {
      report = await _runSelectedProbe(
        report: report,
        probeId: _foundationModelsLanguageMatrixProbeId,
        selectedProbeIds: selectedProbeIds,
        onReport: onReport,
        run: _runFoundationModelsLanguageMatrixProbe,
      );
    } else {
      report = report.withProbeResult(
        const LiveLlmDiagnosticProbeResult(
          id: _foundationModelsLanguageMatrixProbeId,
          status: LiveLlmDiagnosticStatus.skipped,
          summary:
              'Skipped because the selected provider is not Apple Foundation Models.',
        ),
      );
      onReport?.call(report);
    }
    report = await _runVisionProbes(
      report: report,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    if (!capabilities.supportsAnyToolBridge) {
      report = _skipProviderUnsupportedToolProbes(
        report,
        _toolBridgeProbeDefinitions(),
        selectedProbeIds: selectedProbeIds,
      );
      report = _finishReport(report);
      onReport?.call(report);
      return report;
    }
    report = await _runSelectedProbe(
      report: report,
      probeId: _narrowToolCallProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: () => _runNarrowToolCallProbe(catalogContext),
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _goalUpdateFidelityProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runGoalUpdateFidelityProbe,
    );
    report = await _appendToolLoopSamplerCalibrationTrials(
      report: report,
      catalog: catalogContext,
      capabilities: capabilities,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    if (!capabilities.supportsAdvancedLiveToolDiagnostics) {
      report = _skipProviderUnsupportedToolProbes(
        report,
        _probeDefinitionsAfter(_narrowToolCallProbeId),
        selectedProbeIds: selectedProbeIds,
      );
      report = _finishReport(report);
      onReport?.call(report);
      return report;
    }
    report = await _runSelectedProbe(
      report: report,
      probeId: _toolResultProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: () => _runToolResultProbe(catalogContext),
    );
    report = await _runMultiRoundToolLoopProbe(
      report: report,
      catalog: catalogContext,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _initialHarnessProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: () => _runInitialHarnessProbe(catalogContext),
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _toolSearchProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: () => _runToolSearchProbe(catalogContext),
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _subagentProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: () => _runSubagentProbe(catalogContext),
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _remoteMcpProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: () => _runRemoteMcpProbe(catalogContext),
    );
    report = await _runToolDepthProbe(
      report: report,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
    );
    report = await _runSelectedProbe(
      report: report,
      probeId: _toolRecoveryProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runToolRecoveryProbe,
    );

    report = _finishReport(report);
    onReport?.call(report);
    return report;
  }

  Future<LiveLlmDiagnosticReport> _runSelectedProbe({
    required LiveLlmDiagnosticReport report,
    required String probeId,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
    required Future<LiveLlmDiagnosticProbeResult> Function() run,
  }) {
    if (!_shouldRunProbe(probeId, selectedProbeIds)) {
      final updated = _skipProbe(
        report,
        probeId,
        'Skipped because this bounded diagnostic run did not request this probe.',
      );
      onReport?.call(updated);
      return Future.value(updated);
    }
    return _runProbe(report, probeId, onReport, run);
  }

  bool _shouldRunProbe(String probeId, Set<String>? selectedProbeIds) {
    return selectedProbeIds == null || selectedProbeIds.contains(probeId);
  }

  LiveLlmDiagnosticReport _skipProbe(
    LiveLlmDiagnosticReport report,
    String probeId,
    String summary, {
    String details = '',
  }) {
    final existing = report.results.where((result) => result.id == probeId);
    if (existing.isNotEmpty && existing.first.status.isTerminal) {
      return report;
    }
    return report.withProbeResult(
      LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary: summary,
        details: details,
      ),
    );
  }

  Iterable<LiveLlmDiagnosticProbeDefinition> _toolBridgeProbeDefinitions() {
    return probeDefinitions.where((definition) {
      return definition.id != _instructionProbeId &&
          definition.id != _foundationModelsLanguageMatrixProbeId;
    });
  }

  Iterable<LiveLlmDiagnosticProbeDefinition> _probeDefinitionsAfter(
    String probeId,
  ) {
    final index = probeDefinitions.indexWhere(
      (definition) => definition.id == probeId,
    );
    if (index < 0 || index + 1 >= probeDefinitions.length) {
      return const <LiveLlmDiagnosticProbeDefinition>[];
    }
    return probeDefinitions.skip(index + 1);
  }

  String get _diagnosticEndpoint => switch (settings.llmProvider) {
    LlmProvider.appleFoundationModels => 'apple-foundation-models://local',
    LlmProvider.openAiCompatible => settings.baseUrl,
  };

  String get _diagnosticModel => settings.effectiveModel;

  LiveLlmDiagnosticReport _finishReport(LiveLlmDiagnosticReport report) {
    return report.copyWith(
      finishedAt: DateTime.now(),
      thinkingMetrics: _thinking.metrics(
        chatDataSource,
        model: _diagnosticModel,
        maxTokens: _diagnosticMaxTokens,
        effort: settings.reasoningEffort,
      ),
    );
  }

  LiveLlmDiagnosticReport _skipRemainingAfterLiveRequirement(
    LiveLlmDiagnosticReport report,
  ) {
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _instructionProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'Demo mode is enabled.',
        details: 'Live diagnostics require a real selected LLM provider.',
      ),
    );
    for (final definition in probeDefinitions.skip(1)) {
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: definition.id,
          status: LiveLlmDiagnosticStatus.skipped,
          summary: 'Skipped because demo mode is enabled.',
        ),
      );
    }
    return updated;
  }

  Future<LiveLlmDiagnosticReport> _runProbe(
    LiveLlmDiagnosticReport report,
    String probeId,
    LiveLlmDiagnosticReportCallback? onReport,
    Future<LiveLlmDiagnosticProbeResult> Function() run,
  ) async {
    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);

    try {
      final result = await run();
      updated = updated.withProbeResult(
        result.copyWith(elapsed: DateTime.now().difference(startedAt)),
      );
    } catch (error) {
      final rawError = error.toString();
      final unsupportedLanguage =
          AppleFoundationModelsException.isUnsupportedLanguageOrLocaleText(
            rawError,
          );
      final providerUnavailable =
          AppleFoundationModelsException.isProviderUnavailableText(rawError);
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: probeId,
          status: LiveLlmDiagnosticStatus.failed,
          summary: _probeFailureSummary(
            unsupportedLanguage: unsupportedLanguage,
            providerUnavailable: providerUnavailable,
          ),
          details: _probeFailureDetails(
            rawError,
            unsupportedLanguage: unsupportedLanguage,
            providerUnavailable: providerUnavailable,
          ),
          elapsed: DateTime.now().difference(startedAt),
        ),
      );
    }
    onReport?.call(updated);
    return updated;
  }

  String _probeFailureSummary({
    required bool unsupportedLanguage,
    required bool providerUnavailable,
  }) {
    if (unsupportedLanguage) {
      return 'The selected provider rejected this prompt language or locale.';
    }
    if (providerUnavailable) {
      return 'Apple Foundation Models is not available for this device or session.';
    }
    return 'Probe failed with an exception.';
  }

  String _probeFailureDetails(
    String rawError, {
    required bool unsupportedLanguage,
    required bool providerUnavailable,
  }) {
    if (unsupportedLanguage) {
      return 'Foundation Models reported unsupportedLanguageOrLocale. '
          'This is treated as provider incompatibility for the probe, not as '
          'an application crash.\n\n$rawError';
    }
    if (providerUnavailable) {
      return 'Foundation Models preflight reported that local generation is '
          'unavailable. Check Apple Intelligence, model readiness, device '
          'eligibility, and OS support, or switch providers.\n\n$rawError';
    }
    return rawError;
  }

  LiveLlmDiagnosticReport _skipProviderUnsupportedToolProbes(
    LiveLlmDiagnosticReport report,
    Iterable<LiveLlmDiagnosticProbeDefinition> definitions, {
    Set<String>? selectedProbeIds,
  }) {
    var updated = report;
    for (final definition in definitions) {
      if (!_shouldRunProbe(definition.id, selectedProbeIds)) {
        continue;
      }
      updated = _skipProbe(
        updated,
        definition.id,
        'Skipped because the selected provider does not support this diagnostic capability.',
        details:
            'Foundation Models currently supports only limited text responses '
            'and an experimental single-step textual tool bridge in Caverno.',
      );
    }
    return updated;
  }

  Future<_ToolCatalogContext> _loadToolCatalog() async {
    final service = mcpToolService;
    var connectionSummary = '';
    if (!settings.mcpEnabled) {
      return const _ToolCatalogContext(
        definitions: <Map<String, dynamic>>[],
        initialDefinitions: <Map<String, dynamic>>[],
        selectedToolNames: <String>{},
        toolSearchEnabled: false,
        catalog: LiveLlmDiagnosticToolCatalog(
          mcpConnectionSummary: 'MCP tools are disabled in settings.',
        ),
      );
    }
    if (service == null) {
      return const _ToolCatalogContext(
        definitions: <Map<String, dynamic>>[],
        initialDefinitions: <Map<String, dynamic>>[],
        selectedToolNames: <String>{},
        toolSearchEnabled: false,
        catalog: LiveLlmDiagnosticToolCatalog(
          mcpConnectionSummary: 'MCP tool service is unavailable.',
        ),
      );
    }

    try {
      await service.connect();
    } catch (error) {
      connectionSummary = 'Remote MCP connection attempt failed: $error';
    }

    final definitions = service.getOpenAiToolDefinitions();
    final initialSelection = ToolDefinitionSearchService.buildInitialSelection(
      definitions,
    );
    final toolNames = _toolNamesFromDefinitions(definitions);
    final initialToolNames = _toolNamesFromDefinitions(
      initialSelection.toolDefinitions,
    );
    final remoteToolNames = definitions
        .where(_isRemoteMcpTool)
        .map(ToolDefinitionSearchService.toolNameFromDefinition)
        .whereType<String>()
        .toList(growable: false);
    final stateSummary = _mcpStateSummary(service);
    connectionSummary = [
      if (connectionSummary.isNotEmpty) connectionSummary,
      if (stateSummary.isNotEmpty) stateSummary,
    ].join('\n');

    return _ToolCatalogContext(
      definitions: definitions,
      initialDefinitions: initialSelection.toolDefinitions,
      selectedToolNames: initialSelection.selectedToolNames,
      toolSearchEnabled: initialSelection.toolSearchEnabled,
      catalog: LiveLlmDiagnosticToolCatalog(
        totalToolCount: definitions.length,
        initialToolCount: initialSelection.toolDefinitions.length,
        remoteToolCount: remoteToolNames.length,
        remoteServerCount: settings.enabledMcpServers.length,
        toolSearchEnabled: initialSelection.toolSearchEnabled,
        toolNames: toolNames,
        initialToolNames: initialToolNames,
        remoteToolNames: remoteToolNames,
        mcpConnectionSummary: connectionSummary,
      ),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runInstructionProbe() async {
    final result = await _chat.createChatCompletion(
      messages: _messages(
        user:
            'Return exactly this JSON object and no markdown:\n'
            '{"probe":"instruction_echo","status":"ok","marker":"$_marker"}',
      ),
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final content = result.content.trim();
    final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(content);
    final jsonPassed =
        decoded?['probe'] == 'instruction_echo' &&
        decoded?['status'] == 'ok' &&
        decoded?['marker'] == _marker;
    final markerPresent = content.contains(_marker);
    if (jsonPassed) {
      return LiveLlmDiagnosticProbeResult(
        id: _instructionProbeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model followed the exact JSON instruction.',
        modelContent: LiveLlmDiagnosticEvidence.preview(content),
        usage: LiveLlmDiagnosticEvidence.usage(result),
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _instructionProbeId,
      status: markerPresent
          ? LiveLlmDiagnosticStatus.warning
          : LiveLlmDiagnosticStatus.failed,
      summary: markerPresent
          ? 'The marker was present, but the JSON contract was not exact.'
          : 'The expected diagnostic marker was missing.',
      details: 'Expected marker: $_marker',
      modelContent: LiveLlmDiagnosticEvidence.preview(content),
      usage: LiveLlmDiagnosticEvidence.usage(result),
    );
  }

  Future<LiveLlmDiagnosticReport> _runStructuredOutputProbe({
    required LiveLlmDiagnosticReport report,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!_shouldRunProbe(_structuredOutputProbeId, selectedProbeIds)) {
      final updated = _skipProbe(
        report,
        _structuredOutputProbeId,
        'Skipped because this bounded diagnostic run did not request this probe.',
      );
      onReport?.call(updated);
      return updated;
    }
    if (settings.llmProvider == LlmProvider.appleFoundationModels) {
      final updated = _skipProbe(
        report,
        _structuredOutputProbeId,
        'Skipped because Apple Foundation Models does not expose response_format.',
      );
      onReport?.call(updated);
      return updated;
    }
    final dataSource = chatDataSource;
    if (dataSource is! StructuredOutputChatDataSource) {
      final updated = _skipProbe(
        report,
        _structuredOutputProbeId,
        'Skipped because this datasource cannot send response_format.',
      );
      onReport?.call(updated);
      return updated;
    }
    final structuredDataSource = dataSource as StructuredOutputChatDataSource;

    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _structuredOutputProbeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);

    await LiveLlmStructuredOutputProbe(
      complete:
          ({
            required messages,
            required responseFormat,
            required maxTokens,
          }) async {
            final response = await structuredDataSource
                .createStructuredChatCompletion(
                  messages: messages,
                  responseFormat: responseFormat,
                  model: _diagnosticModel,
                  temperature: _diagnosticTemperature,
                  maxTokens: maxTokens,
                );
            _thinking.record(response.content);
            return response;
          },
      responseFormatSupport: _responseFormatSupport,
      messages: (user) => _messages(user: user),
      answerMaxTokens: _diagnosticMaxTokens,
      reasoningMaxTokens: _reasoningProbeMaxTokens,
    ).run(
      startedAt: startedAt,
      onResult: (result) {
        updated = updated.withProbeResult(result);
        onReport?.call(updated);
      },
    );
    return updated;
  }

  /// Reads `supported_parameters` off `GET /models`, reporting
  /// [EndpointParameterSupport.unknown] for anything that does not answer --
  /// which is most servers, and which keeps the generation arms running.
  Future<EndpointParameterSupport> _responseFormatSupport() async {
    final client = http.Client();
    try {
      return await const OpenAiParameterSupportProbe().responseFormatSupport(
        baseUrl: settings.baseUrl,
        model: settings.effectiveModel,
        client: client,
        headers: ApiConstants.userAgentHeaders,
      );
    } on Object {
      return EndpointParameterSupport.unknown;
    } finally {
      client.close();
    }
  }

  Future<LiveLlmDiagnosticProbeResult> _runToolRecoveryProbe() async {
    if (!settings.llmCapabilities.supportsNativeToolCalls) {
      return const LiveLlmDiagnosticProbeResult(
        id: _toolRecoveryProbeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary:
            'Skipped because this provider does not make native tool calls.',
      );
    }

    return _toolRecoveryProbe.run();
  }

  /// LL39 tool-chain depth axis: the same errand at two, three and four
  /// sequential tool calls, each rung needing a value the previous one
  /// produced.
  ///
  /// Scripted rather than executed. The canned observations keep the rung
  /// measuring the model's state carrying instead of whatever the live catalog
  /// happens to hold, and keep the probe deterministic on an endpoint whose
  /// tools may not exist.
  ///
  /// Unscored, like the context ladder: this is headroom above the conformance
  /// floor, reported as a depth rather than folded into a percentage that
  /// would saturate.
  Future<LiveLlmDiagnosticReport> _runToolDepthProbe({
    required LiveLlmDiagnosticReport report,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!_shouldRunProbe(_toolDepthProbeId, selectedProbeIds)) {
      final updated = _skipProbe(
        report,
        _toolDepthProbeId,
        'Skipped because this bounded diagnostic run did not request this probe.',
      );
      onReport?.call(updated);
      return updated;
    }
    if (!settings.llmCapabilities.supportsNativeToolCalls) {
      final updated = _skipProbe(
        report,
        _toolDepthProbeId,
        'Skipped because this provider does not make native tool calls.',
      );
      onReport?.call(updated);
      return updated;
    }

    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _toolDepthProbeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);

    final measurement = await _toolDepthProbe.run(startedAt: startedAt);
    updated = updated
        .withProbeResult(measurement.result)
        .copyWith(toolDepthMetrics: measurement.metrics);
    onReport?.call(updated);
    return updated;
  }

  /// The context window the endpoint publishes, or 0 when it publishes none.
  Future<int> _advertisedContextTokens() async {
    final client = http.Client();
    try {
      return await const OpenAiParameterSupportProbe().advertisedContextTokens(
        baseUrl: settings.baseUrl,
        model: settings.effectiveModel,
        client: client,
        headers: ApiConstants.userAgentHeaders,
      );
    } on Object {
      return 0;
    } finally {
      client.close();
    }
  }

  /// Exercises `streamChatCompletion` — the path the chat screen actually uses,
  /// and the only one with incremental delivery, a reasoning-field fallback and
  /// a `finish_reason` that can truncate. Every other probe goes through the
  /// non-streaming call, so none of that was covered.
  ///
  /// It is also where the capability tier's two speed figures come from, which
  /// is why the metrics are attached to the report rather than folded into the
  /// probe's points.
  Future<LiveLlmDiagnosticReport> _runStreamingProbe({
    required LiveLlmDiagnosticReport report,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!_shouldRunProbe(_streamingProbeId, selectedProbeIds)) {
      final updated = _skipProbe(
        report,
        _streamingProbeId,
        'Skipped because this bounded diagnostic run did not request this probe.',
      );
      onReport?.call(updated);
      return updated;
    }

    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _streamingProbeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);

    try {
      final outcome = await _streamingProbe.run();
      updated = updated
          .withProbeResult(
            outcome.result.copyWith(
              elapsed: DateTime.now().difference(startedAt),
            ),
          )
          .copyWith(streamingMetrics: outcome.metrics);
    } catch (error) {
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: _streamingProbeId,
          status: LiveLlmDiagnosticStatus.failed,
          summary: 'The streaming request failed.',
          details: error.toString(),
          elapsed: DateTime.now().difference(startedAt),
        ),
      );
    }
    onReport?.call(updated);
    return updated;
  }

  Future<LiveLlmDiagnosticProbeResult> _runEditFormatProbe() async {
    final cases = <_EditFormatProbeCase>[
      const _EditFormatProbeCase(
        preference: ModelEditFormatPreference.wholeFile,
        instruction:
            'Return the complete updated file contents with no markdown fence.',
        expected: _editFormatUpdated,
      ),
      _EditFormatProbeCase(
        preference: ModelEditFormatPreference.searchReplace,
        instruction:
            'Return one exact SEARCH/REPLACE block using the markers '
            '<<<<<<< SEARCH, =======, and >>>>>>> REPLACE. Include only the '
            'changed line in each side and no markdown fence.',
        expected: _editFormatSearchReplace,
      ),
      _EditFormatProbeCase(
        preference: ModelEditFormatPreference.unifiedDiff,
        instruction:
            'Return one syntactically valid unified diff that can be applied '
            'to lib/greeting.dart. Include every available unchanged line as '
            'context, and ensure each hunk header count matches the old and '
            'new lines in that hunk. Return no markdown fence or explanation.',
        expected: _editFormatUnifiedDiff,
        normalize: LiveLlmResponseScoring.normalizeUnifiedDiffFileHeaders,
      ),
    ];
    final outcomes = <_EditFormatProbeOutcome>[];
    for (final testCase in cases) {
      final result = await _chat.createChatCompletion(
        messages: _messages(
          user:
              'Update the greeting from Hello to Welcome without changing any '
              'other text. The current $_editFormatPath contents are:\n\n'
              '$_editFormatOriginal\n\n${testCase.instruction}',
        ),
        model: _diagnosticModel,
        temperature: _diagnosticTemperature,
        maxTokens: _reasoningProbeMaxTokens,
      );
      final normalized = LiveLlmResponseScoring.stripSingleCodeFence(
        LiveLlmResponseScoring.visibleContent(result.content),
      );
      final mismatch = LiveLlmResponseScoring.firstEditFormatMismatch(
        expected: testCase.prepare(testCase.expected),
        actual: testCase.prepare(normalized),
      );
      // A cap the answer never got past reads as "received end of output",
      // which names the symptom and hides the cause.
      final failureDetail = mismatch == null || result.finishReason != 'length'
          ? mismatch
          : '$mismatch -- the response hit the token cap '
                '(finish_reason: length)';
      outcomes.add(
        _EditFormatProbeOutcome(
          preference: testCase.preference,
          passed: failureDetail == null,
          failureDetail: failureDetail,
          content: result.content,
          usage: LiveLlmDiagnosticEvidence.usage(result),
        ),
      );
    }

    final passed = outcomes.where((outcome) => outcome.passed).toList();
    final preference = _preferredEditFormat(passed);
    final status = passed.length == outcomes.length
        ? LiveLlmDiagnosticStatus.passed
        : passed.isNotEmpty
        ? LiveLlmDiagnosticStatus.warning
        : LiveLlmDiagnosticStatus.failed;
    return LiveLlmDiagnosticProbeResult(
      id: _editFormatProbeId,
      status: status,
      summary: preference == ModelEditFormatPreference.unknown
          ? 'The model did not reproduce any supported edit format exactly.'
          : 'The model reliably produced ${preference.name} edits.',
      details: outcomes
          .map(
            (outcome) => outcome.passed
                ? '${outcome.preference.name}: passed'
                : '${outcome.preference.name}: failed'
                      '${outcome.failureDetail == null ? '' : ' (${outcome.failureDetail})'}',
          )
          .join('\n'),
      modelContent: outcomes
          .map(
            (outcome) =>
                '${outcome.preference.name}: ${LiveLlmDiagnosticEvidence.preview(outcome.content, maxChars: 360)}',
          )
          .join('\n\n'),
      usage: LiveLlmDiagnosticEvidence.sumUsage(
        outcomes.map((outcome) => outcome.usage),
      ),
      passedChecks: passed.length,
      totalChecks: outcomes.length,
      metadata: {editFormatPreferenceMetadataKey: preference.name},
    );
  }

  ModelEditFormatPreference _preferredEditFormat(
    List<_EditFormatProbeOutcome> passed,
  ) {
    for (final preference in const [
      ModelEditFormatPreference.unifiedDiff,
      ModelEditFormatPreference.searchReplace,
      ModelEditFormatPreference.wholeFile,
    ]) {
      if (passed.any((outcome) => outcome.preference == preference)) {
        return preference;
      }
    }
    return ModelEditFormatPreference.unknown;
  }

  Future<LiveLlmDiagnosticReport> _runEmbeddingsProbe({
    required LiveLlmDiagnosticReport report,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!_shouldRunProbe(_embeddingsProbeId, selectedProbeIds)) {
      final updated = _skipProbe(
        report,
        _embeddingsProbeId,
        'Skipped because this bounded diagnostic run did not request this probe.',
      );
      onReport?.call(updated);
      return updated;
    }
    if (settings.llmProvider == LlmProvider.appleFoundationModels) {
      final updated = _skipProbe(
        report,
        _embeddingsProbeId,
        'Skipped because Apple Foundation Models does not expose embeddings.',
      );
      onReport?.call(updated);
      return updated;
    }
    final model = settings.embeddingsModel.trim();
    if (model.isEmpty) {
      final updated = _skipProbe(
        report,
        _embeddingsProbeId,
        'Skipped because no embeddings model is configured.',
        details:
            'Choose an embeddings model in General settings to measure the '
            'production LL5 semantic-search path.',
      );
      onReport?.call(updated);
      return updated;
    }

    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _embeddingsProbeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);
    try {
      final stopwatch = Stopwatch()..start();
      final attempt = await _embed(LiveLlmEmbeddingProbe.inputs, model: model);
      stopwatch.stop();
      final result = attempt.result;
      if (result == null) {
        updated = updated.withProbeResult(
          LiveLlmDiagnosticProbeResult(
            id: _embeddingsProbeId,
            status: LiveLlmDiagnosticStatus.failed,
            summary: 'The production embeddings client returned no vectors.',
            details: [
              // The embeddings client swallows every failure so semantic search
              // can degrade quietly; name the endpoint and the server's own
              // words here, or a stale model id reads as a dead endpoint.
              attempt.failure?.describe() ??
                  'The configured endpoint/model pair was unavailable or '
                      'returned an unsupported response.',
              '',
              'Embeddings endpoint: ${settings.effectiveEmbeddingsBaseUrl}',
              'Embeddings model: $model',
              if (settings.embeddingsEndpointId.trim().isEmpty)
                'This model is sent to the primary endpoint because no '
                    'embeddings endpoint is pinned. A model from a different '
                    'server will 404 here.',
              'Run COMPAT1 to classify the protocol failure separately.',
            ].join('\n'),
            elapsed: DateTime.now().difference(startedAt),
          ),
        );
        onReport?.call(updated);
        return updated;
      }

      final outcome = LiveLlmEmbeddingProbe.evaluate(result, stopwatch.elapsed);
      updated = updated
          .withProbeResult(
            outcome.result.copyWith(
              elapsed: DateTime.now().difference(startedAt),
            ),
          )
          .copyWith(embeddingMetrics: outcome.metrics);
    } catch (error) {
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: _embeddingsProbeId,
          status: LiveLlmDiagnosticStatus.failed,
          summary: 'The embeddings capability probe failed with an exception.',
          details: error.toString(),
          elapsed: DateTime.now().difference(startedAt),
        ),
      );
    }
    onReport?.call(updated);
    return updated;
  }

  Future<_EmbeddingAttempt> _embed(
    List<String> inputs, {
    required String model,
  }) async {
    final injected = embedTexts;
    if (injected != null) {
      return _EmbeddingAttempt(result: await injected(inputs));
    }
    final client = EmbeddingsClient(
      baseUrl: settings.effectiveEmbeddingsBaseUrl,
      apiKey: settings.effectiveEmbeddingsApiKey,
    );
    try {
      final result = await client.embed(inputs: inputs, model: model);
      return _EmbeddingAttempt(result: result, failure: client.lastFailure);
    } finally {
      client.close();
    }
  }

  Future<LiveLlmDiagnosticReport> _runEffectiveContextProbe({
    required LiveLlmDiagnosticReport report,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!_shouldRunProbe(_effectiveContextProbeId, selectedProbeIds)) {
      final updated = _skipProbe(
        report,
        _effectiveContextProbeId,
        'Skipped because this bounded diagnostic run did not request this probe.',
      );
      onReport?.call(updated);
      return updated;
    }
    if (effectiveContextMaxTokens <= 0) {
      final updated = _skipProbe(
        report,
        _effectiveContextProbeId,
        'Skipped because the expensive context ladder was not enabled.',
        details:
            'Use the headless canary with an explicit effective-context maximum '
            'to opt in. Normal diagnostics never allocate long prompts.',
      );
      onReport?.call(updated);
      return updated;
    }
    if (settings.llmProvider == LlmProvider.appleFoundationModels) {
      final updated = _skipProbe(
        report,
        _effectiveContextProbeId,
        'Skipped because Foundation Models context limits are managed by the host API.',
      );
      onReport?.call(updated);
      return updated;
    }

    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _effectiveContextProbeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);

    final measurement = await _effectiveContextProbe.run(
      requestedMaximumTokens: effectiveContextMaxTokens,
      startedAt: startedAt,
    );
    updated = updated
        .withProbeResult(measurement.result)
        .copyWith(effectiveContextMetrics: measurement.metrics);
    onReport?.call(updated);
    return updated;
  }

  Future<LiveLlmDiagnosticProbeResult>
  _runFoundationModelsLanguageMatrixProbe() async {
    final cases = [
      const _FoundationModelsLanguageProbeCase(
        label: 'english_text',
        marker: _foundationModelsEnglishMarker,
        userPrompt:
            'Reply with exactly $_foundationModelsEnglishMarker and no extra text.',
      ),
      const _FoundationModelsLanguageProbeCase(
        label: 'japanese_text',
        marker: _foundationModelsJapaneseMarker,
        userPrompt:
            '\u6b21\u306e\u6587\u5b57\u5217\u3060\u3051\u3092\u8fd4\u3057\u3066\u304f\u3060\u3055\u3044: $_foundationModelsJapaneseMarker',
      ),
      _FoundationModelsLanguageProbeCase(
        label: 'english_tool_bridge',
        marker: _foundationModelsToolBridgeMarker,
        userPrompt:
            'A diagnostic tool is listed, but do not call it. Reply with '
            'exactly $_foundationModelsToolBridgeMarker and no extra text.',
        tools: [_foundationModelsLanguageMatrixToolDefinition()],
      ),
    ];
    final outcomes = <_FoundationModelsLanguageProbeOutcome>[];
    for (final testCase in cases) {
      outcomes.add(await _runFoundationModelsLanguageProbeCase(testCase));
    }

    final failed = outcomes.where((outcome) => !outcome.passed).toList();
    final englishBaseline = outcomes.first;
    final status = failed.isEmpty
        ? LiveLlmDiagnosticStatus.passed
        : englishBaseline.passed
        ? LiveLlmDiagnosticStatus.warning
        : LiveLlmDiagnosticStatus.failed;
    final summary = failed.isEmpty
        ? 'Foundation Models accepted English, Japanese, and tool-bridge prompts.'
        : englishBaseline.passed
        ? 'English baseline passed, but at least one language matrix case was rejected.'
        : 'Foundation Models rejected the English baseline prompt.';

    return LiveLlmDiagnosticProbeResult(
      id: _foundationModelsLanguageMatrixProbeId,
      status: status,
      summary: summary,
      details: outcomes.map((outcome) => outcome.toDetailLine()).join('\n'),
      modelContent: outcomes
          .map(
            (outcome) =>
                '${outcome.label}: ${LiveLlmDiagnosticEvidence.preview(outcome.preview, maxChars: 240)}',
          )
          .join('\n'),
      passedChecks: outcomes.length - failed.length,
      totalChecks: outcomes.length,
    );
  }

  Future<_FoundationModelsLanguageProbeOutcome>
  _runFoundationModelsLanguageProbeCase(
    _FoundationModelsLanguageProbeCase testCase,
  ) async {
    try {
      final result = await _chat.createChatCompletion(
        messages: _messages(user: testCase.userPrompt),
        tools: testCase.tools,
        model: _diagnosticModel,
        temperature: _diagnosticTemperature,
        maxTokens: _diagnosticMaxTokens,
      );
      final content = result.content.trim();
      return _FoundationModelsLanguageProbeOutcome(
        label: testCase.label,
        passed: content.contains(testCase.marker),
        classification: content.contains(testCase.marker)
            ? 'accepted'
            : 'missing_marker',
        preview: content,
      );
    } catch (error) {
      final rawError = error.toString();
      final classification =
          AppleFoundationModelsException.isUnsupportedLanguageOrLocaleText(
            rawError,
          )
          ? 'unsupported_language_or_locale'
          : AppleFoundationModelsException.isProviderUnavailableText(rawError)
          ? 'provider_unavailable'
          : 'exception';
      return _FoundationModelsLanguageProbeOutcome(
        label: testCase.label,
        passed: false,
        classification: classification,
        preview: rawError,
      );
    }
  }

  Map<String, dynamic> _foundationModelsLanguageMatrixToolDefinition() {
    return {
      'type': 'function',
      'function': {
        'name': 'language_matrix_echo',
        'description': 'Echoes a diagnostic marker when explicitly requested.',
        'parameters': {
          'type': 'object',
          'properties': {
            'marker': {
              'type': 'string',
              'description': 'Diagnostic marker to echo.',
            },
          },
          'required': ['marker'],
        },
      },
    };
  }

  /// LL39 vision block.
  ///
  /// Apple Foundation Models drops image parts at the datasource
  /// (`_contentWithImageNotice`), so the model is never actually asked: that is
  /// not applicable rather than a failure, and it must not be scored as one.
  Future<LiveLlmDiagnosticReport> _runVisionProbes({
    required LiveLlmDiagnosticReport report,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (settings.llmProvider == LlmProvider.appleFoundationModels) {
      var updated = report;
      for (final probeId in const [
        _visionAttachmentProbeId,
        _chartReadingProbeId,
        _visionToolObservationProbeId,
      ]) {
        updated = _skipProbe(
          updated,
          probeId,
          'Skipped because Caverno does not send images to Apple Foundation Models.',
          details:
              'The Foundation Models datasource replaces an attached image '
              'with a text notice, so this provider is never asked to read one.',
        );
      }
      onReport?.call(updated);
      return updated;
    }

    var updated = await _runSelectedProbe(
      report: report,
      probeId: _visionAttachmentProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _visionProbes.attachment,
    );
    updated = await _runSelectedProbe(
      report: updated,
      probeId: _chartReadingProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _visionProbes.chartReading,
    );
    updated = await _runSelectedProbe(
      report: updated,
      probeId: _visionToolObservationProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _visionProbes.toolObservation,
    );
    updated = await _runSelectedProbe(
      report: updated,
      probeId: _videoInputModalityProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runVideoInputModalityProbe,
    );
    return updated;
  }

  static const thinkingControlMetadataKey = 'thinkingControl';
  static const _thinkingControlled = 'controllable';
  static const _thinkingAlwaysOn = 'always_on';
  static const _thinkingNeverObserved = 'never_reasoned';
  static const _thinkingInverted = 'inverted';
  static const _thinkingControlPrompt =
      'Reply with exactly CAVERNO_THINKING_CONTROL and no other text.';

  /// Whether `enable_thinking` actually reaches the model, in both directions.
  ///
  /// Sends one trivial prompt with thinking switched on and one with it
  /// switched off, and reads whether each answer carried reasoning. Until
  /// 2026-09-23 a router in front of qwen3.8-27b-exl3 forced thinking off
  /// whatever the request said, and nothing in the report could show it: the
  /// request side read "on" and the scores quietly measured "off".
  ///
  /// Scores nothing. Like the video probe, it reports what the serving path
  /// does with a request, not what the model can do. Its responses stay out of
  /// the run's thinking metrics too, since they vary the mode on purpose.
  Future<LiveLlmDiagnosticProbeResult> _runThinkingControlProbe() async {
    final createDataSource = thinkingModeDataSource;
    if (createDataSource == null) {
      return const LiveLlmDiagnosticProbeResult(
        id: _thinkingControlProbeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'Skipped because this run cannot switch the thinking mode.',
      );
    }
    if (!LiveLlmDiagnosticRequestShape.canControlThinking(settings)) {
      return const LiveLlmDiagnosticProbeResult(
        id: _thinkingControlProbeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary:
            'Skipped because this endpoint cannot be sent enable_thinking.',
        details:
            'The model is not a Qwen3.8 build and the endpoint is not opted '
            'into chat_template_kwargs, so both modes would send the same '
            'request.',
      );
    }

    Future<ChatCompletionResult> arm(LiveLlmDiagnosticThinkingMode mode) {
      return createDataSource(mode).createChatCompletion(
        messages: _messages(user: _thinkingControlPrompt),
        model: _diagnosticModel,
        temperature: _diagnosticTemperature,
        maxTokens: _diagnosticMaxTokens,
      );
    }

    final on = await arm(LiveLlmDiagnosticThinkingMode.on);
    final off = await arm(LiveLlmDiagnosticThinkingMode.off);
    final onChars = LiveLlmDiagnosticThinkingObserver.reasoningChars(
      on.content,
    );
    final offChars = LiveLlmDiagnosticThinkingObserver.reasoningChars(
      off.content,
    );
    final (classification, status, summary) = switch ((
      onChars > 0,
      offChars > 0,
    )) {
      (true, false) => (
        _thinkingControlled,
        LiveLlmDiagnosticStatus.passed,
        'The endpoint honours enable_thinking in both directions.',
      ),
      (true, true) => (
        _thinkingAlwaysOn,
        LiveLlmDiagnosticStatus.warning,
        'The model reasoned with thinking switched off; something on the way '
            'ignores enable_thinking: false.',
      ),
      (false, false) => (
        _thinkingNeverObserved,
        LiveLlmDiagnosticStatus.warning,
        'No reasoning came back with thinking switched on. A router or server '
            'default may force thinking off, or the model does not reason.',
      ),
      (false, true) => (
        _thinkingInverted,
        LiveLlmDiagnosticStatus.warning,
        'Reasoning came back only with thinking switched off, the reverse of '
            'the request.',
      ),
    };
    return LiveLlmDiagnosticProbeResult(
      id: _thinkingControlProbeId,
      status: status,
      summary: summary,
      details:
          'Classification: $classification\n'
          'Thinking on: $onChars reasoning chars '
          '(finish_reason: ${on.finishReason})\n'
          'Thinking off: $offChars reasoning chars '
          '(finish_reason: ${off.finishReason})',
      usage: LiveLlmDiagnosticEvidence.totalUsage([on, off]),
      metadata: {thinkingControlMetadataKey: classification},
    );
  }

  /// Asks the endpoint whether it accepts video, rather than sending one.
  ///
  /// Every other probe here spends a generation to find out what a model does.
  /// This one is a single GET: uploading a clip to learn the answer would cost
  /// far more than the question is worth, and a server that decodes video says
  /// so in its own metadata. Silence is reported as unknown, never as a denial
  /// -- a proxy in front of a capable server answers nothing at all.
  Future<LiveLlmDiagnosticProbeResult> _runVideoInputModalityProbe() async {
    final timer = Stopwatch()..start();
    final client = http.Client();
    final EndpointModalitySupport support;
    try {
      support = await const OpenAiModalitiesProbe().videoSupport(
        baseUrl: settings.baseUrl,
        model: settings.effectiveModel,
        client: client,
        headers: ApiConstants.userAgentHeaders,
      );
    } finally {
      client.close();
      timer.stop();
    }

    return switch (support) {
      EndpointModalitySupport.supported => LiveLlmDiagnosticProbeResult(
        id: _videoInputModalityProbeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The endpoint accepts video input.',
        details: 'Classification: $_videoModalitySupported',
        elapsed: timer.elapsed,
      ),
      EndpointModalitySupport.unsupported => LiveLlmDiagnosticProbeResult(
        id: _videoInputModalityProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary:
            'The endpoint lists its modalities and video is not among them.',
        details: 'Classification: $_videoModalityUnsupported',
        elapsed: timer.elapsed,
      ),
      // Skipped, not failed and not a warning: most endpoints never advertise
      // their modalities, and nothing in the OpenAI specification asks them to.
      // Warning here would fire on every run against every cloud provider and
      // mean nothing by the second time anyone saw it.
      EndpointModalitySupport.unknown => LiveLlmDiagnosticProbeResult(
        id: _videoInputModalityProbeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'The endpoint does not advertise its input modalities.',
        details:
            'Classification: $_videoModalityUnknown\n'
            'Turn video on for this endpoint by hand if the server behind it '
            'decodes video.',
        elapsed: timer.elapsed,
      ),
    };
  }

  /// How close a numeric reading may be and still count.
  ///
  /// Measured, not guessed. Asked for all four readings in one turn against
  /// qwen3.8-27b-vision, the model answered "78, 40, Dune, Cobalt": three
  /// exactly right and Aster read as 40 where the bar is 41. Demanding the
  /// unit meant failing a model whose own reasoning said "Aster: top aligns
  /// with 40" -- it had read the chart, off a y axis whose gridlines are 20
  /// apart, and the probe was measuring interpolation to the pixel instead.
  ///
  /// The cost is that snapping every bar to the nearest gridline now passes.
  /// That is the intended floor: reading a chart to the nearest gridline is
  /// reading it, and a model that never looked still cannot land within two
  /// units of both 78 and 41 by chance.
  static const int chartValueTolerance =
      LiveLlmResponseScoring.chartValueTolerance;

  /// How many of the chart's readings the model got right, position by
  /// position.
  ///
  /// Grades the visible answer rather than the raw response. A reasoning model
  /// narrates the axis on its way to an answer -- "gridlines (0, 20, 40, 60,
  /// 80, 100)" -- and scanning that text for the expected numbers scores the
  /// thinking, not the reading.
  ///
  /// Compares field to field rather than scanning for each answer in turn. The
  /// prompt asks for four comma-separated items, so the second item is the
  /// answer to the second question: "41, 78, Cobalt, Dune" holds all four
  /// readings and answers none of the questions asked. Scanning also let one
  /// wrong reading swallow the rest, which is how a 3-of-4 answer was first
  /// reported as 1/4.
  @visibleForTesting
  static int matchedChartAnswers(String content) =>
      LiveLlmResponseScoring.matchedChartAnswers(content);

  Future<LiveLlmDiagnosticProbeResult> _runNarrowToolCallProbe(
    _ToolCatalogContext catalog,
  ) async {
    final dateTool = _singleTool(catalog.definitions, 'get_current_datetime');
    if (dateTool == null) {
      return _toolProbeUnavailable(_narrowToolCallProbeId);
    }

    final result = await _chat.createChatCompletion(
      messages: _messages(
        user:
            'Call the get_current_datetime tool now. Do not answer in text '
            'before using the tool.',
      ),
      tools: [dateTool],
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final toolCalls = LiveLlmResponseScoring.toolCallsFrom(result);
    final names = toolCalls.map((call) => call.name).toList(growable: false);
    if (toolCalls.any((call) => call.name == 'get_current_datetime')) {
      return LiveLlmDiagnosticProbeResult(
        id: _narrowToolCallProbeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model emitted the expected built-in tool call.',
        toolCalls: names,
        modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
        usage: LiveLlmDiagnosticEvidence.usage(result),
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _narrowToolCallProbeId,
      status: LiveLlmDiagnosticStatus.failed,
      summary: 'The model did not emit get_current_datetime.',
      details: names.isEmpty
          ? 'No tool calls were returned.'
          : names.join(', '),
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      toolCalls: names,
      usage: LiveLlmDiagnosticEvidence.usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runGoalUpdateFidelityProbe() async {
    final result = await _chat.createChatCompletion(
      messages: _messages(
        user:
            'The active goal is complete. Report that state by calling '
            'update_goal exactly once with completed set to the JSON boolean '
            'literal true, not the string "true" or "True". Do not add '
            'message or blocked_reason, and do not answer in text.',
      ),
      tools: [McpGoalRoutineToolDefinitions.updateGoalTool],
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final calls = LiveLlmResponseScoring.toolCallsFrom(result);
    final names = calls.map((call) => call.name).toList(growable: false);
    final argumentValidationError =
        calls.length == 1 && calls.single.name == 'update_goal'
        ? GoalUpdateInput.validateArguments(calls.single.arguments)
        : null;
    final passed =
        calls.length == 1 &&
        calls.single.name == 'update_goal' &&
        argumentValidationError == null &&
        calls.single.arguments.length == 1 &&
        calls.single.arguments['completed'] == true;
    return LiveLlmDiagnosticProbeResult(
      id: _goalUpdateFidelityProbeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.failed,
      summary: passed
          ? 'The model emitted the exact goal-completion tool call.'
          : 'The model did not emit the exact goal-completion tool call.',
      details: passed
          ? 'Observed update_goal with {"completed":true}; it was not executed.'
          : calls.isEmpty
          ? 'No tool calls were returned.'
          : [
              ?argumentValidationError,
              ...calls.map(
                (call) => '${call.name}: ${jsonEncode(call.arguments)}',
              ),
            ].join('\n'),
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      toolCalls: names,
      usage: LiveLlmDiagnosticEvidence.usage(result),
      metadata: {
        ..._goalUpdateRequestMetadata(),
        'argumentValidationError': ?argumentValidationError,
      },
    );
  }

  /// The contract this probe put on the wire, kept beside the model's call so
  /// a string boolean stays visible as a model miss rather than a schema miss.
  Map<String, String> _goalUpdateRequestMetadata() {
    final tools = [McpGoalRoutineToolDefinitions.updateGoalTool];
    final function =
        tools.single['function'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final parameters =
        function['parameters'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final properties = parameters['properties'];
    final completed = properties is Map ? properties['completed'] : null;
    final completedType = completed is Map ? completed['type'] : null;
    final requiredFields = parameters['required'];
    final toolChoice = StrictToolChoicePolicy.openAiToolChoice(tools);
    final metadata = <String, String>{
      'toolName': '${function['name']}',
      'completedType': '$completedType',
      'required': requiredFields is List ? requiredFields.join(',') : '',
      'additionalProperties': '${parameters['additionalProperties']}',
      'temperature': '$_diagnosticTemperature',
      if (toolChoice != null) 'toolChoice': jsonEncode(toolChoice),
    };
    final remote = chatDataSource;
    if (remote is ChatRemoteDataSource) {
      final overrides = remote.thinkingOverrides(
        model: _diagnosticModel,
        maxTokens: _diagnosticMaxTokens,
      );
      final enableThinking = overrides?.topLevelEnableThinking;
      if (enableThinking != null) {
        metadata['enableThinking'] = '$enableThinking';
      }
      final template = overrides?.chatTemplateKwargs;
      if (template != null) {
        metadata['chatTemplateKwargs'] = jsonEncode(template);
      }
    }
    return metadata;
  }

  Future<LiveLlmDiagnosticReport> _appendToolLoopSamplerCalibrationTrials({
    required LiveLlmDiagnosticReport report,
    required _ToolCatalogContext catalog,
    required LlmProviderCapabilities capabilities,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!capabilities.supportsNativeToolCalls ||
        !_shouldRunProbe(_narrowToolCallProbeId, selectedProbeIds)) {
      return report;
    }
    final dateTool = _singleTool(catalog.definitions, 'get_current_datetime');
    if (dateTool == null) {
      return report;
    }
    if (_temperatureSweepIsMeaningless) {
      return _markSamplerCalibrationUnmeasured(report, onReport);
    }

    final trials = <LiveLlmDiagnosticSamplerTrial>[];
    for (var repeat = 0; repeat < _samplerCalibrationRepeatCount; repeat += 1) {
      for (final temperature in _samplerCalibrationTemperatures) {
        trials.add(
          await _samplerTrials.toolLoop(
            dateTool: dateTool,
            temperature: temperature,
          ),
        );
      }
    }
    if (_temperatureSweepIsMeaningless) {
      return _markSamplerCalibrationUnmeasured(report, onReport);
    }
    if (trials.isEmpty) {
      return report;
    }

    final updated = report.copyWith(
      samplerCalibrationTrials: [...report.samplerCalibrationTrials, ...trials],
    );
    onReport?.call(updated);
    return updated;
  }

  Future<LiveLlmDiagnosticReport> _appendRoutineSamplerCalibrationTrials({
    required LiveLlmDiagnosticReport report,
    required LlmProviderCapabilities capabilities,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!capabilities.supportsLlmMemoryExtraction ||
        !_shouldRunProbe(_instructionProbeId, selectedProbeIds)) {
      return report;
    }
    if (_temperatureSweepIsMeaningless) {
      return _markSamplerCalibrationUnmeasured(report, onReport);
    }

    final trials = <LiveLlmDiagnosticSamplerTrial>[];
    for (var repeat = 0; repeat < _samplerCalibrationRepeatCount; repeat += 1) {
      for (final temperature in _samplerCalibrationTemperatures) {
        trials.add(await _samplerTrials.routine(temperature: temperature));
      }
    }
    // The first trials can be what teaches the endpoint's 400 to the fallback,
    // so re-check before keeping anything.
    if (_temperatureSweepIsMeaningless) {
      return _markSamplerCalibrationUnmeasured(report, onReport);
    }
    if (trials.isEmpty) {
      return report;
    }

    final updated = report.copyWith(
      samplerCalibrationTrials: [...report.samplerCalibrationTrials, ...trials],
    );
    onReport?.call(updated);
    return updated;
  }

  Future<LiveLlmDiagnosticReport> _appendCodingPlanSamplerCalibrationTrials({
    required LiveLlmDiagnosticReport report,
    required LlmProviderCapabilities capabilities,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!capabilities.supportsLlmMemoryExtraction ||
        !_shouldRunProbe(_instructionProbeId, selectedProbeIds)) {
      return report;
    }
    if (_temperatureSweepIsMeaningless) {
      return _markSamplerCalibrationUnmeasured(report, onReport);
    }

    final trials = <LiveLlmDiagnosticSamplerTrial>[];
    for (var repeat = 0; repeat < _samplerCalibrationRepeatCount; repeat += 1) {
      for (final temperature in _samplerCalibrationTemperatures) {
        trials.add(await _samplerTrials.coding(temperature: temperature));
        trials.add(await _samplerTrials.plan(temperature: temperature));
      }
    }
    if (_temperatureSweepIsMeaningless) {
      return _markSamplerCalibrationUnmeasured(report, onReport);
    }
    if (trials.isEmpty) {
      return report;
    }

    final updated = report.copyWith(
      samplerCalibrationTrials: [...report.samplerCalibrationTrials, ...trials],
    );
    onReport?.call(updated);
    return updated;
  }

  Future<LiveLlmDiagnosticProbeResult> _runToolResultProbe(
    _ToolCatalogContext catalog,
  ) async {
    final service = mcpToolService;
    final dateTool = _singleTool(catalog.definitions, 'get_current_datetime');
    if (service == null || dateTool == null) {
      return _toolProbeUnavailable(_toolResultProbeId);
    }

    final messages = _messages(
      user:
          'Call get_current_datetime. After the tool result arrives, return '
          'JSON with probe="datetime_tool_result", marker="$_toolResultMarker", '
          'today copied from relative_dates.today, and timezone copied from the '
          'tool result.',
    );
    final firstResult = await _chat.createChatCompletion(
      messages: messages,
      tools: [dateTool],
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final firstToolCalls = LiveLlmResponseScoring.toolCallsFrom(firstResult);
    final call = firstToolCalls
        .where((item) => item.name == 'get_current_datetime')
        .firstOrNull;
    if (call == null) {
      return LiveLlmDiagnosticProbeResult(
        id: _toolResultProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The model did not request the datetime tool.',
        toolCalls: firstToolCalls
            .map((item) => item.name)
            .toList(growable: false),
        modelContent: LiveLlmDiagnosticEvidence.preview(firstResult.content),
        usage: LiveLlmDiagnosticEvidence.usage(firstResult),
      );
    }

    final toolExecution = await service.executeTool(
      name: call.name,
      arguments: call.arguments,
    );
    if (!toolExecution.isSuccess) {
      return LiveLlmDiagnosticProbeResult(
        id: _toolResultProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The built-in datetime tool failed.',
        details: toolExecution.errorMessage ?? toolExecution.result,
        toolCalls: [call.name],
        usage: LiveLlmDiagnosticEvidence.usage(firstResult),
      );
    }

    final expected = LiveLlmResponseScoring.tryDecodeJsonObject(
      toolExecution.result,
    );
    final relativeDates = expected?['relative_dates'];
    final today = relativeDates is Map
        ? relativeDates['today'] as String?
        : null;
    final timezone = expected?['timezone'] as String?;
    final followUp = await _chat.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: call.id.isEmpty ? 'diagnostic-datetime-call' : call.id,
          name: call.name,
          arguments: call.arguments,
          result: toolExecution.result,
        ),
      ],
      // This probe measures whether the model uses the returned value in its
      // answer. The multi-round probe separately measures further tool calls.
      tools: const <Map<String, dynamic>>[],
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final content = followUp.content.trim();
    final followUpCalls = LiveLlmResponseScoring.toolCallsFrom(followUp);
    final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(content);
    final markerOk =
        decoded?['marker'] == _toolResultMarker ||
        content.contains(_toolResultMarker);
    final todayOk = today == null || content.contains(today);
    final timezoneOk = timezone == null || content.contains(timezone);
    final passed = followUpCalls.isEmpty && markerOk && todayOk && timezoneOk;
    final unexpectedCalls = followUpCalls.map((call) => call.name).toList();
    return LiveLlmDiagnosticProbeResult(
      id: _toolResultProbeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model integrated the tool result into its final answer.'
          : unexpectedCalls.isNotEmpty
          ? 'The model requested another tool instead of completing the answer.'
          : content.isEmpty
          ? 'The model returned no final answer after the tool result.'
          : 'The model did not clearly copy all tool-result fields.',
      details: [
        if (today != null) 'Expected today: $today',
        if (timezone != null) 'Expected timezone: $timezone',
        if (unexpectedCalls.isNotEmpty)
          'Unexpected follow-up tool calls: ${unexpectedCalls.join(", ")}',
        if (content.isEmpty) 'Finish reason: ${followUp.finishReason}',
      ].join('\n'),
      modelContent: LiveLlmDiagnosticEvidence.preview(content),
      toolCalls: [call.name, ...unexpectedCalls],
      usage: LiveLlmDiagnosticEvidence.usage(followUp),
    );
  }

  Future<LiveLlmDiagnosticReport> _runMultiRoundToolLoopProbe({
    required LiveLlmDiagnosticReport report,
    required _ToolCatalogContext catalog,
    required Set<String>? selectedProbeIds,
    required LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    if (!_shouldRunProbe(_multiRoundToolLoopProbeId, selectedProbeIds)) {
      final updated = _skipProbe(
        report,
        _multiRoundToolLoopProbeId,
        'Skipped because this bounded diagnostic run did not request this probe.',
      );
      onReport?.call(updated);
      return updated;
    }

    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _multiRoundToolLoopProbeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);

    try {
      final outcome = await _multiRoundProbe.run(
        searchTool: _singleTool(
          catalog.definitions,
          ToolDefinitionSearchService.toolName,
        ),
        dateTool: _singleTool(catalog.definitions, 'get_current_datetime'),
        execute: mcpToolService?.executeTool,
      );
      updated = updated
          .withProbeResult(
            outcome.result.copyWith(
              elapsed: DateTime.now().difference(startedAt),
            ),
          )
          .copyWith(multiRoundToolLoopMetrics: outcome.metrics);
    } catch (error) {
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: _multiRoundToolLoopProbeId,
          status: LiveLlmDiagnosticStatus.failed,
          summary: 'The multi-round tool loop request failed.',
          details: error.toString(),
          elapsed: DateTime.now().difference(startedAt),
        ),
      );
    }
    onReport?.call(updated);
    return updated;
  }

  Future<LiveLlmDiagnosticProbeResult> _runInitialHarnessProbe(
    _ToolCatalogContext catalog,
  ) async {
    if (!catalog.catalog.hasTools) {
      return _toolProbeUnavailable(_initialHarnessProbeId);
    }
    final result = await _chat.createChatCompletion(
      messages: _messages(
        user:
            'Using the currently exposed Caverno initial tool set, call '
            'get_current_datetime exactly once. Do not call tool_search.',
      ),
      tools: catalog.initialDefinitions,
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final names = LiveLlmResponseScoring.toolCallsFrom(
      result,
    ).map((call) => call.name).toList(growable: false);
    if (names.contains('get_current_datetime')) {
      return LiveLlmDiagnosticProbeResult(
        id: _initialHarnessProbeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model selected the datetime tool from the harness set.',
        details:
            'Initial tool count: ${catalog.catalog.initialToolCount}. '
            'Tool search enabled: ${catalog.toolSearchEnabled}.',
        toolCalls: names,
        modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
        usage: LiveLlmDiagnosticEvidence.usage(result),
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _initialHarnessProbeId,
      status: names.contains(ToolDefinitionSearchService.toolName)
          ? LiveLlmDiagnosticStatus.warning
          : LiveLlmDiagnosticStatus.failed,
      summary: names.contains(ToolDefinitionSearchService.toolName)
          ? 'The model used tool_search instead of the directly exposed tool.'
          : 'The model did not select the expected harness tool.',
      details:
          'Initial tool count: ${catalog.catalog.initialToolCount}. '
          'Returned calls: ${names.isEmpty ? "(none)" : names.join(", ")}',
      toolCalls: names,
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      usage: LiveLlmDiagnosticEvidence.usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runToolSearchProbe(
    _ToolCatalogContext catalog,
  ) async {
    final service = mcpToolService;
    if (!catalog.toolSearchEnabled ||
        !_containsTool(
          catalog.initialDefinitions,
          ToolDefinitionSearchService.toolName,
        )) {
      return const LiveLlmDiagnosticProbeResult(
        id: _toolSearchProbeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'Tool search is not active for the current tool catalog size.',
      );
    }
    if (service == null) {
      return _toolProbeUnavailable(_toolSearchProbeId);
    }

    final result = await _chat.createChatCompletion(
      messages: _messages(
        user:
            'Use the tool catalog search tool to find a tool for delegating a '
            'focused sub-task to another agent. Call tool_search only.',
      ),
      tools: catalog.initialDefinitions,
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final calls = LiveLlmResponseScoring.toolCallsFrom(result);
    final names = calls.map((call) => call.name).toList(growable: false);
    final searchCall = calls
        .where((call) => call.name == ToolDefinitionSearchService.toolName)
        .firstOrNull;
    if (searchCall == null) {
      return LiveLlmDiagnosticProbeResult(
        id: _toolSearchProbeId,
        status: names.contains('spawn_subagent')
            ? LiveLlmDiagnosticStatus.warning
            : LiveLlmDiagnosticStatus.failed,
        summary: names.contains('spawn_subagent')
            ? 'The model found subagents directly, but skipped tool_search.'
            : 'The model did not use the tool catalog search tool.',
        toolCalls: names,
        modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
        usage: LiveLlmDiagnosticEvidence.usage(result),
      );
    }

    final toolResult = await service.executeTool(
      name: searchCall.name,
      arguments: searchCall.arguments,
    );
    final foundSubagent = toolResult.result.contains('spawn_subagent');
    return LiveLlmDiagnosticProbeResult(
      id: _toolSearchProbeId,
      status: foundSubagent
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: foundSubagent
          ? 'The model used tool_search and surfaced the subagent tool.'
          : 'The model used tool_search, but the result did not include subagents.',
      details: LiveLlmDiagnosticEvidence.preview(
        toolResult.result,
        maxChars: 1200,
      ),
      toolCalls: names,
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      usage: LiveLlmDiagnosticEvidence.usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runSubagentProbe(
    _ToolCatalogContext catalog,
  ) async {
    final subagentTools = _toolsNamed(catalog.definitions, {
      'spawn_subagent',
      'get_subagent_result',
    });
    if (subagentTools.isEmpty) {
      return _toolProbeUnavailable(_subagentProbeId);
    }
    // Phrased as the delegation task production would ask for, not as a request
    // to "emit a tool call". Measured 2026-08-11 on qwen3.6-35b-a3b-vision: the
    // old meta-framing ("For diagnostics only, emit a spawn_subagent tool
    // call") made the model print the argument object as message content in 5
    // of 5 runs, while the same tools with this phrasing produce a native call
    // and the same meta-framing with `get_current_datetime` also produces one.
    // The probe was measuring its own wording. Nothing is executed either way —
    // the result is only inspected — so the natural phrasing costs no safety.
    final result = await _chat.createChatCompletion(
      messages: _messages(
        user:
            'Delegate a sub-task to a subagent and run it in the background so '
            'you get a task id immediately: it should summarize the marker '
            '"$_subagentMarker". Do not answer in text.',
      ),
      tools: subagentTools,
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final calls = LiveLlmResponseScoring.toolCallsFrom(result);
    final names = calls.map((call) => call.name).toList(growable: false);
    final spawnCall = calls
        .where((call) => call.name == 'spawn_subagent')
        .firstOrNull;
    if (spawnCall == null) {
      return LiveLlmDiagnosticProbeResult(
        id: _subagentProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The model did not emit spawn_subagent.',
        toolCalls: names,
        modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
        usage: LiveLlmDiagnosticEvidence.usage(result),
      );
    }
    final hasPrompt =
        (spawnCall.arguments['prompt'] as String?)?.contains(_subagentMarker) ??
        false;
    final hasDescription =
        (spawnCall.arguments['description'] as String?)?.trim().isNotEmpty ??
        false;
    final background = spawnCall.arguments['background'] == true;
    final passed = hasPrompt && hasDescription && background;
    return LiveLlmDiagnosticProbeResult(
      id: _subagentProbeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model recognized the subagent contract and required fields.'
          : 'The model emitted spawn_subagent, but the arguments were incomplete.',
      details:
          'description=$hasDescription, promptMarker=$hasPrompt, '
          'background=$background',
      toolCalls: names,
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      usage: LiveLlmDiagnosticEvidence.usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runRemoteMcpProbe(
    _ToolCatalogContext catalog,
  ) async {
    if (catalog.catalog.remoteServerCount == 0) {
      return const LiveLlmDiagnosticProbeResult(
        id: _remoteMcpProbeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'No trusted remote MCP servers are enabled.',
      );
    }
    if (catalog.catalog.remoteToolCount == 0) {
      return LiveLlmDiagnosticProbeResult(
        id: _remoteMcpProbeId,
        status: LiveLlmDiagnosticStatus.warning,
        summary: 'Remote MCP servers are enabled, but no remote tools loaded.',
        details: catalog.catalog.mcpConnectionSummary,
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _remoteMcpProbeId,
      status: LiveLlmDiagnosticStatus.passed,
      summary:
          'Remote MCP tools are visible to the Caverno harness '
          '(${catalog.catalog.remoteToolCount}).',
      details: [
        catalog.catalog.mcpConnectionSummary,
        'Remote tools: ${catalog.catalog.remoteToolNames.take(12).join(", ")}',
      ].where((line) => line.trim().isNotEmpty).join('\n'),
    );
  }

  LiveLlmDiagnosticProbeResult _toolProbeUnavailable(String probeId) {
    final summary = !settings.mcpEnabled
        ? 'Skipped because MCP tools are disabled in settings.'
        : 'Required diagnostic tools are not available.';
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: !settings.mcpEnabled
          ? LiveLlmDiagnosticStatus.skipped
          : LiveLlmDiagnosticStatus.warning,
      summary: summary,
    );
  }

  List<Message> _messages({required String user}) {
    final now = DateTime.now();
    final capabilities = settings.llmCapabilities;
    final toolInstruction = capabilities.supportsNativeToolCalls
        ? 'Prefer OpenAI tool calls when the user asks for a tool.'
        : capabilities.supportsTextualToolBridge
        ? 'When tools are available, use the Caverno tool bridge tag exactly '
              'when the user asks for a tool.'
        : 'Tool calling is not supported by the selected provider.';
    return [
      Message(
        id: 'live-llm-diagnostic-system-${now.microsecondsSinceEpoch}',
        content:
            'You are running inside Caverno live LLM diagnostics. Follow the '
            'user request exactly. $toolInstruction '
            '${SystemPromptConstants.exactPreservationInstruction}',
        role: MessageRole.system,
        timestamp: now,
      ),
      Message(
        id: 'live-llm-diagnostic-user-${now.microsecondsSinceEpoch}',
        content: user,
        role: MessageRole.user,
        timestamp: now,
      ),
    ];
  }

  List<Map<String, dynamic>> _toolsNamed(
    List<Map<String, dynamic>> definitions,
    Set<String> names,
  ) {
    return definitions
        .where((definition) {
          final name = ToolDefinitionSearchService.toolNameFromDefinition(
            definition,
          );
          return name != null && names.contains(name);
        })
        .toList(growable: false);
  }

  Map<String, dynamic>? _singleTool(
    List<Map<String, dynamic>> definitions,
    String name,
  ) {
    for (final definition in definitions) {
      if (ToolDefinitionSearchService.toolNameFromDefinition(definition) ==
          name) {
        return definition;
      }
    }
    return null;
  }

  bool _containsTool(List<Map<String, dynamic>> definitions, String name) {
    return _singleTool(definitions, name) != null;
  }

  List<String> _toolNamesFromDefinitions(
    Iterable<Map<String, dynamic>> definitions,
  ) {
    return definitions
        .map(ToolDefinitionSearchService.toolNameFromDefinition)
        .whereType<String>()
        .toList(growable: false);
  }

  bool _isRemoteMcpTool(Map<String, dynamic> definition) {
    return definition[McpToolEntity.openAiExternalToolKey] == true;
  }

  String _mcpStateSummary(McpToolService service) {
    if (service.serverStates.isEmpty) {
      if (settings.enabledMcpServers.isEmpty) {
        return 'No trusted remote MCP servers are enabled.';
      }
      return service.lastError ?? '';
    }
    return service.serverStates
        .map((state) {
          final error = state.lastError == null ? '' : ': ${state.lastError}';
          return '${state.identifier}: ${state.status.name}, '
              '${state.toolCount} tool(s)$error';
        })
        .join('\n');
  }
}

class _ToolCatalogContext {
  const _ToolCatalogContext({
    required this.definitions,
    required this.initialDefinitions,
    required this.selectedToolNames,
    required this.toolSearchEnabled,
    required this.catalog,
  });

  final List<Map<String, dynamic>> definitions;
  final List<Map<String, dynamic>> initialDefinitions;
  final Set<String> selectedToolNames;
  final bool toolSearchEnabled;
  final LiveLlmDiagnosticToolCatalog catalog;
}

class _FoundationModelsLanguageProbeCase {
  const _FoundationModelsLanguageProbeCase({
    required this.label,
    required this.marker,
    required this.userPrompt,
    this.tools,
  });

  final String label;
  final String marker;
  final String userPrompt;
  final List<Map<String, dynamic>>? tools;
}

class _EditFormatProbeCase {
  const _EditFormatProbeCase({
    required this.preference,
    required this.instruction,
    required this.expected,
    this.normalize,
  });

  final ModelEditFormatPreference preference;
  final String instruction;
  final String expected;

  /// Applied to both sides before comparison, to drop spelling differences the
  /// format permits. Null compares the text verbatim.
  final String Function(String value)? normalize;

  String prepare(String value) => normalize?.call(value) ?? value;
}

class _EditFormatProbeOutcome {
  const _EditFormatProbeOutcome({
    required this.preference,
    required this.passed,
    required this.failureDetail,
    required this.content,
    required this.usage,
  });

  final ModelEditFormatPreference preference;
  final bool passed;
  final String? failureDetail;
  final String content;
  final LiveLlmDiagnosticTokenUsage usage;
}

/// One embeddings call plus the reason it produced nothing, when it did.
class _EmbeddingAttempt {
  const _EmbeddingAttempt({required this.result, this.failure});

  final EmbeddingsResult? result;
  final EmbeddingsFailure? failure;
}

class _FoundationModelsLanguageProbeOutcome {
  const _FoundationModelsLanguageProbeOutcome({
    required this.label,
    required this.passed,
    required this.classification,
    required this.preview,
  });

  final String label;
  final bool passed;
  final String classification;
  final String preview;

  String toDetailLine() {
    return '$label: ${passed ? 'passed' : 'failed'} ($classification)';
  }
}
