import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/constants/api_constants.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  test(
    'new MCP servers start pending and editing a trusted server resets trust',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsNotifierProvider.notifier);

      await notifier.addMcpServer();
      var settings = container.read(settingsNotifierProvider);
      final index = settings.configuredMcpServers.length - 1;

      expect(
        settings.configuredMcpServers[index].trustState,
        McpServerTrustState.pending,
      );

      await notifier.updateMcpServerUrl(index, 'http://localhost:8099');
      await notifier.updateMcpServerTrustState(
        index,
        McpServerTrustState.trusted,
      );

      settings = container.read(settingsNotifierProvider);
      expect(settings.configuredMcpServers[index].isTrusted, isTrue);
      expect(
        settings.enabledMcpServers.any(
          (server) => server.normalizedUrl == 'http://localhost:8099',
        ),
        isTrue,
      );

      await notifier.updateMcpServerUrl(index, 'http://localhost:8100');
      settings = container.read(settingsNotifierProvider);
      expect(
        settings.configuredMcpServers[index].trustState,
        McpServerTrustState.pending,
      );
      expect(
        settings.enabledMcpServers.any(
          (server) => server.normalizedUrl == 'http://localhost:8100',
        ),
        isFalse,
      );
    },
  );

  test(
    'bulk MCP server updates invalidate trust when identity changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsNotifierProvider.notifier);

      await notifier.updateMcpServers([
        const McpServerConfig(
          url: 'http://localhost:8081',
          enabled: true,
          trustState: McpServerTrustState.trusted,
        ),
      ]);

      var settings = container.read(settingsNotifierProvider);
      expect(settings.configuredMcpServers.single.isTrusted, isTrue);

      await notifier.updateMcpServers([
        settings.configuredMcpServers.single.copyWith(
          url: 'http://localhost:8082',
        ),
      ]);

      settings = container.read(settingsNotifierProvider);
      expect(
        settings.configuredMcpServers.single.trustState,
        McpServerTrustState.pending,
      );
      expect(settings.enabledMcpServers, isEmpty);
    },
  );

  test(
    'completeOnboarding persists the first-launch completion flag',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsNotifierProvider.notifier);

      expect(
        container.read(settingsNotifierProvider).onboardingCompleted,
        isFalse,
      );

      await notifier.completeOnboarding();

      final settings = container.read(settingsNotifierProvider);
      expect(settings.onboardingCompleted, isTrue);

      final reloaded = SettingsRepository(prefs).load();
      expect(reloaded.onboardingCompleted, isTrue);
    },
  );

  test(
    'updateLlmProvider leaves plan mode when selecting Apple Foundation Models',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsNotifierProvider.notifier);

      await notifier.updateAssistantMode(AssistantMode.plan);
      expect(
        container.read(settingsNotifierProvider).assistantMode,
        AssistantMode.plan,
      );

      await notifier.updateLlmProvider(LlmProvider.appleFoundationModels);

      final settings = container.read(settingsNotifierProvider);
      expect(settings.llmProvider, LlmProvider.appleFoundationModels);
      expect(settings.assistantMode, AssistantMode.general);
      expect(
        SettingsRepository(prefs).load().assistantMode,
        AssistantMode.general,
      );
    },
  );

  test(
    'updateAssistantMode rejects plan mode for Apple Foundation Models',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsNotifierProvider.notifier);

      await notifier.updateLlmProvider(LlmProvider.appleFoundationModels);
      await notifier.updateAssistantMode(AssistantMode.plan);

      final settings = container.read(settingsNotifierProvider);
      expect(settings.llmProvider, LlmProvider.appleFoundationModels);
      expect(settings.assistantMode, AssistantMode.general);
      expect(
        SettingsRepository(prefs).load().assistantMode,
        AssistantMode.general,
      );
    },
  );

  test(
    'applyNvidiaNimCloudPreset stores the OpenAI-compatible NIM endpoint',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsNotifierProvider.notifier);

      await notifier.updateLlmProvider(LlmProvider.appleFoundationModels);
      await notifier.updateApiKey(ApiConstants.defaultApiKey);
      await notifier.applyNvidiaNimCloudPreset();

      final settings = container.read(settingsNotifierProvider);
      expect(settings.llmProvider, LlmProvider.openAiCompatible);
      expect(settings.baseUrl, ApiConstants.nvidiaNimBaseUrl);
      expect(settings.model, ApiConstants.nvidiaNimDefaultModel);
      expect(settings.apiKey, isEmpty);

      final reloaded = SettingsRepository(prefs).load();
      expect(reloaded.baseUrl, ApiConstants.nvidiaNimBaseUrl);
      expect(reloaded.model, ApiConstants.nvidiaNimDefaultModel);
      expect(reloaded.apiKey, isEmpty);
    },
  );

  test('role model updates persist through the repository', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(settingsNotifierProvider.notifier);

    await notifier.updateMemoryExtractionModel(' small-memory-model ');
    await notifier.updateSubagentModel('small-subagent-model');
    await notifier.updateGoalSuggestionModel('small-goal-model');
    await notifier.updateApprovalAutoReviewModel('small-review-model');

    final settings = container.read(settingsNotifierProvider);
    expect(settings.memoryExtractionModel, 'small-memory-model');
    expect(settings.effectiveMemoryExtractionModel, 'small-memory-model');

    final reloaded = SettingsRepository(prefs).load();
    expect(reloaded.memoryExtractionModel, 'small-memory-model');
    expect(reloaded.subagentModel, 'small-subagent-model');
    expect(reloaded.goalSuggestionModel, 'small-goal-model');
    expect(reloaded.approvalAutoReviewModel, 'small-review-model');

    await notifier.updateSubagentModel('');
    expect(
      container.read(settingsNotifierProvider).effectiveSubagentModel,
      container.read(settingsNotifierProvider).model,
    );
  });

  test(
    'model capability profile updates persist through the repository',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsNotifierProvider.notifier);
      final profile = ModelCapabilityProfile(
        id: '',
        baseUrl: container.read(settingsNotifierProvider).baseUrl,
        model: container.read(settingsNotifierProvider).model,
        toolCallStyle: ModelToolCallStyle.embeddedToolTags,
        structuredOutputSupport: ModelStructuredOutputSupport.jsonObject,
        editFormatPreference: ModelEditFormatPreference.wholeFile,
        usableContextTokens: 8192,
        probedAt: DateTime.utc(2026, 6, 12),
        probeSummary: 'Manual diagnostic completed.',
      );

      await notifier.upsertModelCapabilityProfile(profile);

      var settings = container.read(settingsNotifierProvider);
      final persistedProfile = settings.effectiveModelCapabilityProfile;
      expect(persistedProfile, isNotNull);
      expect(
        persistedProfile!.toolCallStyle,
        ModelToolCallStyle.embeddedToolTags,
      );
      expect(persistedProfile.usableContextTokens, 8192);

      var reloaded = SettingsRepository(prefs).load();
      expect(
        reloaded.effectiveModelCapabilityProfile?.structuredOutputSupport,
        ModelStructuredOutputSupport.jsonObject,
      );

      await notifier.upsertModelCapabilityProfile(
        persistedProfile.copyWith(
          toolCallStyle: ModelToolCallStyle.nativeToolCalls,
        ),
      );
      settings = container.read(settingsNotifierProvider);
      expect(settings.modelCapabilityProfiles, hasLength(1));
      expect(
        settings.effectiveModelCapabilityProfile?.toolCallStyle,
        ModelToolCallStyle.nativeToolCalls,
      );

      await notifier.removeModelCapabilityProfile(persistedProfile.id);

      settings = container.read(settingsNotifierProvider);
      expect(settings.modelCapabilityProfiles, isEmpty);
      reloaded = SettingsRepository(prefs).load();
      expect(reloaded.modelCapabilityProfiles, isEmpty);
    },
  );
}
