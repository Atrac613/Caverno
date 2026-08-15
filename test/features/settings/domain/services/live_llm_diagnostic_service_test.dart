import 'dart:convert';

import 'package:caverno/core/services/apple_foundation_models_platform_client.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/embeddings_client.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_service.dart';
import 'package:caverno/features/settings/domain/services/model_capability_profile_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs live harness probes with safe tool execution', () async {
    final dataSource = _FakeDiagnosticDataSource();
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );
    final updates = <LiveLlmDiagnosticReport>[];

    final report = await service.run(onReport: updates.add);

    expect(updates.length, greaterThan(2));
    expect(report.overallStatus, LiveLlmDiagnosticStatus.passed);
    expect(report.toolCatalog.totalToolCount, greaterThan(0));
    expect(report.toolCatalog.toolSearchEnabled, isTrue);
    expect(dataSource.toolResultFollowUpCount, 1);
    final routineTrials = report.samplerCalibrationTrials
        .where((trial) => trial.requestClass == 'routine')
        .toList(growable: false);
    final codingTrials = report.samplerCalibrationTrials
        .where((trial) => trial.requestClass == 'coding')
        .toList(growable: false);
    final planTrials = report.samplerCalibrationTrials
        .where((trial) => trial.requestClass == 'plan')
        .toList(growable: false);
    final toolLoopTrials = report.samplerCalibrationTrials
        .where((trial) => trial.requestClass == 'toolLoop')
        .toList(growable: false);
    final expectedTemperatures = [0.0, 0.2, 0.4, 0.7, 0.0, 0.2, 0.4, 0.7];
    expect(report.samplerCalibrationTrials, hasLength(32));
    expect(routineTrials, hasLength(8));
    expect(codingTrials, hasLength(8));
    expect(planTrials, hasLength(8));
    expect(toolLoopTrials, hasLength(8));
    expect(
      routineTrials.map((trial) => trial.temperature),
      expectedTemperatures,
    );
    expect(
      codingTrials.map((trial) => trial.temperature),
      expectedTemperatures,
    );
    expect(planTrials.map((trial) => trial.temperature), expectedTemperatures);
    expect(
      toolLoopTrials.map((trial) => trial.temperature),
      expectedTemperatures,
    );
    expect(routineTrials.map((trial) => trial.passed), everyElement(true));
    expect(codingTrials.map((trial) => trial.passed), everyElement(true));
    expect(planTrials.map((trial) => trial.passed), everyElement(true));
    expect(toolLoopTrials.map((trial) => trial.passed), everyElement(true));
    expect(
      report.results
          .where((result) => result.status == LiveLlmDiagnosticStatus.passed)
          .length,
      14,
    );
    expect(
      _result(report, 'edit_format_fidelity').metadata['editFormatPreference'],
      'unifiedDiff',
    );
    expect(
      _result(report, 'structured_output').metadata['structuredOutputSupport'],
      'jsonSchema',
    );
    expect(
      _result(report, 'streaming_response').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(report.streamingMetrics, isNotNull);
    expect(report.streamingMetrics!.completionTokens, 40);
    expect(report.streamingMetrics!.chunkCount, 2);
    expect(
      _result(report, 'multi_round_tool_loop').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(report.multiRoundToolLoopMetrics, isNotNull);
    expect(report.multiRoundToolLoopMetrics!.modelTurnCount, 3);
    expect(report.multiRoundToolLoopMetrics!.toolCallCount, 2);
    expect(report.multiRoundToolLoopMetrics!.successfulToolExecutionCount, 2);
    expect(report.multiRoundToolLoopMetrics!.taskCompleted, isTrue);
    expect(
      _result(report, 'vision_attachment').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'vision_attachment').details,
      contains('No-image control: 1/4'),
    );
    expect(
      _result(report, 'vision_tool_observation').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      report.results
          .where((result) => result.status == LiveLlmDiagnosticStatus.skipped)
          .length,
      4,
    );
  });

  test('skips tool probes when MCP tools are disabled', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run();

    expect(report.toolCatalog.totalToolCount, 0);
    expect(
      _result(report, 'instruction_echo').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'exact_preservation').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'narrow_tool_call').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(
      _result(report, 'remote_mcp_exposure').status,
      LiveLlmDiagnosticStatus.skipped,
    );
  });

  test('runs a bounded model capability probe set', () async {
    final dataSource = _FakeDiagnosticDataSource();
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );

    final report = await service.run(
      probeIds: LiveLlmDiagnosticService.modelCapabilityProbeIds,
    );

    // 31 pre-vision requests (including structured output, streaming, and
    // three edit formats) plus
    // the vision block: two
    // attachment arms and one tool-observation request.
    expect(dataSource.requestedModels, List.filled(34, 'test-model'));
    expect(
      report.samplerCalibrationTrials
          .map((trial) => trial.requestClass)
          .toSet(),
      {'routine', 'coding', 'plan'},
    );
    expect(
      _result(report, 'instruction_echo').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'structured_output').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'edit_format_fidelity').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'embeddings_capability').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(
      _result(report, 'exact_preservation').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(
      _result(report, 'narrow_tool_call').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(
      _result(report, 'update_goal_fidelity').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'tool_result_integration').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(
      _result(report, 'tool_search_catalog').status,
      LiveLlmDiagnosticStatus.skipped,
    );
  });

  test(
    'scores visible content when diagnostic responses include reasoning',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false),
        chatDataSource: _ReasoningWrappedDiagnosticDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run(
        probeIds: const {
          'streaming_response',
          'exact_preservation',
          'edit_format_fidelity',
        },
      );

      for (final probeId in const {
        'streaming_response',
        'exact_preservation',
        'edit_format_fidelity',
      }) {
        final result = _result(report, probeId);
        expect(result.status, LiveLlmDiagnosticStatus.passed);
        expect(
          result.modelContent,
          contains('<think>diagnostic reasoning</think>'),
        );
      }
      expect(_result(report, 'streaming_response').passedChecks, 40);
      expect(_result(report, 'exact_preservation').passedChecks, 3);
      expect(
        _result(
          report,
          'edit_format_fidelity',
        ).metadata['editFormatPreference'],
        'unifiedDiff',
      );
    },
  );

  test('selects the strongest exactly reproduced edit format', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _EditFormatDiagnosticDataSource({
        ModelEditFormatPreference.wholeFile,
        ModelEditFormatPreference.searchReplace,
      }),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'edit_format_fidelity'});
    final result = _result(report, 'edit_format_fidelity');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.passedChecks, 2);
    expect(result.totalChecks, 3);
    expect(result.metadata['editFormatPreference'], 'searchReplace');
  });

  test('reports the first exact edit format mismatch', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _EditFormatDiagnosticDataSource(
        {
          ModelEditFormatPreference.wholeFile,
          ModelEditFormatPreference.searchReplace,
        },
        unifiedDiffResponse: _editFormatUnifiedDiff.replaceFirst(
          '@@ -1,4 +1,4 @@',
          '@@ -1,3 +1,3 @@',
        ),
      ),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'edit_format_fidelity'});
    final result = _result(report, 'edit_format_fidelity');

    expect(
      result.details,
      contains(
        'unifiedDiff: failed (line 3: expected `@@ -1,4 +1,4 @@`, '
        'received `@@ -1,3 +1,3 @@`)',
      ),
    );
  });

  test('keeps edit format unknown when every exact contract fails', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _EditFormatDiagnosticDataSource(const {}),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'edit_format_fidelity'});
    final result = _result(report, 'edit_format_fidelity');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.metadata['editFormatPreference'], 'unknown');
  });

  test('prefers JSON Schema structured output when it is enforced', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'structured_output'});
    final result = _result(report, 'structured_output');

    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.passedChecks, 2);
    expect(result.metadata['structuredOutputSupport'], 'jsonSchema');
    expect(
      ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.openAiCompatible,
      ).structuredOutputSupport,
      ModelStructuredOutputSupport.jsonSchema,
    );
  });

  test('falls back to JSON object structured output', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(
        structuredOutputSupport: ModelStructuredOutputSupport.jsonObject,
      ),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'structured_output'});
    final result = _result(report, 'structured_output');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.passedChecks, 1);
    expect(result.metadata['structuredOutputSupport'], 'jsonObject');
    expect(result.details, contains('json_schema: request failed'));
  });

  test('records no structured output support when both modes fail', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(
        structuredOutputSupport: ModelStructuredOutputSupport.none,
      ),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'structured_output'});
    final result = _result(report, 'structured_output');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.passedChecks, 0);
    expect(result.metadata['structuredOutputSupport'], 'none');
  });

  test('measures usable embeddings and semantic separation', () async {
    late List<String> capturedInputs;
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false, embeddingsModel: 'qwen-embedding'),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      embedTexts: (inputs) async {
        capturedInputs = inputs;
        return const EmbeddingsResult(
          model: 'qwen-embedding',
          vectors: [
            [1, 0],
            [0.9, 0.1],
            [0, 1],
          ],
        );
      },
    );

    final report = await service.run(probeIds: {'embeddings_capability'});
    final result = _result(report, 'embeddings_capability');

    expect(capturedInputs, hasLength(3));
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(report.embeddingMetrics, isNotNull);
    expect(report.embeddingMetrics!.dimension, 2);
    expect(report.embeddingMetrics!.returnedVectorCount, 3);
    expect(report.embeddingMetrics!.semanticMargin, greaterThan(0.05));
  });

  test('warns when usable embeddings do not preserve semantic order', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false, embeddingsModel: 'weak-embedding'),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      embedTexts: (_) async => const EmbeddingsResult(
        model: 'weak-embedding',
        vectors: [
          [1, 0],
          [0, 1],
          [0.9, 0.1],
        ],
      ),
    );

    final report = await service.run(probeIds: {'embeddings_capability'});
    final result = _result(report, 'embeddings_capability');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.passedChecks, 1);
    expect(report.embeddingMetrics, isNotNull);
    expect(report.embeddingMetrics!.semanticMargin, lessThan(0));
  });

  test('rejects structurally invalid embedding vectors', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(
        mcpEnabled: false,
        embeddingsModel: 'broken-embedding',
      ),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      embedTexts: (_) async => const EmbeddingsResult(
        model: 'broken-embedding',
        vectors: [
          [1, 0],
          [1],
        ],
      ),
    );

    final report = await service.run(probeIds: {'embeddings_capability'});
    final result = _result(report, 'embeddings_capability');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.summary, contains('unusable vectors'));
    expect(report.embeddingMetrics, isNull);
  });

  test('measures effective context through an explicit token ladder', () async {
    final requested = <int>[];
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      effectiveContextMaxTokens: 8192,
      runEffectiveContextTrial: (target, messages) async {
        requested.add(target);
        expect(
          messages.last.content,
          contains('exact line beginning CTX_BEGIN_'),
        );
        expect(
          messages.last.content,
          contains('exact line beginning CTX_END_'),
        );
        expect(messages.last.content, contains('CTX_BEGIN_$target'));
        expect(messages.last.content, contains('CTX_END_$target'));
        return ChatCompletionResult(
          content: 'CTX_BEGIN_$target|CTX_END_$target',
          finishReason: 'stop',
          usage: TokenUsage(
            promptTokens: target + 50,
            completionTokens: 8,
            totalTokens: target + 58,
          ),
        );
      },
    );

    final report = await service.run(probeIds: {'effective_context'});
    final result = _result(report, 'effective_context');

    expect(requested, [2048, 4096, 8192]);
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(report.effectiveContextMetrics, isNotNull);
    expect(report.effectiveContextMetrics!.maxSuccessfulPromptTokens, 8242);
    expect(report.effectiveContextMetrics!.reachedConfiguredMaximum, isTrue);
  });

  test('scores visible effective-context markers after reasoning', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      effectiveContextMaxTokens: 2048,
      runEffectiveContextTrial: (target, _) async => ChatCompletionResult(
        content:
            '<think>diagnostic reasoning</think>'
            'CTX_BEGIN_$target|CTX_END_$target',
        finishReason: 'stop',
        usage: TokenUsage(
          promptTokens: target + 50,
          completionTokens: 16,
          totalTokens: target + 66,
        ),
      ),
    );

    final report = await service.run(probeIds: {'effective_context'});
    final result = _result(report, 'effective_context');

    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(report.effectiveContextMetrics!.trials.single.passed, isTrue);
  });

  test('stops the context ladder at the first failed boundary', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      effectiveContextMaxTokens: 16384,
      runEffectiveContextTrial: (target, _) async {
        if (target >= 8192) throw StateError('context overflow');
        return ChatCompletionResult(
          content: 'CTX_BEGIN_$target|CTX_END_$target',
          finishReason: 'stop',
          usage: TokenUsage(
            promptTokens: target + 40,
            completionTokens: 8,
            totalTokens: target + 48,
          ),
        );
      },
    );

    final report = await service.run(probeIds: {'effective_context'});
    final result = _result(report, 'effective_context');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(report.effectiveContextMetrics!.trials, hasLength(3));
    expect(report.effectiveContextMetrics!.maxSuccessfulPromptTokens, 4136);
    expect(report.effectiveContextMetrics!.firstFailedApproximateTokens, 8192);
    expect(
      report.effectiveContextMetrics!.trials.last.failureKind,
      'request_error',
    );
  });

  test('classifies effective-context marker response failures', () async {
    final cases = <(String, String)>[
      ('', 'response_empty'),
      ('CTX_BEGIN_2048', 'response_begin_marker_only'),
      ('CTX_END_2048', 'response_end_marker_only'),
      (
        'prefix CTX_BEGIN_2048|CTX_END_2048 suffix',
        'response_both_markers_non_exact',
      ),
      ('unrelated response', 'response_mismatch'),
    ];

    for (final (content, expectedKind) in cases) {
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false),
        chatDataSource: _FakeDiagnosticDataSource(),
        mcpToolService: McpToolService(),
        effectiveContextMaxTokens: 2048,
        runEffectiveContextTrial: (_, _) async => ChatCompletionResult(
          content: content,
          finishReason: 'length',
          usage: const TokenUsage(
            promptTokens: 2165,
            completionTokens: 32,
            totalTokens: 2197,
          ),
        ),
      );

      final report = await service.run(probeIds: {'effective_context'});
      final trial = report.effectiveContextMetrics!.trials.single;
      final result = _result(report, 'effective_context');

      expect(trial.failureKind, expectedKind);
      expect(trial.finishReason, 'length');
      expect(trial.responsePreview, content);
      expect(result.modelContent, content);
    }
  });

  test('classifies missing effective-context prompt usage', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      effectiveContextMaxTokens: 2048,
      runEffectiveContextTrial: (target, _) async => ChatCompletionResult(
        content: 'CTX_BEGIN_$target|CTX_END_$target',
        finishReason: 'stop',
      ),
    );

    final report = await service.run(probeIds: {'effective_context'});
    final trial = report.effectiveContextMetrics!.trials.single;

    expect(trial.failureKind, 'prompt_usage_missing');
    expect(trial.responsePreview, isEmpty);
    expect(trial.finishReason, 'stop');
  });

  test('bounds effective-context response previews', () async {
    final content = List.filled(300, 'unexpected').join(' ');
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      effectiveContextMaxTokens: 2048,
      runEffectiveContextTrial: (_, _) async => ChatCompletionResult(
        content: content,
        finishReason: 'length',
        usage: const TokenUsage(
          promptTokens: 2165,
          completionTokens: 32,
          totalTokens: 2197,
        ),
      ),
    );

    final report = await service.run(probeIds: {'effective_context'});
    final preview =
        report.effectiveContextMetrics!.trials.single.responsePreview;

    expect(preview, hasLength(243));
    expect(preview, endsWith('...'));
  });

  test('does not run the expensive context ladder without opt-in', () async {
    var invoked = false;
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
      runEffectiveContextTrial: (_, _) async {
        invoked = true;
        return ChatCompletionResult(content: '', finishReason: 'stop');
      },
    );

    final report = await service.run(probeIds: {'effective_context'});

    expect(invoked, isFalse);
    expect(
      _result(report, 'effective_context').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(report.effectiveContextMetrics, isNull);
  });

  test(
    'uses textual tool calls for Apple Foundation Models diagnostics',
    () async {
      final dataSource = _FakeDiagnosticDataSource(textToolCalls: true);
      final service = LiveLlmDiagnosticService(
        settings: _settings(
          mcpEnabled: true,
          llmProvider: LlmProvider.appleFoundationModels,
          baseUrl: 'http://127.0.0.1:1234/v1',
          model: 'qwen3.6-27b-mtp-vision',
        ),
        chatDataSource: dataSource,
        mcpToolService: McpToolService(),
      );

      final report = await service.run();

      expect(report.baseUrl, 'apple-foundation-models://local');
      expect(report.model, AppSettings.appleFoundationModelsModelId);
      expect(dataSource.requestedModels, [
        for (var i = 0; i < 13; i += 1)
          AppSettings.appleFoundationModelsModelId,
      ]);
      expect(dataSource.toolResultFollowUpCount, 0);
      expect(
        _result(report, 'instruction_echo').status,
        LiveLlmDiagnosticStatus.passed,
      );
      expect(
        _result(report, 'exact_preservation').status,
        LiveLlmDiagnosticStatus.passed,
      );
      expect(
        _result(report, 'foundation_models_language_matrix').status,
        LiveLlmDiagnosticStatus.passed,
      );
      expect(
        _result(report, 'narrow_tool_call').status,
        LiveLlmDiagnosticStatus.passed,
      );
      expect(
        _result(report, 'tool_result_integration').status,
        LiveLlmDiagnosticStatus.skipped,
      );
      expect(
        _result(report, 'subagent_recognition').status,
        LiveLlmDiagnosticStatus.skipped,
      );
    },
  );

  test('warns when an exact preservation probe value changes', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _ExactPreservationMismatchDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run();
    final result = _result(report, 'exact_preservation');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.summary, contains('changed at least one'));
    expect(result.details, contains('direct_echo_money_unit: failed'));
    expect(result.details, contains('Expected: 12 GiB, \u00a53,980'));
    expect(result.details, contains('Actual: 12 GiB, \u00a53,980.'));
    expect(result.modelContent, contains('direct_echo_money_unit:'));
    expect(
      result.modelContent,
      contains('<think>diagnostic reasoning</think>'),
    );
    expect(result.modelContent, contains('12 GiB, \u00a53,980.'));
  });

  test(
    'reports unsupported Foundation Models language errors as probe failures',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(
          mcpEnabled: true,
          llmProvider: LlmProvider.appleFoundationModels,
        ),
        chatDataSource: _UnsupportedLanguageDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run();
      final result = _result(report, 'instruction_echo');

      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, contains('rejected this prompt language'));
      expect(result.details, contains('unsupportedLanguageOrLocale'));
      expect(
        _result(report, 'foundation_models_language_matrix').status,
        LiveLlmDiagnosticStatus.failed,
      );
      expect(
        _result(report, 'narrow_tool_call').status,
        LiveLlmDiagnosticStatus.failed,
      );
      expect(
        _result(report, 'tool_result_integration').status,
        LiveLlmDiagnosticStatus.skipped,
      );
    },
  );

  test(
    'reports unavailable Foundation Models preflight as probe failures',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(
          mcpEnabled: true,
          llmProvider: LlmProvider.appleFoundationModels,
        ),
        chatDataSource: _UnavailableFoundationModelsDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run();
      final result = _result(report, 'instruction_echo');

      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, contains('not available'));
      expect(result.details, contains('preflight'));
      expect(result.details, contains('modelNotReady'));
      expect(
        _result(report, 'foundation_models_language_matrix').status,
        LiveLlmDiagnosticStatus.failed,
      );
      expect(
        _result(report, 'narrow_tool_call').status,
        LiveLlmDiagnosticStatus.failed,
      );
      expect(
        _result(report, 'tool_result_integration').status,
        LiveLlmDiagnosticStatus.skipped,
      );
    },
  );

  test('vision probe sends the image on both production shapes', () async {
    final dataSource = _VisionRecordingDataSource();
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );

    await service.run(
      probeIds: const {'vision_attachment', 'vision_tool_observation'},
    );

    // The attachment arm carries the image on the user message; the control
    // arm asks the same question without one.
    expect(dataSource.attachmentArmImages, [isNotNull, isNull]);
    expect(dataSource.attachmentMimeTypes.first, 'image/png');
    // The observation arm delivers it inside the tool result, the way
    // computer-use returns a screenshot.
    expect(dataSource.toolResultImageCount, 1);
  });

  test(
    'vision probe treats a matching control arm as an ignored image',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false),
        chatDataSource: _VisionGuessingDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run(probeIds: const {'vision_attachment'});
      final result = _result(report, 'vision_attachment');

      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.details, contains('model_ignored_the_image'));
      expect(
        ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
          report: report,
          provider: LlmProvider.openAiCompatible,
        ).visionSupport,
        ModelVisionSupport.ignored,
      );
    },
  );

  test('vision probe classifies a rejected image request', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _VisionRejectingDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'vision_attachment'});
    final result = _result(report, 'vision_attachment');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.details, contains('endpoint_rejected'));
    expect(
      ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.openAiCompatible,
      ).visionSupport,
      ModelVisionSupport.rejected,
    );
  });

  test('vision probes are not applicable to Apple Foundation Models', () async {
    final dataSource = _VisionRecordingDataSource();
    final service = LiveLlmDiagnosticService(
      settings: _settings(
        mcpEnabled: false,
        llmProvider: LlmProvider.appleFoundationModels,
      ),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );

    final report = await service.run(
      probeIds: const {'vision_attachment', 'vision_tool_observation'},
    );

    expect(
      _result(report, 'vision_attachment').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(
      _result(report, 'vision_tool_observation').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    // The provider drops images at the datasource, so asking would measure
    // Caverno's own bridge rather than the model.
    expect(dataSource.attachmentArmImages, isEmpty);
    expect(
      ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.appleFoundationModels,
      ).visionSupport,
      ModelVisionSupport.unknown,
    );
  });

  test('multi-round probe rejects extra calls on the first turn', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: _ExtraFirstRoundCallDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'multi_round_tool_loop'});
    final result = _result(report, 'multi_round_tool_loop');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.summary, contains('exactly one tool_search'));
    expect(result.toolCalls, ['tool_search', 'get_current_datetime']);
    expect(report.multiRoundToolLoopMetrics, isNotNull);
    expect(report.multiRoundToolLoopMetrics!.modelTurnCount, 1);
    expect(report.multiRoundToolLoopMetrics!.toolCallCount, 2);
    expect(report.multiRoundToolLoopMetrics!.successfulToolExecutionCount, 0);
    expect(report.multiRoundToolLoopMetrics!.taskCompleted, isFalse);
  });

  test('multi-round probe distinguishes a skipped search', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: _SkippedSearchDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'multi_round_tool_loop'});
    final result = _result(report, 'multi_round_tool_loop');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.summary, contains('exactly one tool_search'));
    expect(result.toolCalls, isEmpty);
    expect(report.multiRoundToolLoopMetrics!.modelTurnCount, 1);
    expect(report.multiRoundToolLoopMetrics!.toolCallCount, 0);
    expect(report.multiRoundToolLoopMetrics!.successfulToolExecutionCount, 0);
  });

  test('multi-round probe distinguishes a skipped datetime call', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: _SkippedDatetimeDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'multi_round_tool_loop'});
    final result = _result(report, 'multi_round_tool_loop');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.summary, contains('exactly one datetime tool call'));
    expect(result.toolCalls, ['tool_search']);
    expect(report.multiRoundToolLoopMetrics!.modelTurnCount, 2);
    expect(report.multiRoundToolLoopMetrics!.toolCallCount, 1);
    expect(report.multiRoundToolLoopMetrics!.successfulToolExecutionCount, 1);
  });

  test('multi-round probe warns when the final marker is missing', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: _MissingFinalMarkerDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'multi_round_tool_loop'});
    final result = _result(report, 'multi_round_tool_loop');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.summary, contains('did not preserve its contract'));
    expect(result.details, contains('Marker copied: false'));
    expect(report.multiRoundToolLoopMetrics!.modelTurnCount, 3);
    expect(report.multiRoundToolLoopMetrics!.toolCallCount, 2);
    expect(report.multiRoundToolLoopMetrics!.successfulToolExecutionCount, 2);
    expect(report.multiRoundToolLoopMetrics!.taskCompleted, isFalse);
  });
}

AppSettings _settings({
  required bool mcpEnabled,
  LlmProvider llmProvider = LlmProvider.openAiCompatible,
  String baseUrl = 'http://localhost:1234/v1',
  String model = 'test-model',
  String embeddingsModel = '',
}) {
  return AppSettings.defaults().copyWith(
    llmProvider: llmProvider,
    baseUrl: baseUrl,
    model: model,
    embeddingsModel: embeddingsModel,
    mcpEnabled: mcpEnabled,
    mcpUrl: '',
    mcpUrls: const <String>[],
    mcpServers: const <McpServerConfig>[],
  );
}

LiveLlmDiagnosticProbeResult _result(
  LiveLlmDiagnosticReport report,
  String id,
) {
  return report.results.singleWhere((result) => result.id == id);
}

class _FakeDiagnosticDataSource
    implements ChatDataSource, StructuredOutputChatDataSource {
  _FakeDiagnosticDataSource({
    this.textToolCalls = false,
    this.structuredOutputSupport = ModelStructuredOutputSupport.jsonSchema,
  });

  final bool textToolCalls;
  final ModelStructuredOutputSupport structuredOutputSupport;
  int toolResultFollowUpCount = 0;
  final List<String?> requestedModels = [];

  @override
  Future<ChatCompletionResult> createStructuredChatCompletion({
    required List<Message> messages,
    required StructuredOutputRequest responseFormat,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestedModels.add(model);
    if (responseFormat.format == StructuredOutputFormat.jsonSchema) {
      if (structuredOutputSupport != ModelStructuredOutputSupport.jsonSchema) {
        throw StateError('json_schema unsupported');
      }
      return ChatCompletionResult(
        content: '{"marker":"CAVERNO_SCHEMA_LOCKED_47","count":47}',
        finishReason: 'stop',
      );
    }
    if (structuredOutputSupport == ModelStructuredOutputSupport.none) {
      throw StateError('json_object unsupported');
    }
    return ChatCompletionResult(
      content: '{"marker":"CAVERNO_JSON_OBJECT_OK","count":47}',
      finishReason: 'stop',
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestedModels.add(model);
    final user = messages.last.content;
    if (user.contains('product_label')) {
      return ChatCompletionResult(
        content: 'ZX-900_\u03b1 2026-06-12',
        finishReason: 'stop',
      );
    }
    if (user.contains('example.test/downloads')) {
      return ChatCompletionResult(
        content:
            'https://example.test/downloads/build_2026-06-10.tar.zst?sha=abc123_def',
        finishReason: 'stop',
      );
    }
    if (user.contains('12 GiB')) {
      return ChatCompletionResult(
        content: '12 GiB, \u00a53,980',
        finishReason: 'stop',
      );
    }
    if (user.contains('Return exactly this JSON object')) {
      return ChatCompletionResult(
        content:
            '{"probe":"instruction_echo","status":"ok","marker":"CAVERNO_LIVE_DIAGNOSTIC"}',
        finishReason: 'stop',
      );
    }
    if (user.contains('complete updated file contents')) {
      return ChatCompletionResult(
        content: _editFormatWholeFile,
        finishReason: 'stop',
      );
    }
    if (user.contains('one exact SEARCH/REPLACE block')) {
      return ChatCompletionResult(
        content: _editFormatSearchReplace,
        finishReason: 'stop',
      );
    }
    if (user.contains('one syntactically valid unified diff')) {
      return ChatCompletionResult(
        content: _editFormatUnifiedDiff,
        finishReason: 'stop',
      );
    }
    if (user.contains('routine sampler JSON object')) {
      return ChatCompletionResult(
        content:
            '{"routine":"sampler_calibration","status":"ok","marker":"CAVERNO_ROUTINE_SAMPLER_OK","nextAction":"post_summary"}',
        finishReason: 'stop',
      );
    }
    if (user.contains('coding sampler JSON object')) {
      return ChatCompletionResult(
        content:
            '{"coding":"sampler_calibration","status":"ok","marker":"CAVERNO_CODING_SAMPLER_OK","edit":["<<<<<<< SEARCH","return oldValue;","=======","return newValue;",">>>>>>> REPLACE"]}',
        finishReason: 'stop',
      );
    }
    if (user.contains('plan sampler JSON object')) {
      return ChatCompletionResult(
        content:
            '{"plan":"sampler_calibration","status":"ok","marker":"CAVERNO_PLAN_SAMPLER_OK","tasks":["inspect","edit","verify"]}',
        finishReason: 'stop',
      );
    }
    if (user.contains('CAVERNO_FM_LANG_EN')) {
      return ChatCompletionResult(
        content: 'CAVERNO_FM_LANG_EN',
        finishReason: 'stop',
      );
    }
    if (user.contains('CAVERNO_FM_LANG_JA')) {
      return ChatCompletionResult(
        content: 'CAVERNO_FM_LANG_JA',
        finishReason: 'stop',
      );
    }
    if (user.contains('CAVERNO_FM_LANG_TOOL')) {
      return ChatCompletionResult(
        content: 'CAVERNO_FM_LANG_TOOL',
        finishReason: 'stop',
      );
    }
    if (user.contains('four equal quadrants')) {
      // Stands in for a vision-capable model: right only when the image is
      // actually attached, so the control arm measures a guess.
      return ChatCompletionResult(
        content: messages.last.imageBase64 == null
            ? 'red, green, blue, yellow'
            : 'yellow, blue, red, green',
        finishReason: 'stop',
      );
    }
    if (user.contains('tool catalog search tool')) {
      return _toolCall('tool_search', {
        'query': 'delegate focused sub-task child agent',
        'max_results': 8,
      });
    }
    if (user.contains('Find the available tool that reports')) {
      return _toolCall('tool_search', {
        'query': 'get_current_datetime current date timezone',
        'max_results': 8,
      });
    }
    if (user.contains('Delegate a sub-task to a subagent')) {
      return _toolCall('spawn_subagent', {
        'description': 'Diagnostic subagent marker summary',
        'prompt': 'Summarize the marker CAVERNO_SUBAGENT_DIAGNOSTIC and stop.',
        'background': true,
      });
    }
    if (user.contains('update_goal exactly once')) {
      return _toolCall('update_goal', const {'completed': true});
    }
    if (user.contains('get_current_datetime')) {
      return _toolCall('get_current_datetime', const <String, dynamic>{});
    }
    return ChatCompletionResult(
      content: 'Unhandled fake prompt',
      finishReason: 'stop',
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    return createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: toolCallId,
          name: toolName,
          arguments: jsonDecode(toolArguments) as Map<String, dynamic>,
          result: toolResult,
        ),
      ],
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestedModels.add(model);
    final toolResult = toolResults.single;
    final payload = jsonDecode(toolResult.result) as Map<String, dynamic>;
    if (payload['imageBase64'] is String) {
      return ChatCompletionResult(
        content: 'yellow, blue, red, green',
        finishReason: 'stop',
      );
    }
    if (toolResult.name == 'tool_search') {
      return _toolCall('get_current_datetime', const <String, dynamic>{});
    }
    final relativeDates = payload['relative_dates'] as Map<String, dynamic>;
    if (messages.last.content.contains('CAVERNO_MULTI_ROUND_LOOP_OK')) {
      return ChatCompletionResult(
        content: jsonEncode({
          'marker': 'CAVERNO_MULTI_ROUND_LOOP_OK',
          'today': relativeDates['today'],
          'timezone': payload['timezone'],
        }),
        finishReason: 'stop',
        usage: const TokenUsage(
          promptTokens: 10,
          completionTokens: 5,
          totalTokens: 15,
        ),
      );
    }
    toolResultFollowUpCount += 1;
    return ChatCompletionResult(
      content: jsonEncode({
        'probe': 'datetime_tool_result',
        'marker': 'CAVERNO_TOOL_RESULT_OK',
        'today': relativeDates['today'],
        'timezone': payload['timezone'],
      }),
      finishReason: 'stop',
    );
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requestedModels.add(model);
    final lines = [for (var value = 1; value <= 40; value += 1) '$value\n'];
    return StreamedChatCompletion.fromStream(
      Stream.fromIterable([lines.take(20).join(), lines.skip(20).join()]),
      finishReason: 'stop',
      usage: const TokenUsage(
        promptTokens: 12,
        completionTokens: 40,
        totalTokens: 52,
      ),
    );
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  ChatCompletionResult _toolCall(String name, Map<String, dynamic> arguments) {
    if (textToolCalls) {
      return ChatCompletionResult(
        content:
            '<tool_use>${jsonEncode({'name': name, 'arguments': arguments})}</tool_use>',
        finishReason: 'stop',
      );
    }
    return ChatCompletionResult(
      content: '',
      toolCalls: [
        ToolCallInfo(id: 'call-$name', name: name, arguments: arguments),
      ],
      finishReason: 'tool_calls',
    );
  }
}

class _ReasoningWrappedDiagnosticDataSource extends _FakeDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final result = await super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    return ChatCompletionResult(
      content: '<think>diagnostic reasoning</think>${result.content}',
      toolCalls: result.toolCalls,
      finishReason: result.finishReason,
      usage: result.usage,
    );
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requestedModels.add(model);
    final lines = [for (var value = 1; value <= 40; value += 1) '$value\n'];
    return StreamedChatCompletion.fromStream(
      Stream.fromIterable([
        '<think>diagnostic reasoning</think>${lines.take(20).join()}',
        lines.skip(20).join(),
      ]),
      finishReason: 'stop',
      usage: const TokenUsage(
        promptTokens: 12,
        completionTokens: 48,
        totalTokens: 60,
      ),
    );
  }
}

const _editFormatWholeFile = '''String buildLabel(String name) {
  final trimmed = name.trim();
  return 'Welcome, \$trimmed!';
}''';
final _editFormatSearchReplace = [
  '<<<<<<< SEARCH',
  "  return 'Hello, \$trimmed!';",
  '=======',
  "  return 'Welcome, \$trimmed!';",
  '>>>>>>> REPLACE',
].join('\n');
const _editFormatUnifiedDiff = '''--- a/lib/greeting.dart
+++ b/lib/greeting.dart
@@ -1,4 +1,4 @@
 String buildLabel(String name) {
   final trimmed = name.trim();
-  return 'Hello, \$trimmed!';
+  return 'Welcome, \$trimmed!';
 }''';

class _EditFormatDiagnosticDataSource extends _FakeDiagnosticDataSource {
  _EditFormatDiagnosticDataSource(this.supported, {this.unifiedDiffResponse});

  final Set<ModelEditFormatPreference> supported;
  final String? unifiedDiffResponse;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final prompt = messages.last.content;
    if (prompt.contains('complete updated file contents')) {
      return ChatCompletionResult(
        content: supported.contains(ModelEditFormatPreference.wholeFile)
            ? _editFormatWholeFile
            : 'I changed the greeting.',
        finishReason: 'stop',
      );
    }
    if (prompt.contains('one exact SEARCH/REPLACE block')) {
      return ChatCompletionResult(
        content: supported.contains(ModelEditFormatPreference.searchReplace)
            ? _editFormatSearchReplace
            : 'I changed the greeting.',
        finishReason: 'stop',
      );
    }
    if (prompt.contains('one syntactically valid unified diff')) {
      return ChatCompletionResult(
        content:
            unifiedDiffResponse ??
            (supported.contains(ModelEditFormatPreference.unifiedDiff)
                ? _editFormatUnifiedDiff
                : 'I changed the greeting.'),
        finishReason: 'stop',
      );
    }
    return super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _ExtraFirstRoundCallDataSource extends _FakeDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (messages.last.content.contains(
      'Find the available tool that reports',
    )) {
      return ChatCompletionResult(
        content: '',
        toolCalls: [
          ToolCallInfo(
            id: 'call-search',
            name: 'tool_search',
            arguments: {'query': 'get_current_datetime'},
          ),
          ToolCallInfo(
            id: 'call-date',
            name: 'get_current_datetime',
            arguments: <String, dynamic>{},
          ),
        ],
        finishReason: 'tool_calls',
      );
    }
    return super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _SkippedSearchDataSource extends _FakeDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (messages.last.content.contains(
      'Find the available tool that reports',
    )) {
      return ChatCompletionResult(
        content: '{"marker":"CAVERNO_MULTI_ROUND_LOOP_OK"}',
        finishReason: 'stop',
      );
    }
    return super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _SkippedDatetimeDataSource extends _FakeDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (toolResults.single.name == 'tool_search') {
      return ChatCompletionResult(
        content: '{"marker":"CAVERNO_MULTI_ROUND_LOOP_OK"}',
        finishReason: 'stop',
      );
    }
    return super.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _MissingFinalMarkerDataSource extends _FakeDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (toolResults.single.name == 'get_current_datetime' &&
        (tools == null || tools.isEmpty)) {
      final payload =
          jsonDecode(toolResults.single.result) as Map<String, dynamic>;
      final relativeDates = payload['relative_dates'] as Map<String, dynamic>;
      return ChatCompletionResult(
        content: jsonEncode({
          'today': relativeDates['today'],
          'timezone': payload['timezone'],
        }),
        finishReason: 'stop',
      );
    }
    return super.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

/// Records how the image reached the model, so the probe is verified against
/// the real message shapes rather than against its own grading.
class _VisionRecordingDataSource extends _FakeDiagnosticDataSource {
  final List<String?> attachmentArmImages = [];
  final List<String?> attachmentMimeTypes = [];
  int toolResultImageCount = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (messages.last.content.contains('four equal quadrants')) {
      attachmentArmImages.add(messages.last.imageBase64);
      attachmentMimeTypes.add(messages.last.imageMimeType);
    }
    return super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final payload =
        jsonDecode(toolResults.single.result) as Map<String, dynamic>;
    if (payload['imageBase64'] is String) {
      toolResultImageCount += 1;
    }
    return super.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

/// Answers the quadrant question identically with and without the image: the
/// shape of a model that never looked but guessed well.
class _VisionGuessingDataSource extends _FakeDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (messages.last.content.contains('four equal quadrants')) {
      requestedModels.add(model);
      return ChatCompletionResult(
        content: 'yellow, blue, red, green',
        finishReason: 'stop',
      );
    }
    return super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

/// Refuses any request carrying image content, the way a text-only endpoint
/// answers a multimodal content part.
class _VisionRejectingDataSource extends _FakeDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (messages.last.imageBase64 != null) {
      throw Exception(
        'HTTP 400: this model does not support image content parts',
      );
    }
    return super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _ExactPreservationMismatchDataSource extends _FakeDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final user = messages.last.content;
    if (!user.contains('product_label') &&
        !user.contains('example.test/downloads') &&
        user.contains('12 GiB')) {
      requestedModels.add(model);
      return ChatCompletionResult(
        content:
            '<think>diagnostic reasoning</think>'
            '12 GiB, \u00a53,980.',
        finishReason: 'stop',
      );
    }
    return super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _UnsupportedLanguageDataSource implements ChatDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    throw Exception(
      'unsupportedLanguageOrLocale(GenerationError.Context(debugDescription: "Unsupported language."))',
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _UnavailableFoundationModelsDataSource
    extends _UnsupportedLanguageDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    throw AppleFoundationModelsException.unavailable(
      const AppleFoundationModelsAvailability(
        isAvailable: false,
        status: 'unavailable',
        reason: 'modelNotReady',
      ),
    );
  }
}
