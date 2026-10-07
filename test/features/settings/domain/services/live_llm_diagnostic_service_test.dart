import 'dart:convert';
import 'dart:typed_data';

import 'package:caverno/core/services/apple_foundation_models_platform_client.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/embeddings_client.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_chart_probe_image.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_scoring.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_service.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_tool_depth_ladder.dart';
import 'package:caverno/features/settings/domain/services/live_llm_tool_depth_staircase.dart';
import 'package:caverno/features/settings/domain/services/model_capability_profile_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/live_llm_tool_recovery_fake.dart';

void main() {
  test('tool-result binding preserves requests and publication', () async {
    final source = _ToolResultRecordingDataSource();
    final statuses = <LiveLlmDiagnosticStatus>[];
    final report =
        await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: true, model: 'tool-result-model'),
          chatDataSource: source,
          mcpToolService: McpToolService(),
        ).run(
          probeIds: const {'tool_result_integration'},
          onReport: (report) {
            final status = _result(report, 'tool_result_integration').status;
            if (statuses.isEmpty || statuses.last != status) {
              statuses.add(status);
            }
          },
        );
    expect(source.requests, ['initial', 'follow-up']);
    expect(statuses, [
      LiveLlmDiagnosticStatus.pending,
      LiveLlmDiagnosticStatus.running,
      LiveLlmDiagnosticStatus.passed,
    ]);
    expect(_result(report, 'tool_result_integration').elapsed, isNotNull);
  });

  test('tool-result unavailable catalog skips without requests', () async {
    final source = _ToolResultRecordingDataSource();
    final report = await LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false, model: 'tool-result-model'),
      chatDataSource: source,
      mcpToolService: McpToolService(),
    ).run(probeIds: const {'tool_result_integration'});
    expect(source.requests, isEmpty);
    expect(
      _result(report, 'tool_result_integration').status,
      LiveLlmDiagnosticStatus.skipped,
    );
  });

  for (final stage in ['initial', 'follow-up']) {
    test(
      'tool-result $stage errors reach the failed report boundary',
      () async {
        final source = _ToolResultRecordingDataSource(failureStage: stage);
        final report = await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: true, model: 'tool-result-model'),
          chatDataSource: source,
          mcpToolService: McpToolService(),
        ).run(probeIds: const {'tool_result_integration'});
        final result = _result(report, 'tool_result_integration');
        expect(result.status, LiveLlmDiagnosticStatus.failed);
        expect(result.details, contains('tool-result $stage'));
        expect(result.usage.totalTokens, 0);
      },
    );
  }

  test('edit format binds requests, thinking and publication', () async {
    final source = _EditRecordingDataSource();
    final statuses = <LiveLlmDiagnosticStatus>[];
    final report =
        await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: false, model: 'edit-model'),
          chatDataSource: source,
          mcpToolService: null,
        ).run(
          probeIds: const {'edit_format_fidelity'},
          onReport: (report) {
            final status = _result(report, 'edit_format_fidelity').status;
            if (statuses.isEmpty || statuses.last != status) {
              statuses.add(status);
            }
          },
        );
    expect(source.calls, 3);
    expect(statuses, [
      LiveLlmDiagnosticStatus.pending,
      LiveLlmDiagnosticStatus.running,
      LiveLlmDiagnosticStatus.passed,
    ]);
    expect(report.thinkingMetrics!.responseCount, 3);
    expect(report.thinkingMetrics!.reasoningResponseCount, 3);
    expect(_result(report, 'edit_format_fidelity').usage.totalTokens, 39);
  });

  test('edit format skips an unselected probe without requests', () async {
    final source = _EditRecordingDataSource();
    final report = await LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false, model: 'edit-model'),
      chatDataSource: source,
      mcpToolService: null,
    ).run(probeIds: const <String>{});
    expect(source.calls, 0);
    expect(
      _result(report, 'edit_format_fidelity').status,
      LiveLlmDiagnosticStatus.skipped,
    );
  });

  for (final arm in [1, 2, 3]) {
    test(
      'edit format converts arm $arm request failures to failed reports',
      () async {
        final source = _EditRecordingDataSource(failingArm: arm);
        final report = await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: false, model: 'edit-model'),
          chatDataSource: source,
          mcpToolService: null,
        ).run(probeIds: const {'edit_format_fidelity'});
        expect(source.calls, arm);
        final result = _result(report, 'edit_format_fidelity');
        expect(result.status, LiveLlmDiagnosticStatus.failed);
        expect(result.details, contains('edit arm $arm'));
        expect(result.usage.totalTokens, 0);
      },
    );
  }

  test('exact preservation binds requests, thinking and publication', () async {
    final source = _ExactRecordingDataSource();
    final statuses = <LiveLlmDiagnosticStatus>[];
    final report =
        await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: false, model: 'exact-model'),
          chatDataSource: source,
          mcpToolService: null,
        ).run(
          probeIds: const {'exact_preservation'},
          onReport: (report) {
            final status = _result(report, 'exact_preservation').status;
            if (statuses.isEmpty || statuses.last != status) {
              statuses.add(status);
            }
          },
        );
    expect(source.calls, 3);
    expect(statuses, [
      LiveLlmDiagnosticStatus.pending,
      LiveLlmDiagnosticStatus.running,
      LiveLlmDiagnosticStatus.passed,
    ]);
    expect(report.thinkingMetrics!.responseCount, 3);
    expect(report.thinkingMetrics!.reasoningResponseCount, 3);
    expect(_result(report, 'exact_preservation').usage.totalTokens, 39);
  });

  test('exact preservation skips an unselected probe', () async {
    final source = _ExactRecordingDataSource();
    final report = await LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false, model: 'exact-model'),
      chatDataSource: source,
      mcpToolService: null,
    ).run(probeIds: const <String>{});
    expect(source.calls, 0);
    expect(
      _result(report, 'exact_preservation').status,
      LiveLlmDiagnosticStatus.skipped,
    );
  });

  for (final arm in [1, 2, 3]) {
    test(
      'exact preservation converts arm $arm request errors to a failed report',
      () async {
        final source = _ExactRecordingDataSource(failingArm: arm);
        final report = await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: false, model: 'exact-model'),
          chatDataSource: source,
          mcpToolService: null,
        ).run(probeIds: const {'exact_preservation'});
        final result = _result(report, 'exact_preservation');
        expect(source.calls, arm);
        expect(result.status, LiveLlmDiagnosticStatus.failed);
        expect(result.details, contains('exact arm $arm'));
        expect(result.usage.totalTokens, 0);
      },
    );
  }

  test('streaming binds requests, thinking and publication', () async {
    final source = _StreamingRecordingDataSource();
    final statuses = <LiveLlmDiagnosticStatus>[];
    final report =
        await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: false, model: 'stream-model'),
          chatDataSource: source,
          mcpToolService: null,
        ).run(
          probeIds: const {'streaming_response'},
          onReport: (report) {
            final status = _result(report, 'streaming_response').status;
            if (statuses.isEmpty || statuses.last != status) {
              statuses.add(status);
            }
          },
        );
    expect(source.calls, 1);
    expect(statuses, [
      LiveLlmDiagnosticStatus.pending,
      LiveLlmDiagnosticStatus.running,
      LiveLlmDiagnosticStatus.passed,
    ]);
    expect(report.thinkingMetrics!.responseCount, 1);
    expect(report.thinkingMetrics!.reasoningResponseCount, 1);
    expect(report.streamingMetrics!.chunkCount, 2);
    expect(report.streamingMetrics!.completionTokens, 40);
    expect(_result(report, 'streaming_response').elapsed, isNotNull);
  });

  test('streaming skips unselected probes without a request', () async {
    final source = _StreamingRecordingDataSource();
    final report = await LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: source,
      mcpToolService: null,
    ).run(probeIds: const <String>{});
    expect(source.calls, 0);
    expect(
      _result(report, 'streaming_response').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(report.streamingMetrics, isNull);
  });

  for (final stage in ['request', 'stream', 'terminal']) {
    test(
      'streaming maps $stage errors to failed reports without metrics',
      () async {
        final source = _StreamingRecordingDataSource(failureStage: stage);
        final report = await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: false),
          chatDataSource: source,
          mcpToolService: null,
        ).run(probeIds: const {'streaming_response'});
        final result = _result(report, 'streaming_response');
        expect(result.status, LiveLlmDiagnosticStatus.failed);
        expect(result.summary, 'The streaming request failed.');
        expect(result.details, 'Bad state: $stage');
        expect(report.streamingMetrics, isNull);
        expect(report.thinkingMetrics, isNull);
      },
    );
  }

  for (final publication in [
    LiveLlmDiagnosticStatus.running,
    LiveLlmDiagnosticStatus.passed,
  ]) {
    test('streaming propagates $publication publication errors', () async {
      final source = _StreamingRecordingDataSource();
      final failure = StateError('publication');
      final run =
          LiveLlmDiagnosticService(
            settings: _settings(mcpEnabled: false),
            chatDataSource: source,
            mcpToolService: null,
          ).run(
            probeIds: const {'streaming_response'},
            onReport: (report) {
              if (_result(report, 'streaming_response').status == publication) {
                throw failure;
              }
            },
          );
      await expectLater(run, throwsA(same(failure)));
      expect(
        source.calls,
        publication == LiveLlmDiagnosticStatus.running ? 0 : 1,
      );
    });
  }

  test('effective context binds requests, thinking and publication', () async {
    final dataSource = _ContextRecordingDataSource();
    final statuses = <LiveLlmDiagnosticStatus>[];
    final report =
        await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: false, model: 'context-model'),
          chatDataSource: dataSource,
          mcpToolService: null,
          effectiveContextMaxTokens: 3000,
        ).run(
          probeIds: const {'effective_context'},
          onReport: (report) {
            final result = _result(report, 'effective_context');
            if (statuses.isEmpty || statuses.last != result.status) {
              statuses.add(result.status);
            }
          },
        );
    expect(dataSource.requestedModels, ['context-model', 'context-model']);
    expect(dataSource.contextCaps, [32, 32]);
    expect(dataSource.contextTemperatures, [0.0, 0.0]);
    expect(dataSource.contextTargets, [2048, 3000]);
    expect(statuses, [
      LiveLlmDiagnosticStatus.pending,
      LiveLlmDiagnosticStatus.running,
      LiveLlmDiagnosticStatus.passed,
    ]);
    expect(report.thinkingMetrics!.responseCount, 2);
    expect(report.thinkingMetrics!.reasoningResponseCount, 2);
    expect(report.effectiveContextMetrics!.configuredMaximumTokens, 3000);
  });

  test(
    'effective context skips unselected and unsupported providers',
    () async {
      for (final provider in [
        LlmProvider.openAiCompatible,
        LlmProvider.appleFoundationModels,
      ]) {
        var invoked = false;
        final dataSource = _FakeDiagnosticDataSource();
        final report =
            await LiveLlmDiagnosticService(
              settings: _settings(mcpEnabled: false, llmProvider: provider),
              chatDataSource: dataSource,
              mcpToolService: null,
              effectiveContextMaxTokens: 2048,
              runEffectiveContextTrial: (_, _) async {
                invoked = true;
                throw StateError('must not run');
              },
            ).run(
              probeIds: provider == LlmProvider.appleFoundationModels
                  ? const {'effective_context'}
                  : const <String>{},
            );
        expect(invoked, isFalse);
        expect(dataSource.requestedModels, isEmpty);
        expect(
          _result(report, 'effective_context').status,
          LiveLlmDiagnosticStatus.skipped,
        );
        expect(report.effectiveContextMetrics, isNull);
      }
    },
  );

  test(
    'effective context clamps the configured maximum before reporting',
    () async {
      final report = await LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false),
        chatDataSource: _FakeDiagnosticDataSource(),
        mcpToolService: null,
        effectiveContextMaxTokens: 1048577,
        runEffectiveContextTrial: (_, _) async => throw StateError('stop'),
      ).run(probeIds: const {'effective_context'});
      expect(report.effectiveContextMetrics!.configuredMaximumTokens, 1048576);
      expect(
        _result(report, 'effective_context').details,
        contains('Requested maximum was clamped to 1048576 tokens.'),
      );
    },
  );

  for (final publication in [
    LiveLlmDiagnosticStatus.running,
    LiveLlmDiagnosticStatus.passed,
  ]) {
    test(
      'effective context propagates $publication publication errors',
      () async {
        var requests = 0;
        final failure = StateError('publication');
        final run =
            LiveLlmDiagnosticService(
              settings: _settings(mcpEnabled: false),
              chatDataSource: _FakeDiagnosticDataSource(),
              mcpToolService: null,
              effectiveContextMaxTokens: 2048,
              runEffectiveContextTrial: (target, _) async {
                requests++;
                return ChatCompletionResult(
                  content: 'CTX_BEGIN_$target|CTX_END_$target',
                  finishReason: 'stop',
                  usage: const TokenUsage(promptTokens: 2048),
                );
              },
            ).run(
              probeIds: const {'effective_context'},
              onReport: (report) {
                if (_result(report, 'effective_context').status ==
                    publication) {
                  throw failure;
                }
              },
            );
        await expectLater(run, throwsA(same(failure)));
        expect(
          requests,
          publication == LiveLlmDiagnosticStatus.running ? 0 : 1,
        );
      },
    );
  }

  test(
    'tool recovery binds settings and publishes running then terminal reports',
    () async {
      final dataSource = _RecoveryRecordingDataSource();
      final updates = <LiveLlmDiagnosticReport>[];
      final report = await LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false, model: 'recovery-model'),
        chatDataSource: dataSource,
        mcpToolService: null,
      ).run(probeIds: const {'tool_recovery'}, onReport: updates.add);
      final result = _result(report, 'tool_recovery');
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.passedChecks, 4);
      expect(result.totalChecks, 4);
      expect(result.elapsed, isNotNull);
      expect(dataSource.recoveryRequestCount, 8);
      expect(
        updates.map((r) => _result(r, 'tool_recovery').status),
        containsAllInOrder([
          LiveLlmDiagnosticStatus.running,
          LiveLlmDiagnosticStatus.passed,
        ]),
      );
    },
  );

  test(
    'tool recovery skips providers without native calls without requests',
    () async {
      final dataSource = _RecoveryRecordingDataSource();
      final report = await LiveLlmDiagnosticService(
        settings: _settings(
          mcpEnabled: false,
          llmProvider: LlmProvider.appleFoundationModels,
        ),
        chatDataSource: dataSource,
        mcpToolService: null,
      ).run(probeIds: const {'tool_recovery'});
      final result = _result(report, 'tool_recovery');
      expect(result.status, LiveLlmDiagnosticStatus.skipped);
      expect(
        result.summary,
        'Skipped because the selected provider does not support this diagnostic capability.',
      );
      expect(dataSource.recoveryRequestCount, 0);
      expect(dataSource.requestedModels, isEmpty);
    },
  );

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
      // 17 since the tool-state staircase and tool recovery joined the run.
      17,
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
      _result(report, 'chart_reading').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'chart_reading').details,
      contains('No-image control: 0/4'),
    );
    expect(
      _result(report, 'vision_tool_observation').status,
      LiveLlmDiagnosticStatus.passed,
    );
    // Six, not four: video_input_modality skips as well. The fake endpoint
    // answers no /props, which is the same silence a proxy or a cloud provider
    // gives, and silence is "not measured" rather than "refused". And
    // thinking_control skips because this run has no per-mode datasource.
    expect(
      report.results
          .where((result) => result.status == LiveLlmDiagnosticStatus.skipped)
          .length,
      6,
    );
  });

  test('tool-result probe asks for a final answer without tools', () async {
    final dataSource = _ToolResultFollowUpDataSource();
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );

    final report = await service.run(
      probeIds: const {'tool_result_integration'},
    );

    expect(dataSource.followUpTools, isEmpty);
    expect(
      _result(report, 'tool_result_integration').status,
      LiveLlmDiagnosticStatus.passed,
    );
  });

  test(
    'tool-result probe identifies an unexpected repeated tool call',
    () async {
      final dataSource = _ToolResultFollowUpDataSource(repeatDatetime: true);
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: true),
        chatDataSource: dataSource,
        mcpToolService: McpToolService(),
      );

      final report = await service.run(
        probeIds: const {'tool_result_integration'},
      );
      final result = _result(report, 'tool_result_integration');

      expect(dataSource.followUpTools, isEmpty);
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.summary, contains('requested another tool'));
      expect(result.details, contains('get_current_datetime'));
      expect(result.details, contains('tool_calls'));
      expect(result.toolCalls, [
        'get_current_datetime',
        'get_current_datetime',
      ]);
    },
  );

  test('tool-result probe reports an empty final response', () async {
    final dataSource = _ToolResultFollowUpDataSource(emptyFinalAnswer: true);
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );

    final report = await service.run(
      probeIds: const {'tool_result_integration'},
    );
    final result = _result(report, 'tool_result_integration');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.summary, contains('no final answer'));
    expect(result.details, contains('Finish reason: stop'));
    expect(result.toolCalls, ['get_current_datetime']);
  });

  test(
    'reports the sampler sweep as unmeasured when temperature is dropped',
    () async {
      // An endpoint that 400s on `temperature` runs every request at its own
      // default, so a sweep would be one request repeated 32 times reported as
      // a clean pass across every temperature.
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: true),
        chatDataSource: _TemperatureIgnoringDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run();

      expect(report.samplerCalibrationTrials, isEmpty);
      expect(report.samplerCalibrationSummaries, isEmpty);
      expect(
        report.samplerCalibrationUnmeasuredReason,
        contains('rejects the `temperature` parameter'),
      );
      expect(
        report.toJson()['samplerCalibrationUnmeasured'],
        contains('Not measured'),
      );
      expect(report.toJson().containsKey('samplerCalibrationSummary'), isFalse);
      // The rest of the run is unaffected.
      expect(
        _result(report, 'instruction_echo').status,
        LiveLlmDiagnosticStatus.passed,
      );
    },
  );

  test('discards sampler trials when the endpoint 400s mid-sweep', () async {
    final dataSource = _TemperatureIgnoringDataSource(afterFirstNonZero: true);
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );

    final report = await service.run();

    expect(dataSource.endpointIgnoresRequestedTemperature, isTrue);
    expect(report.samplerCalibrationTrials, isEmpty);
    expect(
      report.samplerCalibrationUnmeasuredReason,
      contains('server default'),
    );
  });

  test('the vision probe image stays large enough to be readable', () {
    // Measured against a live endpoint: at 64px and 128px a vision-capable
    // model scored 0/3 on the quadrant question and at 256px/384px it scored
    // 3/3. A probe image below that threshold measures the harness, not the
    // model, so the dimensions are asserted rather than left to review.
    final bytes = base64Decode(LiveLlmDiagnosticService.visionProbeImageBase64);
    expect(bytes.sublist(1, 4), utf8.encode('PNG'));
    final header = ByteData.sublistView(bytes);
    final width = header.getUint32(16);
    final height = header.getUint32(20);
    expect(width, greaterThanOrEqualTo(256));
    expect(height, greaterThanOrEqualTo(256));
    expect(width, height);
  });

  test('the chart probe image stays large enough to be readable', () {
    // Measured against a live endpoint (qwen3.8-27b-vision): 600, 1100 and
    // 1700 pixels wide each answered all four questions correctly while the
    // no-image control answered none. Below the smallest measured pass the
    // probe would report the harness's limit as a model failure.
    final bytes = base64Decode(LiveLlmChartProbeImage.base64);
    expect(bytes.sublist(1, 4), utf8.encode('PNG'));
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(16), greaterThanOrEqualTo(600));
    expect(header.getUint32(20), greaterThanOrEqualTo(400));
  });

  group('chart answer grading', () {
    test('counts the readings a model got right', () {
      expect(
        LiveLlmDiagnosticService.matchedChartAnswers('78, 41, Dune, Cobalt'),
        4,
      );
    });

    test('reads the answer out of a sentence around it', () {
      expect(
        LiveLlmDiagnosticService.matchedChartAnswers(
          'Here are the readings:\n78, 41, Dune, Cobalt',
        ),
        4,
      );
    });

    test('grades the answer, not the reasoning that led to it', () {
      // The narration names the gridlines on its way to the answer. Scoring
      // the raw response scored that narration; this is the response a
      // production consumer would display.
      expect(
        LiveLlmDiagnosticService.matchedChartAnswers(
          '<think>Gridlines are 0, 20, 40, 60, 80, 100. Aster is 41, Briar '
          '78.</think>78, 41, Dune, Cobalt',
        ),
        4,
      );
    });

    test('is positional, so a reordered answer answers nothing', () {
      // The same four readings against the wrong four questions.
      expect(
        LiveLlmDiagnosticService.matchedChartAnswers('41, 78, Cobalt, Dune'),
        0,
      );
    });

    test('one wrong reading does not swallow the rest', () {
      // Measured against a live model, which read Aster as 40 where the bar is
      // 41 and got the other three exactly right.
      expect(
        LiveLlmDiagnosticService.matchedChartAnswers('78, 40, Dune, Cobalt'),
        4,
      );
      expect(
        LiveLlmDiagnosticService.matchedChartAnswers('78, 12, Dune, Cobalt'),
        3,
      );
    });

    test('accepts a numeric reading only within the tolerance', () {
      final justInside = 41 + LiveLlmDiagnosticService.chartValueTolerance;
      final justOutside = justInside + 1;
      expect(
        LiveLlmDiagnosticService.matchedChartAnswers(
          '78, $justInside, Dune, Cobalt',
        ),
        4,
      );
      expect(
        LiveLlmDiagnosticService.matchedChartAnswers(
          '78, $justOutside, Dune, Cobalt',
        ),
        3,
      );
    });

    test('scores nothing for an empty or short answer', () {
      expect(LiveLlmDiagnosticService.matchedChartAnswers(''), 0);
      expect(LiveLlmDiagnosticService.matchedChartAnswers('78'), 1);
    });
  });

  test(
    'a chart answer the control arm matches is not counted as read',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: true),
        chatDataSource: _FakeDiagnosticDataSource(blindChart: true),
        mcpToolService: McpToolService(),
      );

      final report = await service.run(probeIds: const {'chart_reading'});

      final result = _result(report, 'chart_reading');
      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.details, contains('model_guessed_without_reading'));
    },
  );

  test('a chart answer that never arrived is not a failed reading', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: _FakeDiagnosticDataSource(silentChart: true),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'chart_reading'});

    final result = _result(report, 'chart_reading');
    // Warning, not failed: a model that spent its budget reasoning was never
    // measured, so it was not shown to be unable to read a chart either.
    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.details, contains('no_answer_within_budget'));
    // Raising the budget was tried and the reasoning grew to fill it, so the
    // report must not send the next reader to raise it again.
    expect(result.details, isNot(contains('raise the probe budget')));
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
    // three edit formats) plus the vision block: two attachment arms, two
    // chart-reading arms, and one tool-observation request.
    expect(dataSource.requestedModels, List.filled(36, 'test-model'));
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

  test('counts the reasoning the probe responses actually carried', () async {
    const probeIds = {
      'streaming_response',
      'exact_preservation',
      'edit_format_fidelity',
    };
    final reasoning = await LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _ReasoningWrappedDiagnosticDataSource(),
      mcpToolService: McpToolService(),
    ).run(probeIds: probeIds);
    final plain = await LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
    ).run(probeIds: probeIds);

    final observed = reasoning.thinkingMetrics!;
    // One streamed answer, three exact-preservation arms, three edit formats.
    expect(observed.responseCount, 7);
    expect(observed.reasoningResponseCount, 7);
    expect(observed.reasoningChars, 7 * 'diagnostic reasoning'.length);
    // A fake datasource sends no thinking control, so nothing to contradict.
    expect(observed.requested, isNull);
    expect(observed.mismatch, isFalse);

    final absent = plain.thinkingMetrics!;
    expect(absent.responseCount, 7);
    expect(absent.reasoningResponseCount, 0);
    expect(absent.observed, isFalse);
    expect(plain.toJson()['thinking'], {
      'responseCount': 7,
      'reasoningResponseCount': 0,
      'reasoningChars': 0,
      'mismatch': false,
    });
  });

  group('thinking_control', () {
    test(
      'preserves mode requests, publication and thinking isolation',
      () async {
        final source = _ThinkingControlRecordingDataSource();
        final modes = <LiveLlmDiagnosticThinkingMode>[];
        final statuses = <LiveLlmDiagnosticStatus>[];
        final report =
            await LiveLlmDiagnosticService(
              settings: _settings(mcpEnabled: false, model: 'qwen3.8-27b-exl3'),
              chatDataSource: _FakeDiagnosticDataSource(),
              mcpToolService: null,
              thinkingModeDataSource: (mode) {
                modes.add(mode);
                return source;
              },
            ).run(
              probeIds: const {'thinking_control'},
              onReport: (report) {
                final status = _result(report, 'thinking_control').status;
                if (statuses.isEmpty || statuses.last != status) {
                  statuses.add(status);
                }
              },
            );
        expect(modes, LiveLlmDiagnosticThinkingMode.values);
        expect(source.requests, 2);
        expect(report.thinkingMetrics, isNull);
        expect(statuses, [
          LiveLlmDiagnosticStatus.pending,
          LiveLlmDiagnosticStatus.running,
          LiveLlmDiagnosticStatus.warning,
        ]);
        expect(
          _result(report, 'thinking_control').elapsed,
          greaterThan(Duration.zero),
        );
      },
    );

    for (final failureRequest in [1, 2]) {
      test(
        'request $failureRequest errors reach the failed boundary',
        () async {
          final source = _ThinkingControlRecordingDataSource(
            failureRequest: failureRequest,
          );
          final report = await LiveLlmDiagnosticService(
            settings: _settings(mcpEnabled: false, model: 'qwen3.8-27b-exl3'),
            chatDataSource: _FakeDiagnosticDataSource(),
            mcpToolService: null,
            thinkingModeDataSource: (_) => source,
          ).run(probeIds: const {'thinking_control'});
          expect(source.requests, failureRequest);
          expect(
            _result(report, 'thinking_control').status,
            LiveLlmDiagnosticStatus.failed,
          );
          expect(
            _result(report, 'thinking_control').details,
            contains('thinking request $failureRequest'),
          );
          expect(report.thinkingMetrics, isNull);
        },
      );
    }

    Future<LiveLlmDiagnosticProbeResult> runProbe({
      required bool reasonsWhenOn,
      required bool reasonsWhenOff,
      String model = 'qwen3.8-27b-exl3',
    }) async {
      final requestedModes = <LiveLlmDiagnosticThinkingMode>[];
      final report = await LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false, model: model),
        chatDataSource: _FakeDiagnosticDataSource(),
        mcpToolService: McpToolService(),
        thinkingModeDataSource: (mode) {
          requestedModes.add(mode);
          final reasons = mode == LiveLlmDiagnosticThinkingMode.on
              ? reasonsWhenOn
              : reasonsWhenOff;
          return reasons
              ? _ReasoningWrappedDiagnosticDataSource()
              : _FakeDiagnosticDataSource();
        },
      ).run(probeIds: const {'thinking_control'});
      final result = _result(report, 'thinking_control');
      if (result.status != LiveLlmDiagnosticStatus.skipped) {
        expect(requestedModes, LiveLlmDiagnosticThinkingMode.values);
      }
      // The deliberate mode switch must not count as the run's own thinking.
      expect(report.thinkingMetrics, isNull);
      return result;
    }

    test('passes when reasoning follows the request both ways', () async {
      final result = await runProbe(reasonsWhenOn: true, reasonsWhenOff: false);

      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.metadata['thinkingControl'], 'controllable');
    });

    test('warns when the serving path forces thinking off', () async {
      final result = await runProbe(
        reasonsWhenOn: false,
        reasonsWhenOff: false,
      );

      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.metadata['thinkingControl'], 'never_reasoned');
    });

    test('warns when the serving path forces thinking on', () async {
      final result = await runProbe(reasonsWhenOn: true, reasonsWhenOff: true);

      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.metadata['thinkingControl'], 'always_on');
    });

    test('warns when the serving path inverts thinking', () async {
      final result = await runProbe(reasonsWhenOn: false, reasonsWhenOff: true);
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.metadata['thinkingControl'], 'inverted');
    });

    test('skips an endpoint that cannot be sent enable_thinking', () async {
      final result = await runProbe(
        reasonsWhenOn: true,
        reasonsWhenOff: false,
        model: 'test-model',
      );

      expect(result.status, LiveLlmDiagnosticStatus.skipped);
      expect(result.metadata, isEmpty);
    });

    test('skips when the run has no per-mode datasource', () async {
      final report = await LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false, model: 'qwen3.8-27b-exl3'),
        chatDataSource: _FakeDiagnosticDataSource(),
        mcpToolService: McpToolService(),
      ).run(probeIds: const {'thinking_control'});

      expect(
        _result(report, 'thinking_control').status,
        LiveLlmDiagnosticStatus.skipped,
      );
    });
  });

  test('keeps update_goal string boolean failures explicit', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: _FakeDiagnosticDataSource(goalCompleted: 'True'),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'update_goal_fidelity'});
    final result = _result(report, 'update_goal_fidelity');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.details, contains('must be a JSON boolean'));
    expect(result.details, contains('{"completed":"True"}'));
    expect(
      result.metadata['argumentValidationError'],
      contains('received String "True"'),
    );
    expect(result.metadata['completedType'], 'boolean');
    expect(result.metadata['required'], 'completed');
    expect(result.metadata['additionalProperties'], 'false');
    expect(result.metadata['toolChoice'], contains('update_goal'));
  });

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

  test(
    'names the token cap when an edit format answer was truncated',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false),
        chatDataSource: _EditFormatDiagnosticDataSource(
          {
            ModelEditFormatPreference.wholeFile,
            ModelEditFormatPreference.searchReplace,
          },
          unifiedDiffResponse: '',
          unifiedDiffFinishReason: 'length',
        ),
        mcpToolService: McpToolService(),
      );

      final report = await service.run(probeIds: {'edit_format_fidelity'});
      final result = _result(report, 'edit_format_fidelity');

      // "received end of output" alone names the symptom and hides the cause.
      expect(result.details, contains('received end of output'));
      expect(
        result.details,
        contains('the response hit the token cap (finish_reason: length)'),
      );
    },
  );

  test('accepts a unified diff without the git a/ b/ path prefixes', () async {
    // `diff -u` and `patch -p0` use the bare path; the prefixes are a git
    // convention. Requiring them scored an applicable diff as a failure and
    // cost a model 18 of the probe's 55 points on spelling.
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _EditFormatDiagnosticDataSource(
        {
          ModelEditFormatPreference.wholeFile,
          ModelEditFormatPreference.searchReplace,
          ModelEditFormatPreference.unifiedDiff,
        },
        unifiedDiffResponse: _editFormatUnifiedDiff
            .replaceFirst('--- a/lib/greeting.dart', '--- lib/greeting.dart')
            .replaceFirst('+++ b/lib/greeting.dart', '+++ lib/greeting.dart'),
      ),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'edit_format_fidelity'});
    final result = _result(report, 'edit_format_fidelity');

    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.passedChecks, 3);
    expect(result.metadata['editFormatPreference'], 'unifiedDiff');
  });

  test('still rejects a unified diff whose body drifted', () async {
    // Only the file-header prefixes are forgiven: hunk headers and context
    // lines decide whether the diff would apply.
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _EditFormatDiagnosticDataSource(
        {
          ModelEditFormatPreference.wholeFile,
          ModelEditFormatPreference.searchReplace,
        },
        unifiedDiffResponse: _editFormatUnifiedDiff
            .replaceFirst('--- a/lib/greeting.dart', '--- lib/greeting.dart')
            .replaceFirst('@@ -1,4 +1,4 @@', '@@ -1,3 +1,3 @@'),
      ),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'edit_format_fidelity'});
    final result = _result(report, 'edit_format_fidelity');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.details, contains('unifiedDiff: failed'));
    expect(result.metadata['editFormatPreference'], 'searchReplace');
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
    final dataSource = _FakeDiagnosticDataSource();
    final updates = <LiveLlmDiagnosticReport>[];
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );

    final report = await service.run(
      probeIds: {'structured_output'},
      onReport: updates.add,
    );
    final result = _result(report, 'structured_output');

    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(dataSource.requestedModels, ['test-model']);
    expect(dataSource.structuredCaps, [2048]);
    expect(dataSource.structuredTemperatures, [0.0]);
    expect(report.thinkingMetrics?.responseCount, 1);
    expect(updates.map((r) => _result(r, 'structured_output').status).toSet(), {
      LiveLlmDiagnosticStatus.pending,
      LiveLlmDiagnosticStatus.running,
      LiveLlmDiagnosticStatus.passed,
    });
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

  test(
    'tool depth binds requests and publishes metrics with terminal report',
    () async {
      final source = _DepthRecordingDataSource();
      final updates = <LiveLlmDiagnosticReport>[];
      final report = await LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false, model: 'depth-model'),
        chatDataSource: source,
        mcpToolService: null,
      ).run(probeIds: const {'tool_state_staircase'}, onReport: updates.add);
      expect(source.requestCount, 12);
      expect(source.finalRequestCount, 3);
      expect(
        _result(report, 'tool_state_staircase').status,
        LiveLlmDiagnosticStatus.passed,
      );
      final running = updates.firstWhere(
        (r) =>
            _result(r, 'tool_state_staircase').status ==
            LiveLlmDiagnosticStatus.running,
      );
      expect(running.toolDepthMetrics, isNull);
      final terminal = updates.firstWhere(
        (r) =>
            _result(r, 'tool_state_staircase').status ==
            LiveLlmDiagnosticStatus.passed,
      );
      expect(terminal.toolDepthMetrics?.deepestPassedDepth, 4);
      expect(terminal.toolDepthMetrics?.attemptedDepths, [2, 3, 4]);
      expect(
        _result(terminal, 'tool_state_staircase').elapsed,
        greaterThanOrEqualTo(Duration.zero),
      );
    },
  );

  for (final selected in [false, true]) {
    test(
      'tool depth skips ${selected ? 'unsupported provider' : 'unselected probe'} without requests',
      () async {
        final source = _DepthRecordingDataSource();
        final report = await LiveLlmDiagnosticService(
          settings: _settings(
            mcpEnabled: false,
            llmProvider: selected
                ? LlmProvider.appleFoundationModels
                : LlmProvider.openAiCompatible,
          ),
          chatDataSource: source,
          mcpToolService: null,
        ).run(probeIds: selected ? const {'tool_state_staircase'} : const {});
        final result = _result(report, 'tool_state_staircase');
        expect(result.status, LiveLlmDiagnosticStatus.skipped);
        expect(
          result.summary,
          selected
              ? 'Skipped because the selected provider does not support this diagnostic capability.'
              : 'Skipped because this bounded diagnostic run did not request this probe.',
        );
        expect(report.toolDepthMetrics, isNull);
        expect(source.requestCount, 0);
      },
    );
  }

  for (final status in [
    LiveLlmDiagnosticStatus.running,
    LiveLlmDiagnosticStatus.passed,
  ]) {
    test('tool depth propagates $status publication errors', () async {
      final source = _DepthRecordingDataSource();
      final error = StateError('publication failed');
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false, model: 'depth-model'),
        chatDataSource: source,
        mcpToolService: null,
      );
      await expectLater(
        service.run(
          probeIds: const {'tool_state_staircase'},
          onReport: (report) {
            if (_result(report, 'tool_state_staircase').status == status) {
              throw error;
            }
          },
        ),
        throwsA(same(error)),
      );
      expect(
        source.requestCount,
        status == LiveLlmDiagnosticStatus.running ? 0 : 12,
      );
    });
  }

  // The staircase is headroom, not a floor: a model that loses the carried id
  // at rung three sits at depth 2 and must not fail the run for it.
  test('reports the deepest rung a model carried state through', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(toolDepthLimit: 2),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'tool_state_staircase'});
    final result = _result(report, 'tool_state_staircase');

    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(result.details, contains('Deepest passed depth: 2 of 4'));
    expect(result.details, contains('depth 3'));
    expect(report.toolDepthMetrics?.deepestPassedDepth, 2);
    expect(
      LiveLlmDiagnosticToolDepthLadder.fromReport(report).passedStageCount,
      1,
    );
  });

  test('passes the whole staircase when state survives every rung', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: {'tool_state_staircase'});
    final result = _result(report, 'tool_state_staircase');

    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(report.toolDepthMetrics?.deepestPassedDepth, 4);
    // Headroom stays unscored so cavernobench totals remain comparable.
    expect(LiveLlmDiagnosticSuite.pointsFor('tool_state_staircase'), 0);
  });

  test(
    'reports a token-cap truncation as truncation, not a violation',
    () async {
      // The endpoint drops response_format and answers 200, so the schema arm
      // reasons to the cap and returns nothing. Calling that "the response
      // violated the schema" blames the model for a budget the harness set.
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false),
        chatDataSource: _FakeDiagnosticDataSource(
          schemaArmRunsToTokenCap: true,
        ),
        mcpToolService: McpToolService(),
      );

      final report = await service.run(probeIds: {'structured_output'});
      final result = _result(report, 'structured_output');

      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.details, contains('finish_reason: length'));
      expect(result.details, isNot(contains('violated the schema')));
      expect(result.metadata['structuredOutputSupport'], 'jsonObject');
    },
  );

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

  test(
    'schema report publication failure still runs the object fallback',
    () async {
      final dataSource = _FakeDiagnosticDataSource();
      var schemaPublications = 0;
      final report =
          await LiveLlmDiagnosticService(
            settings: _settings(mcpEnabled: false),
            chatDataSource: dataSource,
            mcpToolService: McpToolService(),
          ).run(
            probeIds: {'structured_output'},
            onReport: (report) {
              if (_result(report, 'structured_output').status ==
                  LiveLlmDiagnosticStatus.passed) {
                schemaPublications += 1;
                throw StateError('publication failed');
              }
            },
          );

      expect(schemaPublications, 1);
      expect(dataSource.structuredCaps, [2048, 512]);
      expect(
        _result(report, 'structured_output').status,
        LiveLlmDiagnosticStatus.warning,
      );
      expect(
        _result(report, 'structured_output').details,
        contains('publication failed'),
      );
      expect(report.thinkingMetrics?.responseCount, 2);
    },
  );

  test('structured fallback reports and observes each response once', () async {
    final dataSource = _StructuredAccountingDataSource();
    final updates = <LiveLlmDiagnosticReport>[];
    final report = await LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    ).run(probeIds: {'structured_output'}, onReport: updates.add);

    final result = _result(report, 'structured_output');
    expect(dataSource.requestedModels, ['test-model', 'test-model']);
    expect(dataSource.structuredCaps, [2048, 512]);
    expect(dataSource.structuredTemperatures, [0.0, 0.0]);
    expect(result.usage.toJson(), {
      'promptTokens': 30,
      'completionTokens': 10,
      'totalTokens': 40,
    });
    expect(report.thinkingMetrics?.responseCount, 2);
    expect(report.thinkingMetrics?.reasoningResponseCount, 2);
    expect(result.modelContent, contains('<think>'));
    expect(updates.map((r) => _result(r, 'structured_output').status).toSet(), {
      LiveLlmDiagnosticStatus.pending,
      LiveLlmDiagnosticStatus.running,
      LiveLlmDiagnosticStatus.warning,
    });
    expect(
      ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.openAiCompatible,
      ).structuredOutputSupport,
      ModelStructuredOutputSupport.jsonObject,
    );
  });

  test(
    'unselected structured probe does not send a structured request',
    () async {
      final dataSource = _FakeDiagnosticDataSource();
      final report = await LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: false),
        chatDataSource: dataSource,
        mcpToolService: McpToolService(),
      ).run(probeIds: {'instruction_echo'});

      expect(dataSource.structuredCaps, isEmpty);
      expect(
        _result(report, 'structured_output').status,
        LiveLlmDiagnosticStatus.skipped,
      );
    },
  );

  test(
    'Apple provider skips structured output even with a capable datasource',
    () async {
      final dataSource = _FakeDiagnosticDataSource();
      final report = await LiveLlmDiagnosticService(
        settings: _settings(
          mcpEnabled: false,
          llmProvider: LlmProvider.appleFoundationModels,
        ),
        chatDataSource: dataSource,
        mcpToolService: McpToolService(),
      ).run(probeIds: {'structured_output'});

      expect(dataSource.requestedModels, isEmpty);
      expect(report.thinkingMetrics, isNull);
      final result = _result(report, 'structured_output');
      expect(result.status, LiveLlmDiagnosticStatus.skipped);
      expect(result.summary, contains('Apple Foundation Models'));
    },
  );

  test('datasource without response_format skips without generation', () async {
    final report = await LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _UnsupportedLanguageDataSource(),
      mcpToolService: McpToolService(),
    ).run(probeIds: {'structured_output'});

    final result = _result(report, 'structured_output');
    expect(result.status, LiveLlmDiagnosticStatus.skipped);
    expect(result.summary, contains('cannot send response_format'));
    expect(report.thinkingMetrics, isNull);
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

    expect(capturedInputs, [
      'A cat rests on a warm windowsill.',
      'The kitten is sleeping beside a sunny window.',
      'Database backups completed at midnight.',
    ]);
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

  test('vision probe grades the visible answer, not the think block', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _VisionReasoningDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'vision_attachment'});
    final result = _result(report, 'vision_attachment');

    // Both arms enumerate the four colors in order inside <think>; only the
    // attachment arm answers with them. Scoring the raw response scored the
    // control arm 4/4 and reported a sighted model as blind.
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.details, contains('read_correctly'));
    expect(result.details, contains('No-image control: 0/4'));
    // The preview carries the reading rather than the reasoning that hid it.
    expect(
      result.modelContent,
      contains('with_image: yellow, blue, red, green'),
    );
    expect(result.modelContent, isNot(contains('<think>')));
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

  test(
    'multi-round binding preserves requests and publishes metrics together',
    () async {
      final source = _MultiRoundRecordingDataSource();
      final updates = <LiveLlmDiagnosticReport>[];
      final report = await LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: true, model: 'multi-model'),
        chatDataSource: source,
        mcpToolService: McpToolService(),
      ).run(probeIds: const {'multi_round_tool_loop'}, onReport: updates.add);
      expect(source.requestCount, 3);
      expect(source.followUpCount, 2);
      expect(
        _result(report, 'multi_round_tool_loop').status,
        LiveLlmDiagnosticStatus.passed,
      );
      final running = updates.firstWhere(
        (r) =>
            _result(r, 'multi_round_tool_loop').status ==
            LiveLlmDiagnosticStatus.running,
      );
      expect(running.multiRoundToolLoopMetrics, isNull);
      final terminal = updates.firstWhere(
        (r) =>
            _result(r, 'multi_round_tool_loop').status ==
            LiveLlmDiagnosticStatus.passed,
      );
      expect(terminal.multiRoundToolLoopMetrics?.taskCompleted, isTrue);
    },
  );

  for (final selected in [false, true]) {
    test(
      'multi-round skips ${selected ? 'missing local tools' : 'unselected probe'} without model requests',
      () async {
        final source = _MultiRoundRecordingDataSource();
        final report = await LiveLlmDiagnosticService(
          settings: _settings(mcpEnabled: false),
          chatDataSource: source,
          mcpToolService: null,
        ).run(probeIds: selected ? const {'multi_round_tool_loop'} : const {});
        expect(
          _result(report, 'multi_round_tool_loop').status,
          LiveLlmDiagnosticStatus.skipped,
        );
        expect(source.requestCount, 0);
        if (selected) {
          expect(report.multiRoundToolLoopMetrics?.modelTurnCount, 0);
        } else {
          expect(report.multiRoundToolLoopMetrics, isNull);
        }
      },
    );
  }

  test(
    'multi-round request exceptions publish failed results without partial metrics',
    () async {
      final source = _MultiRoundRecordingDataSource(failRequest: true);
      final report = await LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: true, model: 'multi-model'),
        chatDataSource: source,
        mcpToolService: McpToolService(),
      ).run(probeIds: const {'multi_round_tool_loop'});
      final result = _result(report, 'multi_round_tool_loop');
      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, 'The multi-round tool loop request failed.');
      expect(result.details, 'Bad state: request failed');
      expect(report.multiRoundToolLoopMetrics, isNull);
    },
  );

  for (final status in [
    LiveLlmDiagnosticStatus.running,
    LiveLlmDiagnosticStatus.passed,
  ]) {
    test('multi-round propagates $status publication exceptions', () async {
      final source = _MultiRoundRecordingDataSource();
      final error = StateError('publication failed');
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: true, model: 'multi-model'),
        chatDataSource: source,
        mcpToolService: McpToolService(),
      );
      await expectLater(
        service.run(
          probeIds: const {'multi_round_tool_loop'},
          onReport: (report) {
            if (_result(report, 'multi_round_tool_loop').status == status) {
              throw error;
            }
          },
        ),
        throwsA(same(error)),
      );
      expect(
        source.requestCount,
        status == LiveLlmDiagnosticStatus.running ? 0 : 3,
      );
    });
  }

  test(
    'multi-round probe rejects a non-search call on the first turn',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: true),
        chatDataSource: _ExtraFirstRoundCallDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run(
        probeIds: const {'multi_round_tool_loop'},
      );
      final result = _result(report, 'multi_round_tool_loop');

      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, contains('did not call tool_search'));
      expect(result.toolCalls, ['tool_search', 'get_current_datetime']);
      expect(report.multiRoundToolLoopMetrics, isNotNull);
      expect(report.multiRoundToolLoopMetrics!.modelTurnCount, 1);
      expect(report.multiRoundToolLoopMetrics!.toolCallCount, 2);
      expect(report.multiRoundToolLoopMetrics!.successfulToolExecutionCount, 0);
      expect(report.multiRoundToolLoopMetrics!.taskCompleted, isFalse);
    },
  );

  test(
    'multi-round probe accepts a first turn that batches its searches',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(mcpEnabled: true),
        chatDataSource: _ParallelSearchDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run(
        probeIds: const {'multi_round_tool_loop'},
      );
      final result = _result(report, 'multi_round_tool_loop');

      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.toolCalls, [
        'tool_search',
        'tool_search',
        'get_current_datetime',
      ]);
      expect(report.multiRoundToolLoopMetrics!.modelTurnCount, 3);
      expect(report.multiRoundToolLoopMetrics!.toolCallCount, 3);
      // Both searches ran: parallel queries differ, so their union is what
      // decides discovery.
      expect(report.multiRoundToolLoopMetrics!.successfulToolExecutionCount, 3);
      expect(report.multiRoundToolLoopMetrics!.taskCompleted, isTrue);
    },
  );

  test('multi-round probe distinguishes a skipped search', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: _SkippedSearchDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run(probeIds: const {'multi_round_tool_loop'});
    final result = _result(report, 'multi_round_tool_loop');

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.summary, contains('did not call tool_search'));
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
    expect(result.summary, contains('did not call get_current_datetime'));
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

/// A GPT-5-class endpoint: it rejects `temperature`, so the request fallback
/// drops the parameter and every request runs at the server default.
class _TemperatureIgnoringDataSource extends _FakeDiagnosticDataSource
    implements RequestParameterFallbackAware {
  _TemperatureIgnoringDataSource({this.afterFirstNonZero = false});

  /// When true the endpoint only reveals itself once a sweep asks for a
  /// non-default temperature, so the flag flips in the middle of the sweep.
  final bool afterFirstNonZero;

  bool _revealed = false;

  @override
  bool get endpointIgnoresRequestedTemperature =>
      afterFirstNonZero ? _revealed : true;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    if (temperature != null && temperature > 0) {
      _revealed = true;
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

class _ToolResultRecordingDataSource extends _FakeDiagnosticDataSource {
  _ToolResultRecordingDataSource({this.failureStage});
  final String? failureStage;
  final requests = <String>[];

  void _record(
    String stage,
    String? model,
    double? temperature,
    int? maxTokens,
  ) {
    requests.add(stage);
    expect(model, 'tool-result-model');
    expect(temperature, 0.0);
    expect(maxTokens, 512);
    if (stage == failureStage) throw StateError('tool-result $stage');
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    _record('initial', model, temperature, maxTokens);
    expect(tools, hasLength(1));
    expect(tools!.single['function']['name'], 'get_current_datetime');
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
  }) {
    _record('follow-up', model, temperature, maxTokens);
    expect(tools, isEmpty);
    expect(toolResults.single.name, 'get_current_datetime');
    expect(messages.map((message) => message.role), [
      MessageRole.system,
      MessageRole.user,
    ]);
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

class _ToolResultFollowUpDataSource extends _FakeDiagnosticDataSource {
  _ToolResultFollowUpDataSource({
    this.repeatDatetime = false,
    this.emptyFinalAnswer = false,
  });

  final bool repeatDatetime;
  final bool emptyFinalAnswer;
  List<Map<String, dynamic>>? followUpTools;

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
    if (toolResults.single.name == 'get_current_datetime') {
      followUpTools = tools;
      if (repeatDatetime) {
        return Future.value(
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'repeated-datetime',
                name: 'get_current_datetime',
                arguments: const <String, dynamic>{},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        );
      }
      if (emptyFinalAnswer) {
        return Future.value(
          ChatCompletionResult(content: '', finishReason: 'stop'),
        );
      }
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

class _ExactRecordingDataSource extends _FakeDiagnosticDataSource {
  _ExactRecordingDataSource({this.failingArm});
  final int? failingArm;
  int calls = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    calls++;
    expect(model, 'exact-model');
    expect(temperature, 0.0);
    expect(maxTokens, 512);
    expect(tools, isNull);
    expect(messages.first.role, MessageRole.system);
    expect(messages.first.content, contains('Caverno live LLM diagnostics'));
    expect(
      messages.skip(1).every((message) => message.role == MessageRole.user),
      isTrue,
    );
    expect(messages, hasLength(calls == 2 ? 3 : 2));
    if (calls == 2) {
      expect(messages.last.content, contains('diagnostic_exact_value'));
      expect(messages.last.content, contains('ZX-900_α 2026-06-12'));
    }
    if (calls == failingArm) throw StateError('exact arm $calls');
    return ChatCompletionResult(
      content:
          '<think>preserve</think>${['12 GiB, ¥3,980', 'ZX-900_α 2026-06-12', 'https://example.test/downloads/build_2026-06-10.tar.zst?sha=abc123_def'][calls - 1]}',
      finishReason: 'stop',
      usage: const TokenUsage(
        promptTokens: 10,
        completionTokens: 3,
        totalTokens: 13,
      ),
    );
  }
}

class _StreamingRecordingDataSource extends _FakeDiagnosticDataSource {
  _StreamingRecordingDataSource({this.failureStage});

  final String? failureStage;
  int calls = 0;

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    calls++;
    expect(
      model,
      failureStage == null ? anyOf('stream-model', 'test-model') : 'test-model',
    );
    expect(temperature, 0.0);
    expect(maxTokens, 512);
    expect(messages.map((message) => message.role), [
      MessageRole.system,
      MessageRole.user,
    ]);
    expect(
      messages.last.content,
      'List every integer from 1 to 40 in order, one per line, with nothing '
      'else on any line.',
    );
    if (failureStage == 'request') throw StateError('request');
    return StreamedChatCompletion.capture(
      stream: failureStage == 'stream'
          ? Stream<String>.error(StateError('stream'))
          : Stream.fromIterable([
              '',
              '<think>count</think>',
              [for (var n = 1; n <= 40; n++) '$n'].join('\n'),
              '',
            ]),
      terminalMetadata: () {
        if (failureStage == 'terminal') throw StateError('terminal');
        return const ChatCompletionTerminalMetadata(
          finishReason: 'stop',
          usage: TokenUsage(
            promptTokens: 12,
            completionTokens: 40,
            totalTokens: 52,
          ),
        );
      },
    );
  }
}

class _ContextRecordingDataSource extends _FakeDiagnosticDataSource {
  final contextCaps = <int?>[];
  final contextTemperatures = <double?>[];
  final contextTargets = <int>[];

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    expect(tools, isNull);
    expect(messages.map((message) => message.role), [
      MessageRole.system,
      MessageRole.user,
    ]);
    expect(messages.first.content, contains('Caverno live LLM diagnostics'));
    final target = int.parse(
      RegExp(
        r'\nCTX_BEGIN_(\d+)\n',
      ).firstMatch(messages.last.content)!.group(1)!,
    );
    requestedModels.add(model);
    contextCaps.add(maxTokens);
    contextTemperatures.add(temperature);
    contextTargets.add(target);
    return ChatCompletionResult(
      content: '<think>recall</think>CTX_BEGIN_$target|CTX_END_$target',
      finishReason: 'stop',
      usage: TokenUsage(
        promptTokens: target,
        completionTokens: 8,
        totalTokens: target + 8,
      ),
    );
  }
}

class _FakeDiagnosticDataSource
    implements ChatDataSource, StructuredOutputChatDataSource {
  _FakeDiagnosticDataSource({
    this.textToolCalls = false,
    this.structuredOutputSupport = ModelStructuredOutputSupport.jsonSchema,
    this.bracedReasoning = false,
    this.blindChart = false,
    this.silentChart = false,
    this.schemaArmRunsToTokenCap = false,
    this.toolDepthLimit = 4,
    this.goalCompleted = true,
  });

  final bool textToolCalls;
  final ModelStructuredOutputSupport structuredOutputSupport;

  /// Reasons to the token cap and returns no answer, the way a model does
  /// when the endpoint silently dropped the schema it was told to follow.
  final bool schemaArmRunsToTokenCap;

  /// How deep the scripted tool-state staircase is allowed to get. A rung past
  /// this answers in text instead of calling the next tool, which is what
  /// losing the carried state looks like.
  final int toolDepthLimit;
  final Object goalCompleted;

  /// Answers the chart question the same with and without the image, which is
  /// what a model that never looked at the picture does.
  final bool blindChart;

  /// Spends the whole budget inside a think block and never answers.
  final bool silentChart;

  /// Prefixes structured answers with a `<think>` block that itself contains
  /// braces, the way a reasoning model's merged content arrives.
  final bool bracedReasoning;

  String _withReasoning(String content) {
    if (!bracedReasoning) {
      return content;
    }
    return '<think>No schema is visible here. Maybe they want '
        '{ "diagnostic": ... }? I will answer with the locked object.'
        '</think>$content';
  }

  int toolResultFollowUpCount = 0;
  final List<String?> requestedModels = [];
  final List<int?> structuredCaps = [];
  final List<double?> structuredTemperatures = [];

  /// Replays the tool-state staircase: one call per scripted step, then a
  /// final answer carrying every value that rung asks to see survive.
  ChatCompletionResult? _toolDepthStaircaseReply(
    List<Message> messages,
    List<Map<String, dynamic>>? tools,
  ) {
    final rung = LiveLlmToolDepthStaircase.rungs
        .where(
          (candidate) => messages.any((m) => m.content == candidate.prompt),
        )
        .firstOrNull;
    if (rung == null) return null;

    if (rung.depth > toolDepthLimit) {
      return ChatCompletionResult(
        content: 'I am not sure which document to use.',
        finishReason: 'stop',
      );
    }
    // One scripted observation message per completed step.
    final delivered = messages
        .where((message) => message.content.startsWith('Tool result for '))
        .length;
    // Regression: a mid-loop message that tells the model to answer made the
    // live run stop after one call and report "remains unexecuted".
    for (final message in messages.where(
      (message) => message.content.startsWith('Tool result for '),
    )) {
      if (message.content.contains("answer the user's question")) {
        throw StateError('mid-loop observation told the model to answer');
      }
    }
    if (tools == null || delivered >= rung.steps.length) {
      return ChatCompletionResult(
        content: _withReasoning(rung.expectedFinalValues.join(' ')),
        finishReason: 'stop',
      );
    }
    final step = rung.steps[delivered];
    return ChatCompletionResult(
      content: '',
      toolCalls: [
        ToolCallInfo(
          id: 'staircase-$delivered',
          name: step.toolName,
          arguments: Map<String, dynamic>.from(step.expectedArguments),
        ),
      ],
      finishReason: 'tool_calls',
    );
  }

  @override
  Future<ChatCompletionResult> createStructuredChatCompletion({
    required List<Message> messages,
    required StructuredOutputRequest responseFormat,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestedModels.add(model);
    structuredCaps.add(maxTokens);
    structuredTemperatures.add(temperature);
    if (responseFormat.format == StructuredOutputFormat.jsonSchema) {
      if (schemaArmRunsToTokenCap) {
        // An endpoint that drops response_format leaves the schema arm's
        // prompt with no values to produce, so the model reasons to the cap.
        return ChatCompletionResult(
          content: '<think>The schema was supposed to say which marker',
          finishReason: 'length',
        );
      }
      if (structuredOutputSupport != ModelStructuredOutputSupport.jsonSchema) {
        throw StateError('json_schema unsupported');
      }
      return ChatCompletionResult(
        content: _withReasoning(
          '{"marker":"CAVERNO_SCHEMA_LOCKED_47","count":47}',
        ),
        finishReason: 'stop',
      );
    }
    if (structuredOutputSupport == ModelStructuredOutputSupport.none) {
      throw StateError('json_object unsupported');
    }
    return ChatCompletionResult(
      content: _withReasoning('{"marker":"CAVERNO_JSON_OBJECT_OK","count":47}'),
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
    final staircase = _toolDepthStaircaseReply(messages, tools);
    if (staircase != null) return staircase;
    final recovery = scriptedToolRecoveryReply(messages);
    if (recovery != null) return recovery;
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
    if (user.contains('bar chart with a labelled y axis')) {
      // Stands in for a model that reads the chart: the control arm gets the
      // shape of an answer right and the readings wrong.
      if (silentChart) {
        return ChatCompletionResult(
          content: '<think>Gridlines are 0, 20, 40, 60, 80, 100. Aster sits',
          finishReason: 'length',
        );
      }
      return ChatCompletionResult(
        content: messages.last.imageBase64 == null && !blindChart
            ? '10, 4, Briar, Aster'
            : '78, 41, Dune, Cobalt',
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
      return _toolCall('update_goal', {'completed': goalCompleted});
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
    // first, not single: a first turn may batch its searches.
    final toolResult = toolResults.first;
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

class _StructuredAccountingDataSource extends _FakeDiagnosticDataSource {
  _StructuredAccountingDataSource()
    : super(bracedReasoning: true, schemaArmRunsToTokenCap: true);

  @override
  Future<ChatCompletionResult> createStructuredChatCompletion({
    required List<Message> messages,
    required StructuredOutputRequest responseFormat,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final result = await super.createStructuredChatCompletion(
      messages: messages,
      responseFormat: responseFormat,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    final schema = responseFormat.format == StructuredOutputFormat.jsonSchema;
    return ChatCompletionResult(
      content: result.content,
      finishReason: result.finishReason,
      usage: TokenUsage(
        promptTokens: schema ? 10 : 20,
        completionTokens: schema ? 3 : 7,
        totalTokens: schema ? 13 : 27,
      ),
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

class _EditRecordingDataSource extends _EditFormatDiagnosticDataSource {
  _EditRecordingDataSource({this.failingArm})
    : super({
        ModelEditFormatPreference.wholeFile,
        ModelEditFormatPreference.searchReplace,
        ModelEditFormatPreference.unifiedDiff,
      });
  final int? failingArm;
  int calls = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    calls++;
    expect(model, 'edit-model');
    expect(temperature, 0.0);
    expect(maxTokens, 2048);
    expect(tools, isNull);
    expect(messages.map((message) => message.role), [
      MessageRole.system,
      MessageRole.user,
    ]);
    expect(messages.first.content, contains('Caverno live LLM diagnostics'));
    if (calls == failingArm) throw StateError('edit arm $calls');
    final result = await super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    return ChatCompletionResult(
      content: '<think>edit</think>${result.content}',
      finishReason: result.finishReason,
      usage: const TokenUsage(
        promptTokens: 10,
        completionTokens: 3,
        totalTokens: 13,
      ),
    );
  }
}

class _EditFormatDiagnosticDataSource extends _FakeDiagnosticDataSource {
  _EditFormatDiagnosticDataSource(
    this.supported, {
    this.unifiedDiffResponse,
    this.unifiedDiffFinishReason = 'stop',
  });

  final Set<ModelEditFormatPreference> supported;
  final String? unifiedDiffResponse;
  final String unifiedDiffFinishReason;

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
        finishReason: unifiedDiffFinishReason,
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

class _ParallelSearchDataSource extends _FakeDiagnosticDataSource {
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
            id: 'call-search-date',
            name: 'tool_search',
            arguments: {'query': 'current date and timezone'},
          ),
          ToolCallInfo(
            id: 'call-search-relative',
            name: 'tool_search',
            arguments: {'query': 'relative_dates'},
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
    if (toolResults.first.name == 'tool_search') {
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

/// Narrates the four colors inside a think block on both arms and answers
/// correctly only with the image: the shape of a reasoning model, and the shape
/// that made the raw-response scorer report a sighted model as blind.
class _VisionReasoningDataSource extends _FakeDiagnosticDataSource {
  static const _thought =
      '<think>Quadrants could be yellow, blue, red, green or some other '
      'arrangement.</think>';

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (messages.last.content.contains('four equal quadrants')) {
      return ChatCompletionResult(
        content: messages.last.imageBase64 == null
            ? '$_thought\nred, green, blue, orange'
            : '$_thought\nyellow, blue, red, green',
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

class _RecoveryRecordingDataSource extends _FakeDiagnosticDataSource {
  int recoveryRequestCount = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    recoveryRequestCount += 1;
    expect(model, 'recovery-model');
    expect(temperature, 0);
    expect(maxTokens, 512);
    expect(tools, isNotEmpty);
    expect(messages.first.role, MessageRole.system);
    expect(messages.first.content, contains('Prefer OpenAI tool calls'));
    return super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _DepthRecordingDataSource extends _FakeDiagnosticDataSource {
  int requestCount = 0;
  int finalRequestCount = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestCount += 1;
    expect(model, 'depth-model');
    expect(temperature, 0);
    expect(maxTokens, 512);
    expect(messages.first.role, MessageRole.system);
    if (messages.last.content.startsWith('Every tool call is done.')) {
      finalRequestCount += 1;
      expect(tools, isNull);
    } else {
      expect(tools, same(LiveLlmToolDepthStaircase.toolDefinitions));
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

class _MultiRoundRecordingDataSource extends _FakeDiagnosticDataSource {
  _MultiRoundRecordingDataSource({this.failRequest = false});
  final bool failRequest;
  int requestCount = 0;
  int followUpCount = 0;

  void checkRequest(
    List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  ) {
    requestCount += 1;
    expect(model, 'multi-model');
    expect(temperature, 0);
    expect(maxTokens, 512);
    expect(messages.first.role, MessageRole.system);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    checkRequest(messages, model, temperature, maxTokens);
    expect(tools?.map((t) => t['function']['name']), ['tool_search']);
    if (failRequest) {
      throw StateError('request failed');
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
    checkRequest(messages, model, temperature, maxTokens);
    followUpCount += 1;
    expect(toolResults, hasLength(1));
    expect(
      tools?.map((t) => t['function']['name']),
      followUpCount == 1 ? ['tool_search', 'get_current_datetime'] : isEmpty,
    );
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

class _ThinkingControlRecordingDataSource extends _FakeDiagnosticDataSource {
  _ThinkingControlRecordingDataSource({this.failureRequest});
  final int? failureRequest;
  int requests = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
    Map<String, dynamic>? responseFormat,
    Map<String, String>? requestMetadata,
  }) async {
    requests++;
    expect(model, 'qwen3.8-27b-exl3');
    expect(temperature, 0.0);
    expect(maxTokens, 512);
    expect(tools, isNull);
    expect(messages.map((message) => message.role), [
      MessageRole.system,
      MessageRole.user,
    ]);
    expect(
      messages.last.content,
      'Reply with exactly CAVERNO_THINKING_CONTROL and no other text.',
    );
    if (requests == failureRequest) {
      throw StateError('thinking request $requests');
    }
    return ChatCompletionResult(
      content: 'CAVERNO_THINKING_CONTROL',
      finishReason: 'stop',
    );
  }
}
