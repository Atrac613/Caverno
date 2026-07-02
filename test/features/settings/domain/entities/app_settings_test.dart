import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  test('default max tokens is 8192 to avoid truncating coding output', () {
    expect(AppSettings.defaults().maxTokens, 8192);
  });

  test('only trusted MCP servers are exposed to the model', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'test-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      mcpEnabled: true,
      mcpServers: [
        McpServerConfig(
          url: 'http://trusted.example',
          enabled: true,
          trustState: McpServerTrustState.trusted,
        ),
        McpServerConfig(
          url: 'http://pending.example',
          enabled: true,
          trustState: McpServerTrustState.pending,
        ),
        McpServerConfig(
          url: 'http://blocked.example',
          enabled: true,
          trustState: McpServerTrustState.blocked,
        ),
      ],
    );

    expect(settings.enabledMcpServers.map((server) => server.normalizedUrl), [
      'http://trusted.example',
    ]);
    expect(
      settings.connectableMcpServers.map((server) => server.normalizedUrl),
      containsAll(['http://trusted.example', 'http://pending.example']),
    );
    expect(
      settings.connectableMcpServers.map((server) => server.normalizedUrl),
      isNot(contains('http://blocked.example')),
    );
  });

  test('normalizes the Google Chat webhook URL for delivery checks', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'test-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      googleChatWebhookUrl: ' https://chat.googleapis.com/v1/spaces/test ',
    );

    expect(
      settings.normalizedGoogleChatWebhookUrl,
      'https://chat.googleapis.com/v1/spaces/test',
    );
    expect(settings.hasGoogleChatWebhook, isTrue);
  });

  test('persists reasoning effort preference', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'test-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      reasoningEffort: ReasoningEffortPreference.high,
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.reasoningEffort, ReasoningEffortPreference.high);
    expect(decoded.reasoningEffort.apiValue, 'high');
    expect(ReasoningEffortPreference.automatic.apiValue, isNull);
  });

  test('defaults and persists semantic search settings', () {
    expect(AppSettings.defaults().enableSemanticSearch, isFalse);
    expect(AppSettings.defaults().embeddingsModel, '');

    final settings = AppSettings.defaults().copyWith(
      enableSemanticSearch: true,
      embeddingsModel: 'text-embedding-local',
    );
    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.enableSemanticSearch, isTrue);
    expect(decoded.embeddingsModel, 'text-embedding-local');
  });

  test('defaults to no named endpoints and persists registered ones', () {
    expect(AppSettings.defaults().namedEndpoints, isEmpty);

    final settings = AppSettings.defaults().copyWith(
      namedEndpoints: [
        const NamedEndpoint(
          id: 'will-be-recomputed',
          label: '  Studio Box  ',
          baseUrl: 'http://192.168.100.241:1234/v1/',
          apiKey: '  key  ',
        ),
        const NamedEndpoint(
          id: 'disabled',
          baseUrl: 'http://10.0.0.9:8080/v1',
          enabled: false,
        ),
      ],
    );
    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.namedEndpoints, hasLength(2));
    final first = decoded.namedEndpoints.first;
    // normalizedForPersistence trims and strips the trailing slash, and the id
    // is derived from the normalized base URL.
    expect(first.baseUrl, 'http://192.168.100.241:1234/v1');
    expect(first.label, 'Studio Box');
    expect(first.apiKey, 'key');
    expect(first.id, 'http://192.168.100.241:1234/v1');
    expect(first.displayLabel, 'Studio Box');

    // Only the enabled, valid endpoint is exposed for routing.
    expect(decoded.enabledNamedEndpoints, hasLength(1));
    expect(
      decoded.enabledNamedEndpoints.single.baseUrl,
      'http://192.168.100.241:1234/v1',
    );

    // Lookup by base URL tolerates a trailing slash / case differences.
    expect(
      decoded.namedEndpointForBaseUrl('HTTP://192.168.100.241:1234/v1')?.id,
      'http://192.168.100.241:1234/v1',
    );
  });

  test('defaults and persists per-role endpoint assignments', () {
    expect(AppSettings.defaults().memoryExtractionEndpointId, '');
    expect(AppSettings.defaults().subagentEndpointId, '');

    final settings = AppSettings.defaults().copyWith(
      memoryExtractionEndpointId: 'http://10.0.0.5:1234/v1',
      subagentEndpointId: 'http://10.0.0.9:8080/v1',
    );
    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.memoryExtractionEndpointId, 'http://10.0.0.5:1234/v1');
    expect(decoded.subagentEndpointId, 'http://10.0.0.9:8080/v1');
    expect(decoded.goalSuggestionEndpointId, '');
    expect(decoded.approvalAutoReviewEndpointId, '');
  });

  test('drops invalid named endpoints on parse', () {
    final json =
        jsonDecode(jsonEncode(AppSettings.defaults().toJson()))
            as Map<String, dynamic>;
    json['namedEndpoints'] = [
      {'id': 'a', 'baseUrl': '   '},
      {'id': 'b', 'baseUrl': 'http://10.0.0.5:1234/v1'},
    ];
    final decoded = AppSettings.fromJson(json);
    expect(decoded.namedEndpoints, hasLength(1));
    expect(decoded.namedEndpoints.single.baseUrl, 'http://10.0.0.5:1234/v1');
  });

  test('defaults and persists LLM provider selection', () {
    expect(AppSettings.defaults().llmProvider, LlmProvider.openAiCompatible);
    expect(AppSettings.defaults().effectiveModel, AppSettings.defaults().model);

    final settings = AppSettings.defaults().copyWith(
      llmProvider: LlmProvider.appleFoundationModels,
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.llmProvider, LlmProvider.appleFoundationModels);
    expect(decoded.effectiveModel, AppSettings.appleFoundationModelsModelId);
  });

  test('persists and resolves model capability profiles', () {
    final profile = ModelCapabilityProfile(
      id: 'stale-profile-id',
      baseUrl: ' HTTP://LOCALHOST:1234/v1 ',
      model: ' qwen-test ',
      toolCallStyle: ModelToolCallStyle.nativeToolCalls,
      structuredOutputSupport: ModelStructuredOutputSupport.jsonSchema,
      editFormatPreference: ModelEditFormatPreference.searchReplace,
      usableContextTokens: -1,
      probedAt: DateTime.utc(2026, 6, 12),
      probeSummary: ' Probe completed. ',
      probeMetadata: const {'nativeToolCalls': 'passed'},
    ).normalizedForPersistence();
    final settings = AppSettings.defaults().copyWith(
      baseUrl: 'http://localhost:1234/v1',
      model: 'qwen-test',
      modelCapabilityProfiles: [profile],
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.modelCapabilityProfiles, hasLength(1));
    expect(decoded.modelCapabilityProfiles.single.id, profile.computedId);
    expect(decoded.modelCapabilityProfiles.single.usableContextTokens, 0);
    expect(
      decoded.modelCapabilityProfiles.single.probeSummary,
      'Probe completed.',
    );
    expect(
      decoded.effectiveModelCapabilityProfile?.toolCallStyle,
      ModelToolCallStyle.nativeToolCalls,
    );
    expect(
      decoded.effectiveModelCapabilityProfile?.structuredOutputSupport,
      ModelStructuredOutputSupport.jsonSchema,
    );
  });

  test('unknown model capability enum values fall back safely', () {
    final json =
        jsonDecode(jsonEncode(AppSettings.defaults().toJson()))
              as Map<String, dynamic>
          ..['modelCapabilityProfiles'] = [
            {
              'id': ModelCapabilityProfile.buildId(
                provider: LlmProvider.openAiCompatible,
                baseUrl: AppSettings.defaults().baseUrl,
                model: AppSettings.defaults().model,
              ),
              'provider': 'openAiCompatible',
              'baseUrl': AppSettings.defaults().baseUrl,
              'model': AppSettings.defaults().model,
              'toolCallStyle': 'futureStyle',
              'structuredOutputSupport': 'futureStructuredOutput',
              'editFormatPreference': 'futureEditFormat',
            },
          ];

    final decoded = AppSettings.fromJson(json);
    final profile = decoded.effectiveModelCapabilityProfile;

    expect(profile, isNotNull);
    expect(profile!.toolCallStyle, ModelToolCallStyle.unknown);
    expect(
      profile.structuredOutputSupport,
      ModelStructuredOutputSupport.unknown,
    );
    expect(profile.editFormatPreference, ModelEditFormatPreference.unknown);
  });

  test('defaults to no model harness config', () {
    final defaults = AppSettings.defaults();

    expect(defaults.modelHarnessConfigs, isEmpty);
    expect(defaults.effectiveModelHarnessConfig, isNull);
  });

  test('persists and resolves model harness configs', () {
    final config = ModelHarnessConfig(
      id: 'stale-config-id',
      baseUrl: ' HTTP://LOCALHOST:1234/v1 ',
      model: ' qwen-test ',
      bootstrapInstruction: ' Create the answer file first. ',
      failureRecoveryInstruction: ' Re-read before retrying. ',
      toolLoopMaxIterations: -5,
      recoveryMiddlewareEnabled: true,
      explorationToEditNudgeEnabled: true,
    ).normalizedForPersistence();
    final settings = AppSettings.defaults().copyWith(
      baseUrl: 'http://localhost:1234/v1',
      model: 'qwen-test',
      modelHarnessConfigs: [config],
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.modelHarnessConfigs, hasLength(1));
    final stored = decoded.modelHarnessConfigs.single;
    expect(stored.id, config.computedId);
    // Normalization trims instructions and clamps a negative cap to zero.
    expect(stored.bootstrapInstruction, 'Create the answer file first.');
    expect(stored.failureRecoveryInstruction, 'Re-read before retrying.');
    expect(stored.toolLoopMaxIterations, 0);

    final effective = decoded.effectiveModelHarnessConfig;
    expect(effective, isNotNull);
    expect(effective!.recoveryMiddlewareEnabled, isTrue);
    expect(effective.explorationToEditNudgeEnabled, isTrue);
    expect(effective.hasInstructionOverrides, isTrue);
    expect(effective.hasControlPolicyOverrides, isTrue);
    expect(effective.isEmpty, isFalse);
  });

  test('reports an override-free harness config as empty', () {
    const config = ModelHarnessConfig(id: 'x', model: 'qwen-test');

    expect(config.isEmpty, isTrue);
    expect(config.hasInstructionOverrides, isFalse);
    expect(config.hasControlPolicyOverrides, isFalse);
    expect(config.copyWith(toolLoopMaxIterations: 12).isEmpty, isFalse);
    expect(
      config.copyWith(verificationInstruction: 'Verify tests pass.').isEmpty,
      isFalse,
    );
  });

  test('resolves the tool-loop cap with fallback and ceiling', () {
    const noOverride = ModelHarnessConfig(id: 'x', model: 'm');
    const lowCap = ModelHarnessConfig(
      id: 'x',
      model: 'm',
      toolLoopMaxIterations: 4,
    );
    const hugeCap = ModelHarnessConfig(
      id: 'x',
      model: 'm',
      toolLoopMaxIterations: 100000,
    );

    expect(noOverride.resolveToolLoopMaxIterations(12), 12);
    expect(lowCap.resolveToolLoopMaxIterations(12), 4);
    // A runaway value is clamped to the defensive ceiling.
    expect(
      hugeCap.resolveToolLoopMaxIterations(12),
      ModelHarnessConfig.maxToolLoopIterations,
    );
    // Negative values normalize to zero and fall back.
    expect(
      const ModelHarnessConfig(
        id: 'x',
        model: 'm',
        toolLoopMaxIterations: -3,
      ).resolveToolLoopMaxIterations(12),
      12,
    );
  });

  test('drops unknown harness config keys on parse (closed schema)', () {
    final json =
        jsonDecode(jsonEncode(AppSettings.defaults().toJson()))
              as Map<String, dynamic>
          ..['modelHarnessConfigs'] = [
            {
              'id': ModelHarnessConfig.buildId(
                provider: LlmProvider.openAiCompatible,
                baseUrl: AppSettings.defaults().baseUrl,
                model: AppSettings.defaults().model,
              ),
              'provider': 'openAiCompatible',
              'baseUrl': AppSettings.defaults().baseUrl,
              'model': AppSettings.defaults().model,
              'bootstrapInstruction': 'Start here.',
              // Not part of the declared schema; must be ignored, not persisted.
              'selfModifyingCode': 'rm -rf /',
              'unknownFutureField': 'ignored',
            },
          ];

    final decoded = AppSettings.fromJson(json);
    final config = decoded.effectiveModelHarnessConfig;

    expect(config, isNotNull);
    expect(config!.bootstrapInstruction, 'Start here.');
    // The reserialized config never carries the unknown keys.
    final reserialized = jsonEncode(config.toJson());
    expect(reserialized, isNot(contains('selfModifyingCode')));
    expect(reserialized, isNot(contains('unknownFutureField')));
  });

  test('persists coding approval mode', () {
    final settings = AppSettings.defaults().copyWith(
      codingApprovalMode: ToolApprovalMode.autoReview,
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.codingApprovalMode, ToolApprovalMode.autoReview);
  });

  test('defaults chat approval mode and persists changes independently', () {
    expect(
      AppSettings.defaults().chatApprovalMode,
      ToolApprovalMode.defaultPermissions,
    );

    final settings = AppSettings.defaults().copyWith(
      chatApprovalMode: ToolApprovalMode.fullAccess,
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.chatApprovalMode, ToolApprovalMode.fullAccess);
    // Chat approval mode must not leak into the coding approval policy.
    expect(decoded.codingApprovalMode, ToolApprovalMode.defaultPermissions);
  });

  test('legacy settings without chatApprovalMode fall back to default', () {
    final legacyJson =
        jsonDecode(jsonEncode(AppSettings.defaults().toJson()))
              as Map<String, dynamic>
          ..remove('chatApprovalMode');

    final decoded = AppSettings.fromJson(legacyJson);

    expect(decoded.chatApprovalMode, ToolApprovalMode.defaultPermissions);
  });

  test('defaults LLM session logs to enabled and persists opt out', () {
    expect(AppSettings.defaults().enableLlmSessionLogs, isTrue);

    final settings = AppSettings.defaults().copyWith(
      enableLlmSessionLogs: false,
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.enableLlmSessionLogs, isFalse);
  });

  test('defaults onboarding to incomplete and persists completion', () {
    expect(AppSettings.defaults().onboardingCompleted, isFalse);

    final settings = AppSettings.defaults().copyWith(onboardingCompleted: true);

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.onboardingCompleted, isTrue);
  });

  test(
    'defaults coding verification feedback to enabled and persists opt out',
    () {
      expect(AppSettings.defaults().enableCodingVerificationFeedback, isTrue);
      expect(
        AppSettings.defaults().codingVerificationTriggerPolicy,
        CodingVerificationTriggerPolicy.onCompletionClaim,
      );
      expect(
        AppSettings.defaults().effectiveCodingVerificationTimeoutSeconds,
        AppSettings.defaultCodingVerificationTimeoutSeconds,
      );
      expect(
        AppSettings.defaults().effectiveCodingVerificationMaxFailures,
        AppSettings.defaultCodingVerificationMaxFailures,
      );

      final settings = AppSettings.defaults().copyWith(
        enableCodingVerificationFeedback: false,
        codingVerificationTriggerPolicy:
            CodingVerificationTriggerPolicy.onRequestOnly,
        codingVerificationTimeoutSeconds: 120,
        codingVerificationMaxFailures: 7,
      );

      final decoded = AppSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.enableCodingVerificationFeedback, isFalse);
      expect(
        decoded.codingVerificationTriggerPolicy,
        CodingVerificationTriggerPolicy.onRequestOnly,
      );
      expect(decoded.effectiveCodingVerificationTimeoutSeconds, 120);
      expect(decoded.effectiveCodingVerificationMaxFailures, 7);
    },
  );

  test('clamps coding verification policy limits', () {
    final settings = AppSettings.defaults().copyWith(
      codingVerificationTimeoutSeconds: 1,
      codingVerificationMaxFailures: 99,
    );

    expect(
      settings.effectiveCodingVerificationTimeoutSeconds,
      AppSettings.minCodingVerificationTimeoutSeconds,
    );
    expect(
      settings.effectiveCodingVerificationMaxFailures,
      AppSettings.maxCodingVerificationMaxFailures,
    );
    expect(settings.runsCodingVerificationOnCompletionClaim, isTrue);
    expect(
      settings
          .copyWith(
            codingVerificationTriggerPolicy:
                CodingVerificationTriggerPolicy.onRequestOnly,
          )
          .runsCodingVerificationOnCompletionClaim,
      isFalse,
    );
  });

  test('migrates legacy disabled confirmation settings to full access', () {
    final legacyJson =
        jsonDecode(jsonEncode(AppSettings.defaults().toJson()))
              as Map<String, dynamic>
          ..remove('codingApprovalMode')
          ..['confirmFileMutations'] = false
          ..['confirmLocalCommands'] = false
          ..['confirmGitWrites'] = false;

    final decoded = AppSettings.fromJson(legacyJson);

    expect(decoded.codingApprovalMode, ToolApprovalMode.fullAccess);
  });

  test(
    'migrates partial legacy confirmation settings to default permissions',
    () {
      final legacyJson =
          jsonDecode(jsonEncode(AppSettings.defaults().toJson()))
                as Map<String, dynamic>
            ..remove('codingApprovalMode')
            ..['confirmFileMutations'] = false
            ..['confirmLocalCommands'] = true
            ..['confirmGitWrites'] = false;

      final decoded = AppSettings.fromJson(legacyJson);

      expect(decoded.codingApprovalMode, ToolApprovalMode.defaultPermissions);
    },
  );

  test('preserves routine Computer Use action allowlist entries', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'test-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      routineComputerUseActionAllowlist: [
        RoutineComputerUseActionAllowlistEntry(
          id: 'x-post-button',
          label: 'X Post button',
          toolName: 'computer_click',
          targetLabelContains: 'Post',
          targetRole: 'button',
          targetAction: 'publish',
          targetRisk: 'public_action',
          appNameContains: 'Safari',
          appBundleId: 'com.apple.Safari',
          windowTitleContains: 'X',
        ),
        RoutineComputerUseActionAllowlistEntry(
          id: 'empty-boundary',
          toolName: 'computer_click',
        ),
      ],
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.routineComputerUseActionAllowlist, hasLength(2));
    expect(
      decoded.routineComputerUseActionAllowlist.first.targetRisk,
      'public_action',
    );
    expect(decoded.enabledRoutineComputerUseActionAllowlist, hasLength(1));
    expect(
      decoded.enabledRoutineComputerUseActionAllowlist.single.id,
      'x-post-button',
    );
  });

  test('role models fall back to the main model when unset', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'main-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
    );

    expect(settings.effectiveMemoryExtractionModel, 'main-model');
    expect(settings.effectiveSubagentModel, 'main-model');
    expect(settings.effectiveGoalSuggestionModel, 'main-model');
    expect(settings.effectiveApprovalAutoReviewModel, 'main-model');

    final whitespaceOnly = settings.copyWith(memoryExtractionModel: '   ');
    expect(whitespaceOnly.effectiveMemoryExtractionModel, 'main-model');
  });

  test('assigned role models override the main model per role', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'main-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      memoryExtractionModel: 'small-memory-model',
      subagentModel: 'small-subagent-model',
    );

    expect(settings.effectiveMemoryExtractionModel, 'small-memory-model');
    expect(settings.effectiveSubagentModel, 'small-subagent-model');
    // Unassigned roles still fall back to the main model.
    expect(settings.effectiveGoalSuggestionModel, 'main-model');
    expect(settings.effectiveApprovalAutoReviewModel, 'main-model');
  });

  test('role models are ignored for the Apple Foundation Models provider', () {
    const settings = AppSettings(
      llmProvider: LlmProvider.appleFoundationModels,
      baseUrl: 'http://localhost:1234/v1',
      model: 'main-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      memoryExtractionModel: 'small-memory-model',
    );

    expect(
      settings.effectiveMemoryExtractionModel,
      AppSettings.appleFoundationModelsModelId,
    );
    expect(
      settings.effectiveSubagentModel,
      AppSettings.appleFoundationModelsModelId,
    );
  });

  test('role models survive a JSON round-trip and default for legacy JSON', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'main-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      memoryExtractionModel: 'small-memory-model',
      subagentModel: 'small-subagent-model',
      goalSuggestionModel: 'small-goal-model',
      approvalAutoReviewModel: 'small-review-model',
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.memoryExtractionModel, 'small-memory-model');
    expect(decoded.subagentModel, 'small-subagent-model');
    expect(decoded.goalSuggestionModel, 'small-goal-model');
    expect(decoded.approvalAutoReviewModel, 'small-review-model');

    final legacy = AppSettings.fromJson({
      'baseUrl': 'http://localhost:1234/v1',
      'model': 'main-model',
      'apiKey': 'no-key',
      'temperature': 0.7,
      'maxTokens': 4096,
    });
    expect(legacy.memoryExtractionModel, '');
    expect(legacy.effectiveMemoryExtractionModel, 'main-model');
  });
}
