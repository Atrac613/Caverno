import 'dart:convert';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../../core/constants/system_prompt_constants.dart';
import '../../../../core/services/apple_foundation_models_platform_client.dart';
import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/data/datasources/mcp_tool_service.dart';
import '../../../chat/data/datasources/mcp_goal_routine_tool_definitions.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/services/tool_definition_search_service.dart';
import '../../../chat/domain/services/tool_result_prompt_builder.dart';
import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';
import 'llm_provider_capabilities.dart';
import 'llm_sampler_preset_profile.dart';

typedef LiveLlmDiagnosticReportCallback =
    void Function(LiveLlmDiagnosticReport report);

class LiveLlmDiagnosticService {
  LiveLlmDiagnosticService({
    required this.settings,
    required this.chatDataSource,
    required this.mcpToolService,
  });

  final AppSettings settings;
  final ChatDataSource chatDataSource;
  final McpToolService? mcpToolService;

  static const probeDefinitions = <LiveLlmDiagnosticProbeDefinition>[
    LiveLlmDiagnosticProbeDefinition(
      id: _instructionProbeId,
      titleKey: 'settings.live_llm_diag_probe_instruction_title',
      descriptionKey: 'settings.live_llm_diag_probe_instruction_desc',
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
  static const _streamingProbeId = 'streaming_response';
  static const _exactPreservationProbeId = 'exact_preservation';
  static const _foundationModelsLanguageMatrixProbeId =
      'foundation_models_language_matrix';
  static const _visionAttachmentProbeId = 'vision_attachment';
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
    _streamingProbeId,
    _visionAttachmentProbeId,
    _visionToolObservationProbeId,
    _narrowToolCallProbeId,
    _goalUpdateFidelityProbeId,
    _toolResultProbeId,
    _initialHarnessProbeId,
  };

  /// A 64x64 PNG of four solid quadrants in a non-obvious reading order:
  /// yellow, blue, red, green. The shuffled layout prevents a model from
  /// passing by guessing the conventional red, green, blue, yellow sequence.
  /// It is embedded so the probe stays byte-identical on every platform and in
  /// tests. Solid colors also survive vision-tower downscaling.
  static const _visionProbeImageBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAWElEQVR42u3RgQkAIAwDwQ'
      'a6/8p1iqLC/QLhSM/UasnuQNfnAQAAAAAAAAAAAAAAAAAAAAAAAAAAANwAZHlh4gEAAAAA'
      'AAAAAAAAAAAAAAAAAAAAAACAtzq7gAUBzMvYfAAAAABJRU5ErkJggg==';
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

  static const _marker = 'CAVERNO_LIVE_DIAGNOSTIC';
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

  /// Vision outcome labels. Emitted into probe details so the profile builder
  /// and a human reading the report classify a miss the same way.
  static const _visionClassificationRejected = 'endpoint_rejected';
  static const _visionClassificationIgnored = 'model_ignored_the_image';
  static const _visionClassificationPartial = 'partially_read';
  static const _visionClassificationRead = 'read_correctly';
  static const _diagnosticTemperature = 0.0;
  static const _diagnosticMaxTokens = 512;
  static const _samplerCalibrationTemperatures = <double>[0.0, 0.2, 0.4, 0.7];
  static const _samplerCalibrationRepeatCount = 2;

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
    final matched = _matchedIntegerSequence(content);
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
        actual: directResult.content.trim(),
      ),
      _ExactPreservationProbeOutcome(
        label: 'tool_result_raw_value',
        expected: _exactToolResultValue,
        actual: toolResult.content.trim(),
      ),
      _ExactPreservationProbeOutcome(
        label: 'url_preservation',
        expected: _exactUrlValue,
        actual: urlResult.content.trim(),
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
                '${outcome.label}: ${_preview(outcome.actual, maxChars: 360)}',
          )
          .join('\n'),
      usage: _totalUsage([directResult, toolResult, urlResult]),
      passedChecks: outcomes.length - failed.length,
      totalChecks: outcomes.length,
    );
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
      probeId: _visionToolObservationProbeId,
      selectedProbeIds: selectedProbeIds,
      onReport: onReport,
      run: _runVisionToolObservationProbe,
    );
    return updated;
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

    final trials = <LiveLlmDiagnosticSamplerTrial>[];
    for (var repeat = 0; repeat < _samplerCalibrationRepeatCount; repeat += 1) {
      for (final temperature in _samplerCalibrationTemperatures) {
        trials.add(
          await _runRoutineSamplerCalibrationTrial(temperature: temperature),
        );
      }
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
    final trimmed = value.trim();
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
  });

  final String label;
  final String expected;
  final String actual;

  bool get passed => actual == expected;
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
