import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/model_catalog_entry.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';
import 'package:caverno/features/settings/presentation/providers/model_capability_auto_probe_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
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
      // 32 pre-vision requests (including structured-output fallback and
      // streaming) plus the two vision
      // attachment arms. The tool-observation probe goes through a different
      // datasource method, so it is not part of this count.
      expect(dataSource.requestCount, 34);
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
      expect(profile.goalUpdateFidelity, ModelGoalUpdateFidelity.reliable);
      expect(
        profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.routine,
        )],
        '0.2',
      );
      expect(
        profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.coding,
        )],
        '0.2',
      );
      expect(
        profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.plan,
        )],
        '0.2',
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
        modelCatalogProvider(
          ModelListConfig(
            baseUrl: AppSettings.defaults().baseUrl,
            apiKey: AppSettings.defaults().apiKey,
            selectedModelId: 'known-model',
          ),
        ).overrideWith((ref) async => const <ModelCatalogEntry>[]),
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

  test('backfills a stored profile that never measured its context', () async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'known-model',
      modelCapabilityProfiles: [
        ModelCapabilityProfile(
          id: '',
          baseUrl: AppSettings.defaults().baseUrl,
          model: 'known-model',
          toolCallStyle: ModelToolCallStyle.nativeToolCalls,
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
        modelCatalogProvider(
          ModelListConfig(
            baseUrl: AppSettings.defaults().baseUrl,
            apiKey: AppSettings.defaults().apiKey,
            selectedModelId: 'known-model',
          ),
        ).overrideWith(
          (ref) async => const [
            ModelCatalogEntry(id: 'known-model', contextWindowTokens: 32768),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(modelCapabilityAutoProbeNotifierProvider.notifier)
        .runForCurrentModel();

    expect(
      container.read(modelCapabilityAutoProbeNotifierProvider).status,
      ModelCapabilityAutoProbeStatus.skipped,
    );
    expect(
      dataSource.requestCount,
      0,
      reason: 'the backfill must not spend LLM calls',
    );
    expect(
      SettingsRepository(
        prefs,
      ).load().effectiveModelCapabilityProfile?.usableContextTokens,
      32768,
    );
    expect(
      SettingsRepository(
        prefs,
      ).load().effectiveModelCapabilityProfile?.toolCallStyle,
      ModelToolCallStyle.nativeToolCalls,
      reason: 'the backfill only adds the context window',
    );
  });

  test('backfills the video modality without spending a probe run', () async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'known-model',
      modelCapabilityProfiles: [
        ModelCapabilityProfile(
          id: '',
          baseUrl: AppSettings.defaults().baseUrl,
          model: 'known-model',
          toolCallStyle: ModelToolCallStyle.nativeToolCalls,
        ).normalizedForPersistence(),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final dataSource = _InstructionOnlyDataSource();
    Uri? asked;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        mcpToolServiceProvider.overrideWithValue(null),
        modalitiesProbeClientProvider.overrideWithValue(
          () => MockClient((request) async {
            asked = request.url;
            return http.Response(
              jsonEncode({
                'modalities': {'vision': true, 'video': true, 'audio': false},
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(modelCapabilityAutoProbeNotifierProvider.notifier)
        .runForCurrentModel();

    expect(
      dataSource.requestCount,
      0,
      reason: 'the backfill must not spend LLM calls',
    );
    expect(asked?.path, '/props');
    expect(
      asked?.queryParameters['model'],
      'known-model',
      reason: 'a router only answers about a model it is asked about',
    );
    final stored = SettingsRepository(
      prefs,
    ).load().effectiveModelCapabilityProfile;
    expect(stored?.videoInputSupport, ModelVideoInputSupport.supported);
    expect(
      stored?.toolCallStyle,
      ModelToolCallStyle.nativeToolCalls,
      reason: 'the backfill only adds the video modality',
    );
  });

  test('ensureVideoInputSupport resolves without running a probe', () async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'known-model',
      modelCapabilityProfiles: [
        ModelCapabilityProfile(
          id: '',
          baseUrl: AppSettings.defaults().baseUrl,
          model: 'known-model',
          toolCallStyle: ModelToolCallStyle.nativeToolCalls,
        ).normalizedForPersistence(),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final dataSource = _InstructionOnlyDataSource();
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        mcpToolServiceProvider.overrideWithValue(null),
        modalitiesProbeClientProvider.overrideWithValue(
          () => MockClient((_) async {
            reads += 1;
            return http.Response(
              jsonEncode({
                'modalities': {'vision': true, 'video': true},
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(
      modelCapabilityAutoProbeNotifierProvider.notifier,
    );
    await notifier.ensureVideoInputSupport();
    // The composer calls this on every mount; the answer does not change.
    await notifier.ensureVideoInputSupport();
    await notifier.ensureVideoInputSupport();

    expect(dataSource.requestCount, 0, reason: 'must not spend LLM calls');
    expect(reads, 1, reason: 'one read per profile, not one per mount');
    expect(
      SettingsRepository(
        prefs,
      ).load().effectiveModelCapabilityProfile?.videoInputSupport,
      ModelVideoInputSupport.supported,
    );
  });

  test('an endpoint that says nothing leaves the profile alone', () async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'known-model',
      modelCapabilityProfiles: [
        ModelCapabilityProfile(
          id: '',
          baseUrl: AppSettings.defaults().baseUrl,
          model: 'known-model',
          toolCallStyle: ModelToolCallStyle.nativeToolCalls,
        ).normalizedForPersistence(),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chatRemoteDataSourceProvider.overrideWithValue(
          _InstructionOnlyDataSource(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        modalitiesProbeClientProvider.overrideWithValue(
          // A router asked about itself: 200, JSON, no modalities at all.
          () => MockClient(
            (_) async => http.Response(
              jsonEncode({'role': 'router', 'model_path': 'none'}),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(modelCapabilityAutoProbeNotifierProvider.notifier)
        .runForCurrentModel();

    expect(
      SettingsRepository(
        prefs,
      ).load().effectiveModelCapabilityProfile?.videoInputSupport,
      ModelVideoInputSupport.unknown,
      reason: 'silence is not a denial, and must not churn the revision list',
    );
  });
}

class _InstructionOnlyDataSource
    implements ChatDataSource, StructuredOutputChatDataSource {
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
    final user = messages.last.content;
    if (user.contains('update_goal exactly once')) {
      return ChatCompletionResult(
        content: '',
        toolCalls: [
          ToolCallInfo(
            id: 'call-update-goal',
            name: 'update_goal',
            arguments: const {'completed': true},
          ),
        ],
        finishReason: 'tool_calls',
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
  Future<ChatCompletionResult> createStructuredChatCompletion({
    required List<Message> messages,
    required StructuredOutputRequest responseFormat,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestCount += 1;
    return switch (responseFormat.format) {
      StructuredOutputFormat.jsonSchema => ChatCompletionResult(
        content: '{"marker":"wrong","count":0}',
        finishReason: 'stop',
      ),
      StructuredOutputFormat.jsonObject => ChatCompletionResult(
        content: '{"marker":"CAVERNO_JSON_OBJECT_OK","count":47}',
        finishReason: 'stop',
      ),
    };
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
    requestCount += 1;
    final content = [for (var value = 1; value <= 40; value += 1) '$value\n'];
    return StreamedChatCompletion.fromStream(
      Stream.value(content.join()),
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
}
