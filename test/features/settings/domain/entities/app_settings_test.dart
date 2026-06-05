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
}
