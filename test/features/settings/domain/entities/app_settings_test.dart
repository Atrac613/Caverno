import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
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

  test('defaults LLM session logs to disabled and persists opt in', () {
    expect(AppSettings.defaults().enableLlmSessionLogs, isFalse);

    final settings = AppSettings.defaults().copyWith(
      enableLlmSessionLogs: true,
    );

    final decoded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.enableLlmSessionLogs, isTrue);
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
