import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
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
    'transient runtime overrides do not persist CLI configuration',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      container
          .read(settingsNotifierProvider.notifier)
          .applyTransientRuntimeOverrides(
            assistantMode: AssistantMode.coding,
            baseUrl: 'http://terminal.test/v1',
            model: 'terminal-model',
            apiKey: 'terminal-key',
            disabledBuiltInTools: const {'computer_click'},
          );

      final effective = container.read(settingsNotifierProvider);
      expect(effective.assistantMode, AssistantMode.coding);
      expect(effective.baseUrl, 'http://terminal.test/v1');
      expect(effective.model, 'terminal-model');
      expect(effective.codingApprovalMode, ToolApprovalMode.defaultPermissions);
      expect(effective.disabledBuiltInTools, contains('computer_click'));

      final persisted = SettingsRepository(prefs).load();
      expect(persisted.baseUrl, ApiConstants.defaultBaseUrl);
      expect(persisted.model, ApiConstants.defaultModel);
      expect(persisted.apiKey, ApiConstants.defaultApiKey);
    },
  );

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
    'prefix-stable tool loop setting persists through the repository',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsNotifierProvider.notifier);

      expect(
        container.read(settingsNotifierProvider).enablePrefixStableToolLoop,
        isFalse,
      );

      await notifier.updateEnablePrefixStableToolLoop(true);

      final settings = container.read(settingsNotifierProvider);
      expect(settings.enablePrefixStableToolLoop, isTrue);

      final reloaded = SettingsRepository(prefs).load();
      expect(reloaded.enablePrefixStableToolLoop, isTrue);
    },
  );

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

  test('model harness config updates persist through the repository', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(settingsNotifierProvider.notifier);
    final settingsBefore = container.read(settingsNotifierProvider);
    final config = ModelHarnessConfig(
      id: '',
      baseUrl: settingsBefore.baseUrl,
      model: settingsBefore.model,
      bootstrapInstruction: 'Create the answer file early.',
      toolLoopMaxIterations: 6,
    );

    await notifier.upsertModelHarnessConfig(config);

    var settings = container.read(settingsNotifierProvider);
    final persisted = settings.effectiveModelHarnessConfig;
    expect(persisted, isNotNull);
    expect(persisted!.bootstrapInstruction, 'Create the answer file early.');
    expect(persisted.toolLoopMaxIterations, 6);

    var reloaded = SettingsRepository(prefs).load();
    expect(
      reloaded.effectiveModelHarnessConfig?.bootstrapInstruction,
      'Create the answer file early.',
    );

    // Editing the stored config to clear every override removes the entry.
    await notifier.upsertModelHarnessConfig(
      persisted.copyWith(bootstrapInstruction: '', toolLoopMaxIterations: 0),
    );
    settings = container.read(settingsNotifierProvider);
    expect(settings.modelHarnessConfigs, isEmpty);
    reloaded = SettingsRepository(prefs).load();
    expect(reloaded.modelHarnessConfigs, isEmpty);
  });

  test('removeModelHarnessConfig drops a stored config by id', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(settingsNotifierProvider.notifier);
    final settingsBefore = container.read(settingsNotifierProvider);
    await notifier.upsertModelHarnessConfig(
      ModelHarnessConfig(
        id: '',
        baseUrl: settingsBefore.baseUrl,
        model: settingsBefore.model,
        recoveryMiddlewareEnabled: true,
      ),
    );

    final stored = container
        .read(settingsNotifierProvider)
        .effectiveModelHarnessConfig;
    expect(stored, isNotNull);

    await notifier.removeModelHarnessConfig(stored!.id);

    expect(
      container.read(settingsNotifierProvider).modelHarnessConfigs,
      isEmpty,
    );
    expect(SettingsRepository(prefs).load().modelHarnessConfigs, isEmpty);
  });

  group('LL21 profile revision history', () {
    ProviderContainer createContainer(SharedPreferences prefs) {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    ModelCapabilityProfile createProfile(String baseUrl, String model) =>
        ModelCapabilityProfile(
          id: ModelCapabilityProfile.buildId(
            provider: LlmProvider.openAiCompatible,
            baseUrl: baseUrl,
            model: model,
          ),
          model: model,
          baseUrl: baseUrl,
          probedAt: DateTime(2026, 6, 16),
          toolCallStyle: ModelToolCallStyle.nativeToolCalls,
          structuredOutputSupport: ModelStructuredOutputSupport.jsonSchema,
          editFormatPreference: ModelEditFormatPreference.searchReplace,
          usableContextTokens: 8192,
        );

    List<ModelCapabilityProfileRevision> revisionsFor(
      ProviderContainer container,
      String model,
    ) => container
        .read(settingsNotifierProvider)
        .capabilityProfileRevisionsFor(
          provider: LlmProvider.openAiCompatible,
          baseUrl: 'http://localhost:1234/v1',
          model: model,
        );

    test('upsert appends a revision with the given source', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs);
      final notifier = container.read(settingsNotifierProvider.notifier);

      final profile = createProfile('http://localhost:1234/v1', 'my-model');
      await notifier.upsertModelCapabilityProfile(
        profile,
        source: 'idle_re_probe',
      );

      final revisions = revisionsFor(container, 'my-model');
      expect(revisions, hasLength(1));
      expect(revisions.first.source, 'idle_re_probe');
      expect(revisions.first.capabilityChangeDetected, isFalse);
    });

    test(
      'second upsert sets capabilityChangeDetected when toolCallStyle changes',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = createContainer(prefs);
        final notifier = container.read(settingsNotifierProvider.notifier);

        final base = createProfile('http://localhost:1234/v1', 'my-model');
        await notifier.upsertModelCapabilityProfile(base, source: 'probe');

        final changed = base.copyWith(
          toolCallStyle: ModelToolCallStyle.embeddedToolTags,
        );
        await notifier.upsertModelCapabilityProfile(
          changed,
          source: 'idle_re_probe',
        );

        final revisions = revisionsFor(container, 'my-model');
        // Newest first: the idle_re_probe revision should be first.
        expect(revisions, hasLength(2));
        expect(revisions.first.source, 'idle_re_probe');
        expect(revisions.first.capabilityChangeDetected, isTrue);
      },
    );

    test(
      'capabilityChangeDetected is false when profile is unchanged',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = createContainer(prefs);
        final notifier = container.read(settingsNotifierProvider.notifier);

        final profile = createProfile('http://localhost:1234/v1', 'my-model');
        await notifier.upsertModelCapabilityProfile(profile, source: 'probe');
        await notifier.upsertModelCapabilityProfile(
          profile,
          source: 'idle_re_probe',
        );

        final revisions = revisionsFor(container, 'my-model');
        expect(revisions.first.capabilityChangeDetected, isFalse);
      },
    );

    test(
      'context-token drift > 20% triggers capabilityChangeDetected',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = createContainer(prefs);
        final notifier = container.read(settingsNotifierProvider.notifier);

        final base = createProfile('http://localhost:1234/v1', 'my-model');
        await notifier.upsertModelCapabilityProfile(base, source: 'probe');

        final drifted = base.copyWith(usableContextTokens: 4096); // 50% drop
        await notifier.upsertModelCapabilityProfile(
          drifted,
          source: 'idle_re_probe',
        );

        final revisions = revisionsFor(container, 'my-model');
        expect(revisions.first.capabilityChangeDetected, isTrue);
      },
    );

    test('revisions are capped at maxPerProfile per model id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs);
      final notifier = container.read(settingsNotifierProvider.notifier);

      final profile = createProfile('http://localhost:1234/v1', 'my-model');
      final cap = ModelCapabilityProfileRevision.maxPerProfile;

      for (var i = 0; i < cap + 3; i++) {
        await notifier.upsertModelCapabilityProfile(
          profile.copyWith(
            probedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
            probeSummary: 'run $i',
          ),
          source: 'idle_re_probe',
        );
      }

      final revisions = revisionsFor(container, 'my-model');
      expect(revisions.length, cap);
      // Newest is most recent; index 0 should be the last upserted.
      expect(revisions.first.probeSummary, 'run ${cap + 2}');
    });

    test('revisions for different model ids do not interfere', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs);
      final notifier = container.read(settingsNotifierProvider.notifier);

      final profileA = createProfile('http://localhost:1234/v1', 'model-a');
      final profileB = createProfile('http://localhost:1234/v1', 'model-b');

      await notifier.upsertModelCapabilityProfile(profileA, source: 'probe');
      await notifier.upsertModelCapabilityProfile(profileB, source: 'probe');
      await notifier.upsertModelCapabilityProfile(
        profileA.copyWith(toolCallStyle: ModelToolCallStyle.embeddedToolTags),
        source: 'idle_re_probe',
      );

      expect(revisionsFor(container, 'model-a'), hasLength(2));
      expect(revisionsFor(container, 'model-b'), hasLength(1));
    });
  });

  group('LL8 named endpoints', () {
    test('upsert registers, dedupes by base URL, and remove deletes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsNotifierProvider.notifier);

      await notifier.upsertNamedEndpoint(
        const NamedEndpoint(
          id: '',
          label: 'Studio Box',
          baseUrl: 'http://192.168.100.241:1234/v1',
        ),
      );
      var settings = container.read(settingsNotifierProvider);
      expect(settings.namedEndpoints, hasLength(1));
      final firstCreatedAt = settings.namedEndpoints.single.createdAt;
      expect(firstCreatedAt, isNotNull);

      // Re-registering the same base URL (trailing slash) updates in place and
      // preserves the original registration time.
      await notifier.upsertNamedEndpoint(
        const NamedEndpoint(
          id: '',
          label: 'Studio Box (renamed)',
          baseUrl: 'http://192.168.100.241:1234/v1/',
        ),
      );
      settings = container.read(settingsNotifierProvider);
      expect(settings.namedEndpoints, hasLength(1));
      expect(settings.namedEndpoints.single.label, 'Studio Box (renamed)');
      expect(settings.namedEndpoints.single.createdAt, firstCreatedAt);

      // Persisted across a reload.
      final reloaded = SettingsRepository(prefs).load();
      expect(reloaded.namedEndpoints, hasLength(1));

      await notifier.removeNamedEndpoint(settings.namedEndpoints.single.id);
      expect(container.read(settingsNotifierProvider).namedEndpoints, isEmpty);
    });

    test('upsert rejects an endpoint without a base URL', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsNotifierProvider.notifier);

      expect(
        () => notifier.upsertNamedEndpoint(
          const NamedEndpoint(id: '', baseUrl: ' '),
        ),
        throwsArgumentError,
      );
    });
  });
}
