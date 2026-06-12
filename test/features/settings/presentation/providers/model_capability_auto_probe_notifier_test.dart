import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/model_capability_auto_probe_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  test(
    'runForCurrentModel persists a profile for an unprofiled model',
    () async {
      final initialSettings = AppSettings.defaults().copyWith(
        model: 'auto-probed-model',
        mcpEnabled: false,
        mcpUrl: '',
        mcpUrls: const <String>[],
        mcpServers: const <McpServerConfig>[],
      );
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode(initialSettings.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final dataSource = _InstructionOnlyDataSource();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          mcpToolServiceProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(modelCapabilityAutoProbeNotifierProvider.notifier)
          .runForCurrentModel();

      final state = container.read(modelCapabilityAutoProbeNotifierProvider);
      expect(state.status, ModelCapabilityAutoProbeStatus.succeeded);
      expect(dataSource.requestCount, 1);
      expect(
        state.report?.results
            .singleWhere((result) => result.id == 'exact_preservation')
            .status
            .name,
        'skipped',
      );

      final settings = SettingsRepository(prefs).load();
      final profile = settings.effectiveModelCapabilityProfile;
      expect(profile, isNotNull);
      expect(profile!.model, 'auto-probed-model');
      expect(
        profile.structuredOutputSupport,
        ModelStructuredOutputSupport.jsonObject,
      );
    },
  );

  test('runForCurrentModel skips models with an existing profile', () async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'known-model',
      modelCapabilityProfiles: [
        ModelCapabilityProfile(
          id: '',
          baseUrl: AppSettings.defaults().baseUrl,
          model: 'known-model',
          toolCallStyle: ModelToolCallStyle.nativeToolCalls,
          structuredOutputSupport: ModelStructuredOutputSupport.jsonObject,
        ).normalizedForPersistence(),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final dataSource = _InstructionOnlyDataSource();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        mcpToolServiceProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(modelCapabilityAutoProbeNotifierProvider.notifier)
        .runForCurrentModel();

    final state = container.read(modelCapabilityAutoProbeNotifierProvider);
    expect(state.status, ModelCapabilityAutoProbeStatus.skipped);
    expect(dataSource.requestCount, 0);
  });
}

class _InstructionOnlyDataSource implements ChatDataSource {
  int requestCount = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestCount += 1;
    return ChatCompletionResult(
      content:
          '{"probe":"instruction_echo","status":"ok","marker":"CAVERNO_LIVE_DIAGNOSTIC"}',
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
}
