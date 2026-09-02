import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/system_prompt_constants.dart';
import '../../../../core/services/apple_foundation_models_platform_client.dart';
import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/data/datasources/embeddings_client.dart';
import '../../../chat/data/datasources/embeddings_math.dart';
import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/data/datasources/mcp_tool_service.dart';
import '../../../chat/data/datasources/openai_modalities_probe.dart';
import '../../../chat/data/datasources/mcp_goal_routine_tool_definitions.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/services/tool_definition_search_service.dart';
import '../../../chat/domain/services/tool_result_prompt_builder.dart';
import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_chart_probe_image.dart';
import 'llm_provider_capabilities.dart';
import 'llm_sampler_preset_profile.dart';

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
  });

  final AppSettings settings;
  final ChatDataSource chatDataSource;
  final McpToolService? mcpToolService;
  final EmbedTexts? embedTexts;
  final int effectiveContextMaxTokens;
  final RunEffectiveContextTrial? runEffectiveContextTrial;

  static const probeDefinitions = <LiveLlmDiagnosticProbeDefinition>[
    LiveLlmDiagnosticProbeDefinition(
      id: _instructionProbeId,
      titleKey: 'settings.live_llm_diag_probe_instruction_title',
      descriptionKey: 'settings.live_llm_diag_probe_instruction_desc',
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
  ];

  static const _instructionProbeId = 'instruction_echo';
  static const _structuredOutputProbeId = 'structured_output';
  static const _streamingProbeId = 'streaming_response';
  static const _exactPreservationProbeId = 'exact_preservation';
  static const _editFormatProbeId = 'edit_format_fidelity';
  static const _embeddingsProbeId = 'embeddings_capability';
  static const _effectiveContextProbeId = 'effective_context';
  static const _foundationModelsLanguageMatrixProbeId =
      'foundation_models_language_matrix';
  static const _visionAttachmentProbeId = 'vision_attachment';
  static const _chartReadingProbeId = 'chart_reading';
  static const _videoInputModalityProbeId = 'video_input_modality';
  static const _visionToolObservationProbeId = 'vision_tool_observation';
  static const _narrowToolCallProbeId = 'narrow_tool_call';
  static const _goalUpdateFidelityProbeId = 'update_goal_fidelity';
  static const _toolResultProbeId = 'tool_result_integration';
  static const _multiRoundToolLoopProbeId = 'multi_round_tool_loop';
  static const _initialHarnessProbeId = 'initial_harness_selection';
  static const _toolSearchProbeId = 'tool_search_catalog';
  static const _subagentProbeId = 'subagent_recognition';
  static const _remoteMcpProbeId = 'remote_mcp_exposure';
  static const _multiRoundToolLoopMarker = 'CAVERNO_MULTI_ROUND_LOOP_OK';

  /// The streaming probe asks for a run of integers rather than prose: the
  /// content is verifiable without a judge, and it is long enough that the
  /// decode rate means something. Phrased as the task ("list the integers"),
  /// not as the mechanism ("stream me a response") — a probe that describes the
  /// mechanism measures its own wording.
  static const _streamingSequenceLength = 40;
  static const _streamingProbePrompt =
      'List every integer from 1 to 40 in order, one per line, with nothing '
      'else on any line.';

  static const modelCapabilityProbeIds = <String>{
    _instructionProbeId,
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
  static const visionProbeImageBase64 = _visionProbeImageBase64;

  static const _visionProbeImageBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAYAAAAGACAIAAAArpSLoAAAEpElEQVR42u3UwQkAMAwDMe'
      '+/tLtD8glFoAkMvrSBsaQw50IIEAKEACFAIEAIEAKEAIEAIUAIEAIEAoQAIUAIEAIEAoQA'
      'IUAIEAgQAoQAIUAgQAgQAoQAgQAhQAgQAoQAgQAhQAgQAgQChAAhQAgQCBAChAAhQCBACB'
      'AChAAhQCBACBAChACBACFACBACBAKEACFACBC4EAKEACFACBAIEAKEACFAIEAIEAKEAIEA'
      'IUAIEAKEAHkRAoQAIUAIEAgQAoQAIUAgQAgQAoQAgQAhQAgQAoQAgQAhQAgQAgQChAAhQA'
      'gQCBAChAAhQCBACBAChAAhQCBACBAChACBACFACBACBAKEACFACBAIEAKEACFACBAIEAKE'
      'ACFAIEAIEAKEAIEAIUAIEAIELoQAIUAIEAIEAoQAIUAIEAgQAoQAIUAgQAgQAoQAIUAgQA'
      'gQAoQAgQAhQAgQAgQChAAhQAgQCBAChAAhQAgQCBAChAAhQCBACBAChACBACFACBACBAKE'
      'ACFACBACBAKEACFACBAIEAKEACFAIEAIEAKEAIEAIUAIEAKEAIEAIUAIEAIEAoQAIUAIEA'
      'gQAoQAIUAIEAgQAoQAIUAgQAgQAoQAgQAhQAgQAgQChAAhQAgQAgQChAAhQAgQCBAChAAh'
      'QCBACBAChACBACFACBAChACBACFACBACBAKEACFACBAIEAKEACFAIEAIEAKEACFAIEAIEA'
      'KEAIEAIUAIEAIEAoQAIUAIELgQAoQAIUAIEAgQAoQAIUAgQAgQAoQAgQAhQAgQAoQAgQAh'
      'QAgQAgQChAAhQAgQCBAChAAhQCBACBAChAAhQCBACBAChACBACFACBACBAKEACFACBAIEA'
      'KEACFACBAIEAKEACFAIEAIEAKEAIEAIUAIEAIEAoQAIUAIEAIEAoQAIUAIEAgQAoQAIUAg'
      'QAgQAoQAIUAuhAAhQAgQAgQChAAhQAgQCBACxM0A2YAFEwACBAgQgAABAgQgQIAAAQgQIE'
      'AAAgQIEIAAAQIEIECAAAEIECBAgAABCBAgQAACBAgQgAABAgQgQIAAAQgQIEAAAgQIEIAA'
      'AQIEIECAAAECBCBAgAABCBAgQAACBAgQgAABAgQgQIAAAQgQIEAAAgQIECBAAAIECBCAAA'
      'ECBCBAgAABCBAgQAACBAgQgAABAgQgQIAAAQgQIECAAAEIECBAAAIECBCAAAECBCBAgAAB'
      'CBAgQAACBAgQgAABAgQIEIAAAQIEIECAAAEIECBAAAIECBCAAAECBCBAgAABCBAgQAACBA'
      'gQIEAAAgQIEIAAAQIEIECAAAEIECBAAAIECBCAAAECBCBAgAABAmQCQIAAAQIQIECAAAQI'
      'ECAAAQIECECAAAECECBAgAAECBAgAAECBAgQIAABAgQIQIAAAQIQIECAAAQIECAAAQIECE'
      'CAAAECECBAgABMAAgQIEAAAgQIEIAAAQIEIECAAAEIECBAAAIECBCAAAECBCBAgAABAgQg'
      'QIAAAQgQIEAAAgQIEIAAAQIEIECAAAEIECBAAAIECBCAAAECBAgQgAABAgQgQIAAAQgQIE'
      'AAAgQIEIAAAQIEIECAAPGdB+I3WgSaUHuyAAAAAElFTkSuQmCC';
  static const _visionProbeImageMimeType = 'image/png';
  static const _visionProbeExpectedColors = <String>[
    'yellow',
    'blue',
    'red',
    'green',
  ];
  static const _visionProbePrompt =
      'The attached image is split into four equal quadrants, each a single '
      'solid color. Reply with exactly the four color names in reading order '
      '(top-left, top-right, bottom-left, bottom-right), lowercase, separated '
      'by commas, and no other text.';

  /// Asks for all four readings in one turn.
  ///
  /// One request per arm rather than one per question: the probe runs on every
  /// diagnostic pass and a chart image is not cheap, and asking separately
  /// measured nothing extra when it was tried against a live endpoint.
  static const _chartProbePrompt =
      'The attached image is a bar chart with a labelled y axis. Reply with '
      'exactly four comma-separated items and no other text: the numeric '
      'height of the bar labelled Briar, the numeric height of the bar '
      'labelled Aster, the label of the tallest bar, the label of the '
      'shortest bar.';

  /// A larger budget than the other probes get.
  ///
  /// This one asks for four readings off a picture, and a reasoning model
  /// narrates the axis before it answers: a measured run spent 628 completion
  /// tokens across the two arms, and at 1024 one run in three still ended
  /// inside the think block with no answer at all. The shared 512 would have
  /// reported that as a model that cannot read charts.
  static const _chartProbeMaxTokens = 1024;

  static const _chartClassificationRejected = 'endpoint_rejected';
  static const _chartClassificationNoAnswer = 'no_answer_within_budget';
  static const _chartClassificationGuessed = 'model_guessed_without_reading';
  static const _chartClassificationPartial = 'partially_read';
  static const _chartClassificationRead = 'read_correctly';

  static const _marker = 'CAVERNO_LIVE_DIAGNOSTIC';
  static const structuredOutputSupportMetadataKey = 'structuredOutputSupport';
  static const _structuredOutputSchemaMarker = 'CAVERNO_SCHEMA_LOCKED_47';
  static const _structuredOutputObjectMarker = 'CAVERNO_JSON_OBJECT_OK';
  static const _structuredOutputSchema = <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'marker': <String, dynamic>{
        'type': 'string',
        'const': _structuredOutputSchemaMarker,
      },
      'count': <String, dynamic>{'type': 'integer', 'const': 47},
    },
    'required': <String>['marker', 'count'],
    'additionalProperties': false,
  };
  static const _foundationModelsEnglishMarker = 'CAVERNO_FM_LANG_EN';
  static const _foundationModelsJapaneseMarker = 'CAVERNO_FM_LANG_JA';
  static const _foundationModelsToolBridgeMarker = 'CAVERNO_FM_LANG_TOOL';
  static const _toolResultMarker = 'CAVERNO_TOOL_RESULT_OK';
  static const _subagentMarker = 'CAVERNO_SUBAGENT_DIAGNOSTIC';
  static const _routineSamplerMarker = 'CAVERNO_ROUTINE_SAMPLER_OK';
  static const _codingSamplerMarker = 'CAVERNO_CODING_SAMPLER_OK';
  static const _planSamplerMarker = 'CAVERNO_PLAN_SAMPLER_OK';
  static const _codingSamplerEditBlock = <String>[
    '<<<<<<< SEARCH',
    'return oldValue;',
    '=======',
    'return newValue;',
    '>>>>>>> REPLACE',
  ];
  static const _planSamplerTasks = <String>['inspect', 'edit', 'verify'];
  static const _exactDirectEchoValue = '12 GiB, \u00a53,980';
  static const _exactToolResultValue = 'ZX-900_\u03b1 2026-06-12';
  static const _exactUrlValue =
      'https://example.test/downloads/build_2026-06-10.tar.zst?sha=abc123_def';
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
  static const _embeddingInputs = <String>[
    'A cat rests on a warm windowsill.',
    'The kitten is sleeping beside a sunny window.',
    'Database backups completed at midnight.',
  ];
  static const _embeddingSemanticMarginMinimum = 0.05;
  static const _effectiveContextInitialTokens = 2048;
  static const _effectiveContextHardMaximumTokens = 1048576;

  /// Vision outcome labels. Emitted into probe details so the profile builder
  /// and a human reading the report classify a miss the same way.
  static const _videoModalitySupported = 'video_input_supported';
  static const _videoModalityUnsupported = 'video_input_unsupported';
  static const _videoModalityUnknown = 'video_input_unknown';

  static const _visionClassificationRejected = 'endpoint_rejected';
  static const _visionClassificationIgnored = 'model_ignored_the_image';
  static const _visionClassificationPartial = 'partially_read';
  static const _visionClassificationRead = 'read_correctly';
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
      report = report.copyWith(finishedAt: DateTime.now());
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
      run: _runExactPreservationProbe,
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
      report = report.copyWith(finishedAt: DateTime.now());
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
      report = report.copyWith(finishedAt: DateTime.now());
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

    report = report.copyWith(finishedAt: DateTime.now());
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
    final result = await chatDataSource.createChatCompletion(
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
    final decoded = _tryDecodeJsonObject(content);
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
        modelContent: _preview(content),
        usage: _usage(result),
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
      modelContent: _preview(content),
      usage: _usage(result),
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

    final completed = <ChatCompletionResult>[];
    String schemaDetail;
    try {
      final schemaResult = await structuredDataSource
          .createStructuredChatCompletion(
            messages: _messages(
              user:
                  'Produce one diagnostic object that follows the supplied response '
                  'schema. Do not add markdown or explanatory text.',
            ),
            responseFormat: const StructuredOutputRequest.jsonSchema(
              name: 'caverno_live_diagnostic',
              schema: _structuredOutputSchema,
            ),
            model: _diagnosticModel,
            temperature: _diagnosticTemperature,
            maxTokens: _diagnosticMaxTokens,
          );
      completed.add(schemaResult);
      final decoded = _tryDecodeJsonObject(schemaResult.content);
      final schemaPassed =
          decoded?.length == 2 &&
          decoded?['marker'] == _structuredOutputSchemaMarker &&
          decoded?['count'] == 47;
      if (schemaPassed) {
        updated = updated.withProbeResult(
          LiveLlmDiagnosticProbeResult(
            id: _structuredOutputProbeId,
            status: LiveLlmDiagnosticStatus.passed,
            summary:
                'The endpoint and model enforced the supplied JSON schema.',
            details: 'json_schema: passed\njson_object fallback: not needed',
            modelContent: _preview(schemaResult.content),
            usage: _usage(schemaResult),
            passedChecks: 2,
            totalChecks: 2,
            metadata: const {structuredOutputSupportMetadataKey: 'jsonSchema'},
            elapsed: DateTime.now().difference(startedAt),
          ),
        );
        onReport?.call(updated);
        return updated;
      }
      schemaDetail =
          'json_schema: request completed but the response violated the schema';
    } catch (error) {
      schemaDetail = 'json_schema: request failed (${_preview('$error')})';
    }

    try {
      final objectResult = await structuredDataSource
          .createStructuredChatCompletion(
            messages: _messages(
              user:
                  'Return one JSON object with exactly these two fields and no '
                  'markdown: {"marker":"$_structuredOutputObjectMarker","count":47}',
            ),
            responseFormat: const StructuredOutputRequest.jsonObject(),
            model: _diagnosticModel,
            temperature: _diagnosticTemperature,
            maxTokens: _diagnosticMaxTokens,
          );
      completed.add(objectResult);
      final decoded = _tryDecodeJsonObject(objectResult.content);
      final objectPassed =
          decoded?.length == 2 &&
          decoded?['marker'] == _structuredOutputObjectMarker &&
          decoded?['count'] == 47;
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: _structuredOutputProbeId,
          status: objectPassed
              ? LiveLlmDiagnosticStatus.warning
              : LiveLlmDiagnosticStatus.failed,
          summary: objectPassed
              ? 'JSON object mode worked, but JSON Schema mode did not.'
              : 'Neither structured-output mode preserved its contract.',
          details: [
            schemaDetail,
            'json_object: ${objectPassed ? 'passed' : 'response violated the contract'}',
          ].join('\n'),
          modelContent: _preview(objectResult.content),
          usage: _totalUsage(completed),
          passedChecks: objectPassed ? 1 : 0,
          totalChecks: 2,
          metadata: {
            structuredOutputSupportMetadataKey: objectPassed
                ? 'jsonObject'
                : 'none',
          },
          elapsed: DateTime.now().difference(startedAt),
        ),
      );
    } catch (error) {
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: _structuredOutputProbeId,
          status: LiveLlmDiagnosticStatus.failed,
          summary: 'Neither structured-output request mode was usable.',
          details: [
            schemaDetail,
            'json_object: request failed (${_preview('$error')})',
          ].join('\n'),
          usage: _totalUsage(completed),
          passedChecks: 0,
          totalChecks: 2,
          metadata: const {structuredOutputSupportMetadataKey: 'none'},
          elapsed: DateTime.now().difference(startedAt),
        ),
      );
    }
    onReport?.call(updated);
    return updated;
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
      final outcome = await _measureStreamingResponse();
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

  Future<_StreamingProbeOutcome> _measureStreamingResponse() async {
    final buffer = StringBuffer();
    var chunkCount = 0;
    Duration? timeToFirstToken;
    final stopwatch = Stopwatch()..start();

    final streamed = chatDataSource.streamChatCompletion(
      messages: _messages(user: _streamingProbePrompt),
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );

    await for (final chunk in streamed.stream) {
      if (chunk.isEmpty) {
        continue;
      }
      // First *content*, not first event: an endpoint that opens the stream
      // with empty keep-alive frames would otherwise report a flattering TTFT.
      timeToFirstToken ??= stopwatch.elapsed;
      chunkCount += 1;
      buffer.write(chunk);
    }
    final totalElapsed = stopwatch.elapsed;
    final terminal = await streamed.terminal;

    final content = buffer.toString();
    final visibleContent = _visibleDiagnosticContent(content);
    final matched = _matchedIntegerSequence(visibleContent);
    final metrics = LiveLlmDiagnosticStreamingMetrics(
      timeToFirstToken: timeToFirstToken ?? totalElapsed,
      totalElapsed: totalElapsed,
      completionTokens: terminal.usage.completionTokens,
      chunkCount: chunkCount,
      finishReason: terminal.finishReason ?? '',
    );

    final truncated = terminal.finishReason == 'length';
    final passed = matched == _streamingSequenceLength && !truncated;
    final status = passed
        ? LiveLlmDiagnosticStatus.passed
        : matched > 0
        ? LiveLlmDiagnosticStatus.warning
        : LiveLlmDiagnosticStatus.failed;
    final rate = metrics.decodeTokensPerSecond;

    return _StreamingProbeOutcome(
      metrics: metrics,
      result: LiveLlmDiagnosticProbeResult(
        id: _streamingProbeId,
        status: status,
        summary: passed
            ? 'The model streamed the full sequence over the streaming path.'
            : truncated
            ? 'The stream was cut short by the token limit.'
            : 'The streamed sequence was incomplete or out of order.',
        details: [
          'Matched in order: $matched/$_streamingSequenceLength',
          'Chunks: $chunkCount',
          'Finish reason: ${terminal.finishReason ?? "(none)"}',
          'TTFT: ${metrics.timeToFirstToken.inMilliseconds} ms',
          'Total: ${metrics.totalElapsed.inMilliseconds} ms',
          if (rate != null) 'Decode: ${rate.toStringAsFixed(1)} tok/s',
          if (metrics.isLikelyBuffered)
            'Buffered delivery: the answer arrived in one chunk or a short '
                'terminal burst, so decode rate is unavailable.',
        ].join('\n'),
        modelContent: _preview(content, maxChars: 400),
        usage: LiveLlmDiagnosticTokenUsage(
          promptTokens: terminal.usage.promptTokens,
          completionTokens: terminal.usage.completionTokens,
          totalTokens: terminal.usage.totalTokens,
        ),
        passedChecks: matched,
        totalChecks: _streamingSequenceLength,
      ),
    );
  }

  /// Counts how many of 1..N appear as their own line, in order. Line-scoped on
  /// purpose: a substring search would count the "1" inside "10".
  int _matchedIntegerSequence(String content) {
    var expected = 1;
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (int.tryParse(trimmed) != expected) {
        continue;
      }
      expected += 1;
      if (expected > _streamingSequenceLength) {
        break;
      }
    }
    return expected - 1;
  }

  Future<LiveLlmDiagnosticProbeResult> _runExactPreservationProbe() async {
    final directResult = await chatDataSource.createChatCompletion(
      messages: _messages(
        user:
            'Reply with exactly this text and no extra characters:\n'
            '$_exactDirectEchoValue',
      ),
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );

    final toolResultMessages = _messages(
      user:
          'Return only the product_label value from the diagnostic tool result. '
          'Do not add quotes, punctuation, or explanatory text.',
    );
    toolResultMessages.add(
      Message(
        id: 'live-llm-diagnostic-tool-result-${DateTime.now().microsecondsSinceEpoch}',
        content: ToolResultPromptBuilder.buildAnswerPrompt(
          [
            ToolResultInfo(
              id: 'diagnostic-exact-value-call',
              name: 'diagnostic_exact_value',
              arguments: const {'field': 'product_label'},
              result:
                  'Raw result:\n'
                  '${jsonEncode({'product_label': _exactToolResultValue})}',
            ),
          ],
          descriptionsByName: const {
            'diagnostic_exact_value':
                'Provides exact raw values for preservation diagnostics.',
          },
        ),
        role: MessageRole.user,
        timestamp: DateTime.now(),
      ),
    );
    final toolResult = await chatDataSource.createChatCompletion(
      messages: toolResultMessages,
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );

    final urlResult = await chatDataSource.createChatCompletion(
      messages: _messages(
        user:
            'Reply with exactly this URL and no extra characters:\n'
            '$_exactUrlValue',
      ),
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );

    final outcomes = [
      _ExactPreservationProbeOutcome(
        label: 'direct_echo_money_unit',
        expected: _exactDirectEchoValue,
        actual: _visibleDiagnosticContent(directResult.content),
        rawActual: directResult.content.trim(),
      ),
      _ExactPreservationProbeOutcome(
        label: 'tool_result_raw_value',
        expected: _exactToolResultValue,
        actual: _visibleDiagnosticContent(toolResult.content),
        rawActual: toolResult.content.trim(),
      ),
      _ExactPreservationProbeOutcome(
        label: 'url_preservation',
        expected: _exactUrlValue,
        actual: _visibleDiagnosticContent(urlResult.content),
        rawActual: urlResult.content.trim(),
      ),
    ];
    final failed = outcomes.where((outcome) => !outcome.passed).toList();
    final status = failed.isEmpty
        ? LiveLlmDiagnosticStatus.passed
        : failed.length == outcomes.length
        ? LiveLlmDiagnosticStatus.failed
        : LiveLlmDiagnosticStatus.warning;
    final summary = failed.isEmpty
        ? 'The model preserved exact literal values across direct and tool-result prompts.'
        : failed.length == outcomes.length
        ? 'The model changed every exact literal preservation probe value.'
        : 'The model changed at least one exact literal preservation probe value.';

    return LiveLlmDiagnosticProbeResult(
      id: _exactPreservationProbeId,
      status: status,
      summary: summary,
      details: outcomes.map(_formatExactPreservationDetail).join('\n\n'),
      modelContent: outcomes
          .map(
            (outcome) =>
                '${outcome.label}: ${_preview(outcome.rawActual, maxChars: 360)}',
          )
          .join('\n'),
      usage: _totalUsage([directResult, toolResult, urlResult]),
      passedChecks: outcomes.length - failed.length,
      totalChecks: outcomes.length,
    );
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
        normalize: _normalizeUnifiedDiffFileHeaders,
      ),
    ];
    final outcomes = <_EditFormatProbeOutcome>[];
    for (final testCase in cases) {
      final result = await chatDataSource.createChatCompletion(
        messages: _messages(
          user:
              'Update the greeting from Hello to Welcome without changing any '
              'other text. The current $_editFormatPath contents are:\n\n'
              '$_editFormatOriginal\n\n${testCase.instruction}',
        ),
        model: _diagnosticModel,
        temperature: _diagnosticTemperature,
        maxTokens: _diagnosticMaxTokens,
      );
      final normalized = _stripSingleCodeFence(
        _visibleDiagnosticContent(result.content),
      );
      final failureDetail = _firstEditFormatMismatch(
        expected: testCase.prepare(testCase.expected),
        actual: testCase.prepare(normalized),
      );
      outcomes.add(
        _EditFormatProbeOutcome(
          preference: testCase.preference,
          passed: failureDetail == null,
          failureDetail: failureDetail,
          content: result.content,
          usage: _usage(result),
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
                '${outcome.preference.name}: ${_preview(outcome.content, maxChars: 360)}',
          )
          .join('\n\n'),
      usage: _sumDiagnosticUsage(outcomes.map((outcome) => outcome.usage)),
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

  String _stripSingleCodeFence(String content) {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    final match = RegExp(
      r'^```(?:dart|diff)?\s*\n([\s\S]*?)\n```$',
      caseSensitive: false,
    ).firstMatch(normalized);
    return (match?.group(1) ?? normalized).trim();
  }

  /// Drops the `a/` and `b/` prefixes from a unified diff's file headers.
  ///
  /// The prefixes are a git convention, not part of the format: `diff -u` and
  /// `patch -p0` write and expect the bare path, and Caverno never consumes the
  /// header at all -- the preference only picks a sentence for the system
  /// prompt. Comparing them verbatim scored a model that produced a perfectly
  /// applicable diff as an edit-format failure, and cost it 18 of 55 points on
  /// a spelling difference. Everything below the header is still compared
  /// exactly, including hunk headers and context lines.
  static String _normalizeUnifiedDiffFileHeaders(String diff) {
    return diff
        .split('\n')
        .map((line) {
          for (final marker in const ['--- ', '+++ ']) {
            if (!line.startsWith(marker)) continue;
            final path = line.substring(marker.length);
            for (final prefix in const ['a/', 'b/']) {
              if (path.startsWith(prefix)) {
                return '$marker${path.substring(prefix.length)}';
              }
            }
            return line;
          }
          return line;
        })
        .join('\n');
  }

  String? _firstEditFormatMismatch({
    required String expected,
    required String actual,
  }) {
    if (expected == actual) return null;
    final expectedLines = const LineSplitter().convert(expected);
    final actualLines = const LineSplitter().convert(actual);
    final sharedLength = math.min(expectedLines.length, actualLines.length);
    for (var index = 0; index < sharedLength; index += 1) {
      if (expectedLines[index] != actualLines[index]) {
        return 'line ${index + 1}: expected `${expectedLines[index]}`, '
            'received `${actualLines[index]}`';
      }
    }
    if (expectedLines.length > actualLines.length) {
      return 'line ${actualLines.length + 1}: expected '
          '`${expectedLines[actualLines.length]}`, received end of output';
    }
    return 'line ${expectedLines.length + 1}: expected end of output, '
        'received `${actualLines[expectedLines.length]}`';
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
      final attempt = await _embed(_embeddingInputs, model: model);
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

      final outcome = _evaluateEmbeddings(result, stopwatch.elapsed);
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

  _EmbeddingProbeOutcome _evaluateEmbeddings(
    EmbeddingsResult result,
    Duration elapsed,
  ) {
    final vectors = result.vectors;
    final dimensions = vectors.map((vector) => vector.length).toSet();
    final structurallyValid =
        vectors.length == _embeddingInputs.length &&
        dimensions.length == 1 &&
        dimensions.first > 0 &&
        vectors.every(
          (vector) =>
              vector.every((value) => value.isFinite) &&
              vector.any((value) => value != 0),
        );
    if (!structurallyValid) {
      return _EmbeddingProbeOutcome(
        result: LiveLlmDiagnosticProbeResult(
          id: _embeddingsProbeId,
          status: LiveLlmDiagnosticStatus.failed,
          summary: 'The embeddings response contained unusable vectors.',
          details:
              'Expected ${_embeddingInputs.length} finite, non-zero, equal-width '
              'vectors; received ${vectors.length} with dimensions '
              '${dimensions.toList()}.',
          passedChecks: 0,
          totalChecks: 2,
        ),
      );
    }

    final similarCosine = EmbeddingsMath.cosineSimilarity(
      vectors[0],
      vectors[1],
    );
    final unrelatedCosine = EmbeddingsMath.cosineSimilarity(
      vectors[0],
      vectors[2],
    );
    final metrics = LiveLlmDiagnosticEmbeddingMetrics(
      totalElapsed: elapsed,
      inputCount: _embeddingInputs.length,
      returnedVectorCount: vectors.length,
      dimension: vectors.first.length,
      model: result.model,
      similarCosine: similarCosine,
      unrelatedCosine: unrelatedCosine,
    );
    final semanticPass =
        metrics.semanticMargin >= _embeddingSemanticMarginMinimum;
    return _EmbeddingProbeOutcome(
      result: LiveLlmDiagnosticProbeResult(
        id: _embeddingsProbeId,
        status: semanticPass
            ? LiveLlmDiagnosticStatus.passed
            : LiveLlmDiagnosticStatus.warning,
        summary: semanticPass
            ? 'The embedding model returned usable, semantically separated vectors.'
            : 'The vectors were usable but did not separate the paraphrase from the control.',
        details: [
          'Model: ${result.model}',
          'Vectors: ${vectors.length} x ${vectors.first.length}',
          'Similar cosine: ${similarCosine.toStringAsFixed(6)}',
          'Unrelated cosine: ${unrelatedCosine.toStringAsFixed(6)}',
          'Semantic margin: ${metrics.semanticMargin.toStringAsFixed(6)} '
              '(required >= ${_embeddingSemanticMarginMinimum.toStringAsFixed(2)})',
        ].join('\n'),
        passedChecks: semanticPass ? 2 : 1,
        totalChecks: 2,
        metadata: {'embeddingModel': result.model},
      ),
      metrics: metrics,
    );
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

    final maximum = math.min(
      effectiveContextMaxTokens,
      _effectiveContextHardMaximumTokens,
    );
    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _effectiveContextProbeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);

    final trials = <LiveLlmDiagnosticContextTrial>[];
    final completed = <ChatCompletionResult>[];
    for (final target in _effectiveContextTargets(maximum)) {
      final stopwatch = Stopwatch()..start();
      try {
        final result = await _executeEffectiveContextTrial(target);
        completed.add(result);
        stopwatch.stop();
        final expected = _effectiveContextExpectedReply(target);
        final visibleContent = _visibleDiagnosticContent(result.content);
        final recallPassed = visibleContent == expected;
        final usageReported = result.usage.promptTokens > 0;
        final failureKind = !recallPassed
            ? _effectiveContextResponseFailureKind(target, visibleContent)
            : !usageReported
            ? 'prompt_usage_missing'
            : '';
        trials.add(
          LiveLlmDiagnosticContextTrial(
            requestedApproximateTokens: target,
            elapsed: stopwatch.elapsed,
            passed: recallPassed && usageReported,
            promptTokens: result.usage.promptTokens,
            failure: !recallPassed
                ? 'The response did not reproduce both boundary markers.'
                : !usageReported
                ? 'The endpoint omitted prompt token usage.'
                : '',
            failureKind: failureKind,
            finishReason: result.finishReason,
            responsePreview: recallPassed
                ? ''
                : _preview(result.content, maxChars: 240),
          ),
        );
      } catch (error) {
        stopwatch.stop();
        trials.add(
          LiveLlmDiagnosticContextTrial(
            requestedApproximateTokens: target,
            elapsed: stopwatch.elapsed,
            passed: false,
            failure: _preview('$error', maxChars: 300),
            failureKind: 'request_error',
          ),
        );
      }
      if (!trials.last.passed) break;
    }

    final metrics = LiveLlmDiagnosticEffectiveContextMetrics(
      configuredMaximumTokens: maximum,
      trials: List.unmodifiable(trials),
    );
    final measured = metrics.maxSuccessfulPromptTokens;
    final status = measured == 0
        ? LiveLlmDiagnosticStatus.failed
        : metrics.reachedConfiguredMaximum
        ? LiveLlmDiagnosticStatus.passed
        : LiveLlmDiagnosticStatus.warning;
    final summary = measured == 0
        ? 'The context ladder could not produce a measured successful request.'
        : metrics.reachedConfiguredMaximum
        ? 'The model preserved both boundary markers through the configured maximum.'
        : 'The context ladder found a boundary above the last successful request.';
    updated = updated
        .withProbeResult(
          LiveLlmDiagnosticProbeResult(
            id: _effectiveContextProbeId,
            status: status,
            summary: summary,
            details: [
              'Measured prompt tokens: $measured',
              'Configured approximate maximum: $maximum',
              if (effectiveContextMaxTokens > maximum)
                'Requested maximum was clamped to $_effectiveContextHardMaximumTokens tokens.',
              for (final trial in trials)
                '${trial.requestedApproximateTokens}: '
                    '${trial.passed ? 'passed' : 'failed'}'
                    '${trial.promptTokens > 0 ? ' (${trial.promptTokens} prompt tokens)' : ''}'
                    '${trial.failureKind.isNotEmpty ? ' [${trial.failureKind}]' : ''}'
                    '${trial.finishReason.isNotEmpty ? ' finish=${trial.finishReason}' : ''}'
                    '${trial.failure.isNotEmpty ? ' - ${trial.failure}' : ''}',
            ].join('\n'),
            passedChecks: trials.where((trial) => trial.passed).length,
            totalChecks: trials.length,
            metadata: {'maxSuccessfulPromptTokens': '$measured'},
            modelContent: trials
                .map((trial) => trial.responsePreview)
                .firstWhere((preview) => preview.isNotEmpty, orElse: () => ''),
            usage: _totalUsage(completed),
            elapsed: DateTime.now().difference(startedAt),
          ),
        )
        .copyWith(effectiveContextMetrics: metrics);
    onReport?.call(updated);
    return updated;
  }

  List<int> _effectiveContextTargets(int maximum) {
    if (maximum <= _effectiveContextInitialTokens) return [maximum];
    final targets = <int>[];
    var target = _effectiveContextInitialTokens;
    while (target < maximum) {
      targets.add(target);
      target *= 2;
    }
    if (targets.isEmpty || targets.last != maximum) targets.add(maximum);
    return targets;
  }

  Future<ChatCompletionResult> _executeEffectiveContextTrial(int target) {
    final messages = _effectiveContextMessages(target);
    final injected = runEffectiveContextTrial;
    if (injected != null) return injected(target, messages);
    return chatDataSource.createChatCompletion(
      messages: messages,
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: 32,
    );
  }

  List<Message> _effectiveContextMessages(int target) {
    final begin = _effectiveContextBeginMarker(target);
    final end = _effectiveContextEndMarker(target);
    final fillerCount = math.max(1, target - 128);
    final content = StringBuffer()
      ..writeln(
        'Read the DATA block. Return the exact line beginning CTX_BEGIN_ and '
        'the exact line beginning CTX_END_, separated by |, with no spaces or '
        'other text.',
      )
      ..writeln('DATA')
      ..writeln(begin)
      ..write(List.filled(fillerCount, 'pad').join(' '))
      ..writeln()
      ..writeln(end)
      ..write('END DATA');
    return _messages(user: content.toString());
  }

  String _effectiveContextExpectedReply(int target) =>
      '${_effectiveContextBeginMarker(target)}|${_effectiveContextEndMarker(target)}';

  String _effectiveContextResponseFailureKind(int target, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return 'response_empty';
    final hasBegin = trimmed.contains(_effectiveContextBeginMarker(target));
    final hasEnd = trimmed.contains(_effectiveContextEndMarker(target));
    if (hasBegin && hasEnd) return 'response_both_markers_non_exact';
    if (hasBegin) return 'response_begin_marker_only';
    if (hasEnd) return 'response_end_marker_only';
    return 'response_mismatch';
  }

  String _effectiveContextBeginMarker(int target) => 'CTX_BEGIN_$target';
  String _effectiveContextEndMarker(int target) => 'CTX_END_$target';

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
                '${outcome.label}: ${_preview(outcome.preview, maxChars: 240)}',
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
      final result = await chatDataSource.createChatCompletion(
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
      run: _runVisionAttachmentProbe,
    );
    updated = await _runSelectedProbe(
      report: updated,
      probeId: _chartReadingProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runChartReadingProbe,
    );
    updated = await _runSelectedProbe(
      report: updated,
      probeId: _visionToolObservationProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runVisionToolObservationProbe,
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
        summary: 'The endpoint lists its modalities and video is not among them.',
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

  /// Reads the image through the user-attachment path: a user message carrying
  /// `imageBase64`, which `_formatMessages` turns into an image content part.
  ///
  /// Runs a no-image control arm as well. Without it a model that ignores image
  /// content but guesses a plausible color list is indistinguishable from one
  /// that actually looked; with it, "the control scored the same" is direct
  /// evidence the image did not inform the answer.
  Future<LiveLlmDiagnosticProbeResult> _runVisionAttachmentProbe() async {
    final withImage = await _runVisionColorArm(attachImage: true);
    final control = await _runVisionColorArm(attachImage: false);

    if (withImage.rejected) {
      return LiveLlmDiagnosticProbeResult(
        id: _visionAttachmentProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The endpoint rejected a request carrying image content.',
        details:
            'Classification: $_visionClassificationRejected\n${withImage.error}',
        modelContent: _preview(withImage.content, maxChars: 400),
      );
    }

    final matched = withImage.matchedColors;
    final controlMatched = control.matchedColors;
    // The control arm outranks the score. A model that answers just as well
    // with no image did not read one, and a correct answer it could produce
    // blind is not evidence of vision -- so this is checked before the
    // all-four-colors pass.
    final ignored = controlMatched >= matched;
    final passed = !ignored && matched == _visionProbeExpectedColors.length;
    final status = passed
        ? LiveLlmDiagnosticStatus.passed
        : ignored
        ? LiveLlmDiagnosticStatus.failed
        : LiveLlmDiagnosticStatus.warning;

    return LiveLlmDiagnosticProbeResult(
      id: _visionAttachmentProbeId,
      status: status,
      summary: passed
          ? 'The model read every quadrant color from the attached image.'
          : ignored
          ? 'The no-image control arm scored the same, so the image was not used.'
          : 'The model read the image only partially.',
      details: [
        'Classification: ${passed
            ? _visionClassificationRead
            : ignored
            ? _visionClassificationIgnored
            : _visionClassificationPartial}',
        'Expected: ${_visionProbeExpectedColors.join(', ')}',
        'With image: $matched/${_visionProbeExpectedColors.length} colors in order',
        'No-image control: $controlMatched/${_visionProbeExpectedColors.length}',
      ].join('\n'),
      modelContent: [
        'with_image: ${_preview(withImage.content, maxChars: 240)}',
        'control: ${_preview(control.content, maxChars: 240)}',
      ].join('\n'),
      usage: _totalUsage([
        if (withImage.result != null) withImage.result!,
        if (control.result != null) control.result!,
      ]),
      passedChecks: matched,
      totalChecks: _visionProbeExpectedColors.length,
    );
  }

  Future<_VisionProbeArm> _runVisionColorArm({
    required bool attachImage,
  }) async {
    final now = DateTime.now();
    final messages = _messages(user: _visionProbePrompt);
    if (attachImage) {
      messages[messages.length - 1] = messages.last.copyWith(
        imageBase64: _visionProbeImageBase64,
        imageMimeType: _visionProbeImageMimeType,
      );
    } else {
      // The control arm must ask the same question with no image, so a model
      // that guesses is measured on the guess.
      messages[messages.length - 1] = messages.last.copyWith(
        content:
            '$_visionProbePrompt\n'
            '(No image is attached in this control request. Answer with your '
            'best guess and no explanation.)',
        timestamp: now,
      );
    }

    try {
      final result = await chatDataSource.createChatCompletion(
        messages: messages,
        model: _diagnosticModel,
        temperature: _diagnosticTemperature,
        maxTokens: _diagnosticMaxTokens,
      );
      return _VisionProbeArm(
        result: result,
        content: result.content.trim(),
        matchedColors: _matchedQuadrantColors(result.content),
      );
    } catch (error) {
      return _VisionProbeArm(
        rejected: attachImage,
        error: error.toString(),
        content: '',
        matchedColors: 0,
      );
    }
  }

  /// Reads quantitative detail off a chart, which is what a document with a
  /// figure in it actually asks of a model.
  ///
  /// Separate from the quadrant probe on purpose: four solid colors say the
  /// vision path is wired, not that the model can read a value off an axis.
  /// Whether a chart is legible decides whether rendering PDF pages is worth
  /// building at all, so it is measured rather than assumed.
  Future<LiveLlmDiagnosticProbeResult> _runChartReadingProbe() async {
    final withImage = await _runChartArm(attachImage: true);
    final control = await _runChartArm(attachImage: false);

    if (withImage.rejected) {
      return LiveLlmDiagnosticProbeResult(
        id: _chartReadingProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The endpoint rejected a request carrying image content.',
        details:
            'Classification: $_chartClassificationRejected\n${withImage.error}',
        modelContent: _preview(withImage.content, maxChars: 400),
      );
    }

    // An answer that never arrived is not a reading the model got wrong. A
    // reasoning model can spend the whole budget narrating the axis, and
    // scoring that as blindness would report the harness's limit as the
    // model's -- the same mistake the quadrant probe's image size once made.
    if (_visibleDiagnosticContent(withImage.content).isEmpty) {
      return LiveLlmDiagnosticProbeResult(
        id: _chartReadingProbeId,
        status: LiveLlmDiagnosticStatus.warning,
        summary: 'The model produced no answer within the token budget.',
        details:
            'Classification: $_chartClassificationNoAnswer\n'
            'Nothing was measured: the response carried reasoning and no '
            'readings. Re-run, or raise the probe budget if it persists.',
        modelContent: _preview(withImage.content, maxChars: 400),
        usage: _totalUsage([if (withImage.result != null) withImage.result!]),
        totalChecks: LiveLlmChartProbeImage.expectedAnswers.length,
      );
    }

    final expected = LiveLlmChartProbeImage.expectedAnswers;
    final matched = withImage.matchedColors;
    final controlMatched = control.matchedColors;
    // Same rule the quadrant probe follows: a model that scores as well with
    // no chart in front of it did not read one. Chart questions are guessable
    // enough that this outranks the score.
    final guessed = controlMatched >= matched;
    final passed = !guessed && matched == expected.length;
    final status = passed
        ? LiveLlmDiagnosticStatus.passed
        : guessed
        ? LiveLlmDiagnosticStatus.failed
        : LiveLlmDiagnosticStatus.warning;

    return LiveLlmDiagnosticProbeResult(
      id: _chartReadingProbeId,
      status: status,
      summary: passed
          ? 'The model read every value off the chart.'
          : guessed
          ? 'The no-image control arm scored the same, so the chart was not read.'
          : 'The model read the chart only partially.',
      details: [
        'Classification: ${passed
            ? _chartClassificationRead
            : guessed
            ? _chartClassificationGuessed
            : _chartClassificationPartial}',
        'Expected: ${expected.join(', ')}',
        'With chart: $matched/${expected.length}',
        'No-image control: $controlMatched/${expected.length}',
      ].join('\n'),
      modelContent: [
        // The visible answer, not the reasoning: a think block filled the
        // whole preview and left the actual reading invisible in the report.
        'with_chart: ${_preview(_visibleDiagnosticContent(withImage.content), maxChars: 240)}',
        'control: ${_preview(_visibleDiagnosticContent(control.content), maxChars: 240)}',
      ].join('\n'),
      usage: _totalUsage([
        if (withImage.result != null) withImage.result!,
        if (control.result != null) control.result!,
      ]),
      passedChecks: matched,
      totalChecks: expected.length,
    );
  }

  Future<_VisionProbeArm> _runChartArm({required bool attachImage}) async {
    final messages = _messages(user: _chartProbePrompt);
    messages[messages.length - 1] = attachImage
        ? messages.last.copyWith(
            imageBase64: LiveLlmChartProbeImage.base64,
            imageMimeType: LiveLlmChartProbeImage.mimeType,
          )
        : messages.last.copyWith(
            content:
                '$_chartProbePrompt\n'
                '(No image is attached in this control request. Answer with '
                'your best guess and no explanation.)',
          );

    try {
      final result = await chatDataSource.createChatCompletion(
        messages: messages,
        model: _diagnosticModel,
        temperature: _diagnosticTemperature,
        maxTokens: _chartProbeMaxTokens,
      );
      return _VisionProbeArm(
        result: result,
        content: result.content.trim(),
        matchedColors: matchedChartAnswers(result.content),
      );
    } catch (error) {
      return _VisionProbeArm(
        rejected: attachImage,
        error: error.toString(),
        content: '',
        matchedColors: 0,
      );
    }
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
  static const int chartValueTolerance = 2;

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
  static int matchedChartAnswers(String content) {
    final expected = LiveLlmChartProbeImage.expectedAnswers;
    final fields = _chartAnswerFields(ContentParser.parse(content).text.trim());
    var matched = 0;
    for (var index = 0; index < expected.length && index < fields.length; index++) {
      if (_chartFieldMatches(fields[index], expected[index])) matched += 1;
    }
    return matched;
  }

  /// The four answers out of whatever the model wrapped them in.
  ///
  /// Read from the last line that carries enough commas, so a model that
  /// prefaces the list with a sentence is still graded on the list.
  static List<String> _chartAnswerFields(String answer) {
    final expectedCount = LiveLlmChartProbeImage.expectedAnswers.length;
    final lines = const LineSplitter()
        .convert(answer)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (final line in lines.reversed) {
      final fields = line.split(',');
      if (fields.length >= expectedCount) {
        return fields.map(_normalizeChartField).toList();
      }
    }
    return answer.split(',').map(_normalizeChartField).toList();
  }

  static String _normalizeChartField(String field) =>
      field.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');

  static bool _chartFieldMatches(String actual, String expected) {
    final expectedValue = num.tryParse(expected);
    if (expectedValue == null) return actual == expected;
    final actualValue = num.tryParse(actual);
    if (actualValue == null) return false;
    return (actualValue - expectedValue).abs() <= chartValueTolerance;
  }

  /// Reads the image through the computer-use path: a tool result whose JSON
  /// carries `imageBase64`, which the datasource lifts into its own observation
  /// message. Same picture, different message shape — an endpoint can support
  /// one and not the other.
  Future<LiveLlmDiagnosticProbeResult> _runVisionToolObservationProbe() async {
    final messages = _messages(
      user: 'A screen observation tool returned an image. $_visionProbePrompt',
    );
    try {
      final result = await chatDataSource.createChatCompletionWithToolResults(
        messages: messages,
        toolResults: [
          ToolResultInfo(
            id: 'diagnostic-vision-observe-call',
            name: 'diagnostic_vision_observe',
            arguments: const {'region': 'full'},
            result: jsonEncode({
              'ok': true,
              'coordinateSpace': 'screenshot_pixels',
              'imageMimeType': _visionProbeImageMimeType,
              'imageBase64': _visionProbeImageBase64,
            }),
          ),
        ],
        model: _diagnosticModel,
        temperature: _diagnosticTemperature,
        maxTokens: _diagnosticMaxTokens,
      );
      final matched = _matchedQuadrantColors(result.content);
      final passed = matched == _visionProbeExpectedColors.length;
      return LiveLlmDiagnosticProbeResult(
        id: _visionToolObservationProbeId,
        status: passed
            ? LiveLlmDiagnosticStatus.passed
            : matched > 0
            ? LiveLlmDiagnosticStatus.warning
            : LiveLlmDiagnosticStatus.failed,
        summary: passed
            ? 'The model read the image delivered as a tool observation.'
            : 'The model did not read the tool-observation image correctly.',
        details:
            'Expected: ${_visionProbeExpectedColors.join(', ')}\n'
            'Matched in order: $matched/${_visionProbeExpectedColors.length}',
        modelContent: _preview(result.content, maxChars: 400),
        usage: _usage(result),
        passedChecks: matched,
        totalChecks: _visionProbeExpectedColors.length,
      );
    } catch (error) {
      return LiveLlmDiagnosticProbeResult(
        id: _visionToolObservationProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The endpoint rejected the tool-observation image request.',
        details: 'Classification: $_visionClassificationRejected\n$error',
      );
    }
  }

  /// Counts leading quadrant colors named in the expected order. Order matters:
  /// naming the right four colors in the wrong arrangement means the layout was
  /// not actually read.
  int _matchedQuadrantColors(String content) {
    final normalized = content.toLowerCase();
    var cursor = 0;
    var matched = 0;
    for (final color in _visionProbeExpectedColors) {
      final index = normalized.indexOf(color, cursor);
      if (index < 0) {
        break;
      }
      cursor = index + color.length;
      matched += 1;
    }
    return matched;
  }

  Future<LiveLlmDiagnosticProbeResult> _runNarrowToolCallProbe(
    _ToolCatalogContext catalog,
  ) async {
    final dateTool = _singleTool(catalog.definitions, 'get_current_datetime');
    if (dateTool == null) {
      return _toolProbeUnavailable(_narrowToolCallProbeId);
    }

    final result = await chatDataSource.createChatCompletion(
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
    final toolCalls = _toolCallsFromResult(result);
    final names = toolCalls.map((call) => call.name).toList(growable: false);
    if (toolCalls.any((call) => call.name == 'get_current_datetime')) {
      return LiveLlmDiagnosticProbeResult(
        id: _narrowToolCallProbeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model emitted the expected built-in tool call.',
        toolCalls: names,
        modelContent: _preview(result.content),
        usage: _usage(result),
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _narrowToolCallProbeId,
      status: LiveLlmDiagnosticStatus.failed,
      summary: 'The model did not emit get_current_datetime.',
      details: names.isEmpty
          ? 'No tool calls were returned.'
          : names.join(', '),
      modelContent: _preview(result.content),
      toolCalls: names,
      usage: _usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runGoalUpdateFidelityProbe() async {
    final result = await chatDataSource.createChatCompletion(
      messages: _messages(
        user:
            'The active goal is complete. Report that state by calling '
            'update_goal exactly once with completed set to true. Do not add '
            'message or blocked_reason, and do not answer in text.',
      ),
      tools: [McpGoalRoutineToolDefinitions.updateGoalTool],
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final calls = _toolCallsFromResult(result);
    final names = calls.map((call) => call.name).toList(growable: false);
    final passed =
        calls.length == 1 &&
        calls.single.name == 'update_goal' &&
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
          : calls
                .map((call) => '${call.name}: ${jsonEncode(call.arguments)}')
                .join('\n'),
      modelContent: _preview(result.content),
      toolCalls: names,
      usage: _usage(result),
    );
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
          await _runToolLoopSamplerCalibrationTrial(
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

  Future<LiveLlmDiagnosticSamplerTrial> _runToolLoopSamplerCalibrationTrial({
    required Map<String, dynamic> dateTool,
    required double temperature,
  }) async {
    try {
      final result = await chatDataSource.createChatCompletion(
        messages: _messages(
          user:
              'Call the get_current_datetime tool now. Do not answer in text '
              'before using the tool.',
        ),
        tools: [dateTool],
        model: _diagnosticModel,
        temperature: temperature,
        maxTokens: _diagnosticMaxTokens,
      );
      final toolCalls = _toolCallsFromResult(result);
      final passed = toolCalls.any(
        (call) => call.name == 'get_current_datetime',
      );
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.toolLoop.metadataName,
        temperature: temperature,
        passed: passed,
        malformedToolCallCount: passed ? 0 : 1,
        repetitionDetected: _looksRepetitive(result.content),
      );
    } catch (_) {
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.toolLoop.metadataName,
        temperature: temperature,
        passed: false,
        malformedToolCallCount: 1,
      );
    }
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
        trials.add(
          await _runRoutineSamplerCalibrationTrial(temperature: temperature),
        );
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

  Future<LiveLlmDiagnosticSamplerTrial> _runRoutineSamplerCalibrationTrial({
    required double temperature,
  }) async {
    try {
      final result = await chatDataSource.createChatCompletion(
        messages: _messages(
          user:
              'Return exactly this routine sampler JSON object and no markdown:\n'
              '{"routine":"sampler_calibration","status":"ok","marker":"$_routineSamplerMarker","nextAction":"post_summary"}',
        ),
        model: _diagnosticModel,
        temperature: temperature,
        maxTokens: _diagnosticMaxTokens,
      );
      final content = result.content.trim();
      final decoded = _tryDecodeJsonObject(content);
      final passed =
          decoded?['routine'] == 'sampler_calibration' &&
          decoded?['status'] == 'ok' &&
          decoded?['marker'] == _routineSamplerMarker &&
          decoded?['nextAction'] == 'post_summary';
      final hasUnexpectedToolCalls = _toolCallsFromResult(result).isNotEmpty;
      final hasMarker = content.contains(_routineSamplerMarker);
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.routine.metadataName,
        temperature: temperature,
        passed: passed && !hasUnexpectedToolCalls,
        jsonRepairEventCount: !passed && hasMarker ? 1 : 0,
        malformedToolCallCount: hasUnexpectedToolCalls ? 1 : 0,
        repetitionDetected: _looksRepetitive(result.content),
      );
    } catch (_) {
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.routine.metadataName,
        temperature: temperature,
        passed: false,
        jsonRepairEventCount: 1,
      );
    }
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
        trials.add(
          await _runCodingSamplerCalibrationTrial(temperature: temperature),
        );
        trials.add(
          await _runPlanSamplerCalibrationTrial(temperature: temperature),
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

  Future<LiveLlmDiagnosticSamplerTrial> _runCodingSamplerCalibrationTrial({
    required double temperature,
  }) async {
    try {
      final result = await chatDataSource.createChatCompletion(
        messages: _messages(
          user:
              'Return exactly this coding sampler JSON object and no markdown:\n'
              '{"coding":"sampler_calibration","status":"ok","marker":"$_codingSamplerMarker","edit":["<<<<<<< SEARCH","return oldValue;","=======","return newValue;",">>>>>>> REPLACE"]}',
        ),
        model: _diagnosticModel,
        temperature: temperature,
        maxTokens: _diagnosticMaxTokens,
      );
      final content = result.content.trim();
      final decoded = _tryDecodeJsonObject(content);
      final editBlockMatches = _stringListEquals(
        decoded?['edit'],
        _codingSamplerEditBlock,
      );
      final hasCodingEnvelope =
          decoded?['coding'] == 'sampler_calibration' &&
          decoded?['marker'] == _codingSamplerMarker;
      final passed =
          hasCodingEnvelope && decoded?['status'] == 'ok' && editBlockMatches;
      final hasUnexpectedToolCalls = _toolCallsFromResult(result).isNotEmpty;
      final hasMarker = content.contains(_codingSamplerMarker);
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.coding.metadataName,
        temperature: temperature,
        passed: passed && !hasUnexpectedToolCalls,
        jsonRepairEventCount: decoded == null && hasMarker ? 1 : 0,
        malformedToolCallCount: hasUnexpectedToolCalls ? 1 : 0,
        editApplyFailureCount: hasCodingEnvelope && !editBlockMatches ? 1 : 0,
        repetitionDetected: _looksRepetitive(result.content),
      );
    } catch (_) {
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.coding.metadataName,
        temperature: temperature,
        passed: false,
        jsonRepairEventCount: 1,
        editApplyFailureCount: 1,
      );
    }
  }

  Future<LiveLlmDiagnosticSamplerTrial> _runPlanSamplerCalibrationTrial({
    required double temperature,
  }) async {
    try {
      final result = await chatDataSource.createChatCompletion(
        messages: _messages(
          user:
              'Return exactly this plan sampler JSON object and no markdown:\n'
              '{"plan":"sampler_calibration","status":"ok","marker":"$_planSamplerMarker","tasks":["inspect","edit","verify"]}',
        ),
        model: _diagnosticModel,
        temperature: temperature,
        maxTokens: _diagnosticMaxTokens,
      );
      final content = result.content.trim();
      final decoded = _tryDecodeJsonObject(content);
      final passed =
          decoded?['plan'] == 'sampler_calibration' &&
          decoded?['status'] == 'ok' &&
          decoded?['marker'] == _planSamplerMarker &&
          _stringListEquals(decoded?['tasks'], _planSamplerTasks);
      final hasUnexpectedToolCalls = _toolCallsFromResult(result).isNotEmpty;
      final hasMarker = content.contains(_planSamplerMarker);
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.plan.metadataName,
        temperature: temperature,
        passed: passed && !hasUnexpectedToolCalls,
        jsonRepairEventCount: decoded == null && hasMarker ? 1 : 0,
        malformedToolCallCount: hasUnexpectedToolCalls ? 1 : 0,
        repetitionDetected: _looksRepetitive(result.content),
      );
    } catch (_) {
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.plan.metadataName,
        temperature: temperature,
        passed: false,
        jsonRepairEventCount: 1,
      );
    }
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
    final firstResult = await chatDataSource.createChatCompletion(
      messages: messages,
      tools: [dateTool],
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final firstToolCalls = _toolCallsFromResult(firstResult);
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
        modelContent: _preview(firstResult.content),
        usage: _usage(firstResult),
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
        usage: _usage(firstResult),
      );
    }

    final expected = _tryDecodeJsonObject(toolExecution.result);
    final relativeDates = expected?['relative_dates'];
    final today = relativeDates is Map
        ? relativeDates['today'] as String?
        : null;
    final timezone = expected?['timezone'] as String?;
    final followUp = await chatDataSource.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: call.id.isEmpty ? 'diagnostic-datetime-call' : call.id,
          name: call.name,
          arguments: call.arguments,
          result: toolExecution.result,
        ),
      ],
      tools: [dateTool],
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final content = followUp.content.trim();
    final decoded = _tryDecodeJsonObject(content);
    final markerOk =
        decoded?['marker'] == _toolResultMarker ||
        content.contains(_toolResultMarker);
    final todayOk = today == null || content.contains(today);
    final timezoneOk = timezone == null || content.contains(timezone);
    final passed = markerOk && todayOk && timezoneOk;
    return LiveLlmDiagnosticProbeResult(
      id: _toolResultProbeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model integrated the tool result into its final answer.'
          : 'The model answered, but did not clearly copy all tool-result fields.',
      details: [
        if (today != null) 'Expected today: $today',
        if (timezone != null) 'Expected timezone: $timezone',
      ].join('\n'),
      modelContent: _preview(content),
      toolCalls: [call.name],
      usage: _usage(followUp),
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
      final outcome = await _measureMultiRoundToolLoop(catalog);
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

  Future<_MultiRoundToolLoopProbeOutcome> _measureMultiRoundToolLoop(
    _ToolCatalogContext catalog,
  ) async {
    final service = mcpToolService;
    final searchTool = _singleTool(
      catalog.definitions,
      ToolDefinitionSearchService.toolName,
    );
    final dateTool = _singleTool(catalog.definitions, 'get_current_datetime');
    final stopwatch = Stopwatch()..start();
    final modelResults = <ChatCompletionResult>[];
    final observedToolNames = <String>[];
    var toolCallCount = 0;
    var successfulToolExecutionCount = 0;

    _MultiRoundToolLoopProbeOutcome finish({
      required LiveLlmDiagnosticStatus status,
      required String summary,
      String details = '',
      String modelContent = '',
      int passedChecks = 0,
      int totalChecks = 3,
    }) {
      stopwatch.stop();
      final usage = _totalUsage(modelResults);
      return _MultiRoundToolLoopProbeOutcome(
        result: LiveLlmDiagnosticProbeResult(
          id: _multiRoundToolLoopProbeId,
          status: status,
          summary: summary,
          details: details,
          modelContent: _preview(modelContent),
          toolCalls: List.unmodifiable(observedToolNames),
          usage: usage,
          passedChecks: passedChecks,
          totalChecks: totalChecks,
        ),
        metrics: LiveLlmDiagnosticMultiRoundToolLoopMetrics(
          totalElapsed: stopwatch.elapsed,
          modelTurnCount: modelResults.length,
          toolCallCount: toolCallCount,
          successfulToolExecutionCount: successfulToolExecutionCount,
          promptTokens: usage.promptTokens,
          completionTokens: usage.completionTokens,
          taskCompleted: status == LiveLlmDiagnosticStatus.passed,
        ),
      );
    }

    if (service == null || searchTool == null || dateTool == null) {
      return finish(
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'The sequential local tools are not available.',
      );
    }

    final messages = _messages(
      user:
          'Find the available tool that reports the current date and timezone, '
          'use it, then return JSON with marker="$_multiRoundToolLoopMarker", '
          'today copied from relative_dates.today, and timezone copied from '
          'the datetime result.',
    );
    final searchRequest = await chatDataSource.createChatCompletion(
      messages: messages,
      // The datetime tool is intentionally absent. The model must discover it
      // first, so a direct or parallel call cannot satisfy the probe.
      tools: [searchTool],
      model: _diagnosticModel,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    modelResults.add(searchRequest);
    final searchCalls = _toolCallsFromResult(searchRequest);
    toolCallCount += searchCalls.length;
    observedToolNames.addAll(searchCalls.map((call) => call.name));
    if (searchCalls.length != 1 ||
        searchCalls.single.name != ToolDefinitionSearchService.toolName) {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The first turn did not make exactly one tool_search call.',
        details: 'Returned calls: ${observedToolNames.join(", ")}',
        modelContent: searchRequest.content,
      );
    }

    final searchCall = searchCalls.single;
    final searchExecution = await service.executeTool(
      name: searchCall.name,
      arguments: searchCall.arguments,
    );
    if (!searchExecution.isSuccess) {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The local tool catalog search failed.',
        details: searchExecution.errorMessage ?? searchExecution.result,
      );
    }
    successfulToolExecutionCount += 1;
    final searchResult = ToolResultInfo(
      id: searchCall.id.isEmpty ? 'diagnostic-tool-search-call' : searchCall.id,
      name: searchCall.name,
      arguments: searchCall.arguments,
      result: searchExecution.result,
    );
    final discovered =
        ToolDefinitionSearchService.discoveredToolNamesFromResults([
          searchResult,
        ]);
    if (!discovered.contains('get_current_datetime')) {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'Tool search did not discover get_current_datetime.',
        details: _preview(searchExecution.result, maxChars: 1200),
        passedChecks: 1,
      );
    }

    final dateRequest = await chatDataSource
        .createChatCompletionWithToolResults(
          messages: messages,
          toolResults: [searchResult],
          tools: [searchTool, dateTool],
          model: _diagnosticModel,
          temperature: _diagnosticTemperature,
          maxTokens: _diagnosticMaxTokens,
        );
    modelResults.add(dateRequest);
    final dateCalls = _toolCallsFromResult(dateRequest);
    toolCallCount += dateCalls.length;
    observedToolNames.addAll(dateCalls.map((call) => call.name));
    if (dateCalls.length != 1 ||
        dateCalls.single.name != 'get_current_datetime') {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The second turn did not make exactly one datetime tool call.',
        details:
            'Returned calls: ${dateCalls.map((call) => call.name).join(", ")}',
        modelContent: dateRequest.content,
        passedChecks: 1,
      );
    }

    final dateCall = dateCalls.single;
    final dateExecution = await service.executeTool(
      name: dateCall.name,
      arguments: dateCall.arguments,
    );
    if (!dateExecution.isSuccess) {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The local datetime tool failed.',
        details: dateExecution.errorMessage ?? dateExecution.result,
        passedChecks: 1,
      );
    }
    successfulToolExecutionCount += 1;
    final dateResult = ToolResultInfo(
      id: dateCall.id.isEmpty ? 'diagnostic-datetime-call' : dateCall.id,
      name: dateCall.name,
      arguments: dateCall.arguments,
      result: dateExecution.result,
    );

    final finalRequest = await chatDataSource
        .createChatCompletionWithToolResults(
          messages: messages,
          toolResults: [dateResult],
          tools: const <Map<String, dynamic>>[],
          model: _diagnosticModel,
          temperature: _diagnosticTemperature,
          maxTokens: _diagnosticMaxTokens,
        );
    modelResults.add(finalRequest);
    final finalCalls = _toolCallsFromResult(finalRequest);
    toolCallCount += finalCalls.length;
    observedToolNames.addAll(finalCalls.map((call) => call.name));

    final expected = _tryDecodeJsonObject(dateExecution.result);
    final relativeDates = expected?['relative_dates'];
    final today = relativeDates is Map
        ? relativeDates['today'] as String?
        : null;
    final timezone = expected?['timezone'] as String?;
    final content = finalRequest.content.trim();
    final decoded = _tryDecodeJsonObject(content);
    final markerOk = decoded?['marker'] == _multiRoundToolLoopMarker;
    final todayOk = today != null && decoded?['today'] == today;
    final timezoneOk = timezone != null && decoded?['timezone'] == timezone;
    final noExtraCalls = finalCalls.isEmpty;
    final passed = markerOk && todayOk && timezoneOk && noExtraCalls;
    return finish(
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model completed two sequential tool rounds and the final answer.'
          : 'The loop reached a final answer but did not preserve its contract.',
      details: [
        'Search discovered datetime: true',
        'Marker copied: $markerOk',
        'Today copied: $todayOk',
        'Timezone copied: $timezoneOk',
        'No extra final calls: $noExtraCalls',
      ].join('\n'),
      modelContent: content,
      passedChecks:
          2 +
          [
            markerOk,
            todayOk,
            timezoneOk,
            noExtraCalls,
          ].where((ok) => ok).length,
      totalChecks: 6,
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runInitialHarnessProbe(
    _ToolCatalogContext catalog,
  ) async {
    if (!catalog.catalog.hasTools) {
      return _toolProbeUnavailable(_initialHarnessProbeId);
    }
    final result = await chatDataSource.createChatCompletion(
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
    final names = _toolCallsFromResult(
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
        modelContent: _preview(result.content),
        usage: _usage(result),
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
      modelContent: _preview(result.content),
      usage: _usage(result),
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

    final result = await chatDataSource.createChatCompletion(
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
    final calls = _toolCallsFromResult(result);
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
        modelContent: _preview(result.content),
        usage: _usage(result),
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
      details: _preview(toolResult.result, maxChars: 1200),
      toolCalls: names,
      modelContent: _preview(result.content),
      usage: _usage(result),
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
    final result = await chatDataSource.createChatCompletion(
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
    final calls = _toolCallsFromResult(result);
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
        modelContent: _preview(result.content),
        usage: _usage(result),
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
      modelContent: _preview(result.content),
      usage: _usage(result),
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

  List<ToolCallInfo> _toolCallsFromResult(ChatCompletionResult result) {
    final nativeCalls = result.toolCalls;
    if (nativeCalls != null && nativeCalls.isNotEmpty) {
      return nativeCalls;
    }
    return ContentParser.extractCompletedToolCalls(result.content)
        .map(
          (toolCall) => ToolCallInfo(
            id: toolCall.occurrenceId ?? 'text-${toolCall.name}',
            name: toolCall.name,
            arguments: toolCall.arguments,
          ),
        )
        .toList(growable: false);
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

  LiveLlmDiagnosticTokenUsage _usage(ChatCompletionResult result) {
    return LiveLlmDiagnosticTokenUsage(
      promptTokens: result.usage.promptTokens,
      completionTokens: result.usage.completionTokens,
      totalTokens: result.usage.totalTokens,
    );
  }

  LiveLlmDiagnosticTokenUsage _totalUsage(
    Iterable<ChatCompletionResult> results,
  ) {
    var promptTokens = 0;
    var completionTokens = 0;
    var totalTokens = 0;
    for (final result in results) {
      promptTokens += result.usage.promptTokens;
      completionTokens += result.usage.completionTokens;
      totalTokens += result.usage.totalTokens;
    }
    return LiveLlmDiagnosticTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  LiveLlmDiagnosticTokenUsage _sumDiagnosticUsage(
    Iterable<LiveLlmDiagnosticTokenUsage> usages,
  ) {
    var promptTokens = 0;
    var completionTokens = 0;
    var totalTokens = 0;
    for (final usage in usages) {
      promptTokens += usage.promptTokens;
      completionTokens += usage.completionTokens;
      totalTokens += usage.totalTokens;
    }
    return LiveLlmDiagnosticTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  String _formatExactPreservationDetail(
    _ExactPreservationProbeOutcome outcome,
  ) {
    return [
      '${outcome.label}: ${outcome.passed ? 'passed' : 'failed'}',
      'Expected: ${outcome.expected}',
      'Actual: ${_preview(outcome.actual, maxChars: 800)}',
    ].join('\n');
  }

  Map<String, dynamic>? _tryDecodeJsonObject(String value) {
    // Reasoning models hand back their chain of thought merged into the
    // content as a <think> block, and that prose routinely contains braces.
    // Slicing the raw text from its first brace would start inside the
    // thought and end at the answer's closing brace, so the decode fails and
    // a schema-perfect reply gets scored as a contract violation. Decode the
    // same visible text a production consumer would parse.
    final trimmed = _visibleDiagnosticContent(value);
    final candidates = <String>[trimmed];
    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace > firstBrace) {
      candidates.add(trimmed.substring(firstBrace, lastBrace + 1));
    }
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Scores the same text that production consumers display or parse while
  /// retaining the raw response separately for evidence and physical metrics.
  String _visibleDiagnosticContent(String content) {
    return ContentParser.parse(content).text.trim();
  }

  bool _stringListEquals(Object? actual, List<String> expected) {
    if (actual is! List || actual.length != expected.length) {
      return false;
    }
    for (var index = 0; index < expected.length; index += 1) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }

  String _preview(String value, {int maxChars = 2000}) {
    final trimmed = value.trim();
    if (trimmed.length <= maxChars) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxChars)}...';
  }

  bool _looksRepetitive(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length < 24) {
      return false;
    }
    final words = normalized
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.length < 8) {
      return false;
    }
    final windowCounts = <String, int>{};
    for (var index = 0; index <= words.length - 4; index += 1) {
      final window = words.sublist(index, index + 4).join(' ');
      final count = (windowCounts[window] ?? 0) + 1;
      if (count >= 3) {
        return true;
      }
      windowCounts[window] = count;
    }
    return false;
  }
}

class _StreamingProbeOutcome {
  const _StreamingProbeOutcome({required this.result, required this.metrics});

  final LiveLlmDiagnosticProbeResult result;
  final LiveLlmDiagnosticStreamingMetrics metrics;
}

class _MultiRoundToolLoopProbeOutcome {
  const _MultiRoundToolLoopProbeOutcome({
    required this.result,
    required this.metrics,
  });

  final LiveLlmDiagnosticProbeResult result;
  final LiveLlmDiagnosticMultiRoundToolLoopMetrics metrics;
}

class _VisionProbeArm {
  const _VisionProbeArm({
    required this.content,
    required this.matchedColors,
    this.result,
    this.rejected = false,
    this.error = '',
  });

  final ChatCompletionResult? result;
  final String content;
  final int matchedColors;
  final bool rejected;
  final String error;
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

class _ExactPreservationProbeOutcome {
  const _ExactPreservationProbeOutcome({
    required this.label,
    required this.expected,
    required this.actual,
    required this.rawActual,
  });

  final String label;
  final String expected;
  final String actual;
  final String rawActual;

  bool get passed => actual == expected;
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

class _EmbeddingProbeOutcome {
  const _EmbeddingProbeOutcome({required this.result, this.metrics});

  final LiveLlmDiagnosticProbeResult result;
  final LiveLlmDiagnosticEmbeddingMetrics? metrics;
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
