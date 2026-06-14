import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';
import 'package:caverno/features/settings/presentation/providers/live_llm_diagnostic_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  test('run persists a model capability profile from the report', () async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'diagnostic-model',
      mcpEnabled: false,
      mcpUrl: '',
      mcpUrls: const <String>[],
      mcpServers: const <McpServerConfig>[],
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chatRemoteDataSourceProvider.overrideWithValue(
          _TextOnlyDiagnosticDataSource(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    await container.read(liveLlmDiagnosticNotifierProvider.notifier).run();

    final diagnosticState = container.read(liveLlmDiagnosticNotifierProvider);
    expect(diagnosticState.isRunning, isFalse);
    expect(
      diagnosticState.report?.overallStatus,
      LiveLlmDiagnosticStatus.passed,
    );

    final settings = SettingsRepository(prefs).load();
    final profile = settings.effectiveModelCapabilityProfile;
    expect(profile, isNotNull);
    expect(profile!.model, 'diagnostic-model');
    expect(profile.toolCallStyle, ModelToolCallStyle.unknown);
    expect(
      profile.structuredOutputSupport,
      ModelStructuredOutputSupport.jsonObject,
    );
    expect(profile.probeMetadata['probe.instruction_echo.status'], 'passed');
  });

  test('run persists sampler metadata from diagnostic trials', () async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'sampler-diagnostic-model',
      mcpEnabled: true,
      mcpUrl: '',
      mcpUrls: const <String>[],
      mcpServers: const <McpServerConfig>[],
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chatRemoteDataSourceProvider.overrideWithValue(
          _NativeToolDiagnosticDataSource(),
        ),
        mcpToolServiceProvider.overrideWithValue(McpToolService()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(liveLlmDiagnosticNotifierProvider.notifier).run();

    final diagnosticState = container.read(liveLlmDiagnosticNotifierProvider);
    expect(diagnosticState.isRunning, isFalse);
    expect(diagnosticState.report?.samplerCalibrationTrials, hasLength(32));

    final settings = SettingsRepository(prefs).load();
    final profile = settings.effectiveModelCapabilityProfile;
    expect(profile, isNotNull);
    expect(profile!.model, 'sampler-diagnostic-model');
    expect(profile.toolCallStyle, ModelToolCallStyle.nativeToolCalls);
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.2',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.scoreKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '1.000',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.trialCountKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '2',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.sourceKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      'probe',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.routine,
      )],
      '0.2',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.scoreKey(
        LlmSamplerRequestClass.routine,
      )],
      '1.000',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.trialCountKey(
        LlmSamplerRequestClass.routine,
      )],
      '2',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.coding,
      )],
      '0.2',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.scoreKey(
        LlmSamplerRequestClass.coding,
      )],
      '1.000',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.trialCountKey(
        LlmSamplerRequestClass.coding,
      )],
      '2',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.plan,
      )],
      '0.2',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.scoreKey(
        LlmSamplerRequestClass.plan,
      )],
      '1.000',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.trialCountKey(
        LlmSamplerRequestClass.plan,
      )],
      '2',
    );
  });
}

class _TextOnlyDiagnosticDataSource implements ChatDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
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
    return ChatCompletionResult(
      content:
          '{"probe":"instruction_echo","status":"ok","marker":"CAVERNO_LIVE_DIAGNOSTIC"}',
      finishReason: 'stop',
    );
  }

  @override
  Stream<String> streamChatCompletion({
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
}

class _NativeToolDiagnosticDataSource extends _TextOnlyDiagnosticDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final user = messages.last.content;
    if (user.contains('tool catalog search tool')) {
      return _toolCall('tool_search', {
        'query': 'delegate focused sub-task child agent',
        'max_results': 8,
      });
    }
    if (user.contains('spawn_subagent tool call')) {
      return _toolCall('spawn_subagent', {
        'description': 'Diagnostic subagent marker summary',
        'prompt': 'Summarize the marker CAVERNO_SUBAGENT_DIAGNOSTIC and stop.',
        'background': true,
      });
    }
    if (user.contains('get_current_datetime')) {
      return _toolCall('get_current_datetime', const <String, dynamic>{});
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
    final relativeDates = payload['relative_dates'] as Map<String, dynamic>;
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

  ChatCompletionResult _toolCall(String name, Map<String, dynamic> arguments) {
    return ChatCompletionResult(
      content: '',
      toolCalls: [
        ToolCallInfo(id: 'call-$name', name: name, arguments: arguments),
      ],
      finishReason: 'tool_calls',
    );
  }
}
