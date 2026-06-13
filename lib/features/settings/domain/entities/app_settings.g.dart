// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LocalCommandPermissionRule _$LocalCommandPermissionRuleFromJson(
  Map<String, dynamic> json,
) => _LocalCommandPermissionRule(
  id: json['id'] as String,
  enabled: json['enabled'] as bool? ?? true,
  action:
      $enumDecodeNullable(
        _$LocalCommandPermissionActionEnumMap,
        json['action'],
        unknownValue: LocalCommandPermissionAction.ask,
      ) ??
      LocalCommandPermissionAction.ask,
  match:
      $enumDecodeNullable(
        _$LocalCommandPermissionMatchEnumMap,
        json['match'],
        unknownValue: LocalCommandPermissionMatch.exact,
      ) ??
      LocalCommandPermissionMatch.exact,
  pattern: json['pattern'] as String? ?? '',
  workingDirectory: json['workingDirectory'] as String? ?? '',
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$LocalCommandPermissionRuleToJson(
  _LocalCommandPermissionRule instance,
) => <String, dynamic>{
  'id': instance.id,
  'enabled': instance.enabled,
  'action': _$LocalCommandPermissionActionEnumMap[instance.action]!,
  'match': _$LocalCommandPermissionMatchEnumMap[instance.match]!,
  'pattern': instance.pattern,
  'workingDirectory': instance.workingDirectory,
  'createdAt': instance.createdAt?.toIso8601String(),
};

const _$LocalCommandPermissionActionEnumMap = {
  LocalCommandPermissionAction.allow: 'allow',
  LocalCommandPermissionAction.deny: 'deny',
  LocalCommandPermissionAction.ask: 'ask',
};

const _$LocalCommandPermissionMatchEnumMap = {
  LocalCommandPermissionMatch.exact: 'exact',
  LocalCommandPermissionMatch.prefix: 'prefix',
};

_RoutineComputerUseActionAllowlistEntry
_$RoutineComputerUseActionAllowlistEntryFromJson(Map<String, dynamic> json) =>
    _RoutineComputerUseActionAllowlistEntry(
      id: json['id'] as String,
      enabled: json['enabled'] as bool? ?? true,
      label: json['label'] as String? ?? '',
      toolName: json['toolName'] as String? ?? '',
      targetLabelContains: json['targetLabelContains'] as String? ?? '',
      targetRole: json['targetRole'] as String? ?? '',
      targetAction: json['targetAction'] as String? ?? '',
      targetRisk: json['targetRisk'] as String? ?? '',
      appNameContains: json['appNameContains'] as String? ?? '',
      appBundleId: json['appBundleId'] as String? ?? '',
      windowTitleContains: json['windowTitleContains'] as String? ?? '',
      urlHost: json['urlHost'] as String? ?? '',
      urlStartsWith: json['urlStartsWith'] as String? ?? '',
      exactText: json['exactText'] as String? ?? '',
    );

Map<String, dynamic> _$RoutineComputerUseActionAllowlistEntryToJson(
  _RoutineComputerUseActionAllowlistEntry instance,
) => <String, dynamic>{
  'id': instance.id,
  'enabled': instance.enabled,
  'label': instance.label,
  'toolName': instance.toolName,
  'targetLabelContains': instance.targetLabelContains,
  'targetRole': instance.targetRole,
  'targetAction': instance.targetAction,
  'targetRisk': instance.targetRisk,
  'appNameContains': instance.appNameContains,
  'appBundleId': instance.appBundleId,
  'windowTitleContains': instance.windowTitleContains,
  'urlHost': instance.urlHost,
  'urlStartsWith': instance.urlStartsWith,
  'exactText': instance.exactText,
};

_McpServerConfig _$McpServerConfigFromJson(Map<String, dynamic> json) =>
    _McpServerConfig(
      url: json['url'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      type:
          $enumDecodeNullable(
            _$McpServerTypeEnumMap,
            json['type'],
            unknownValue: McpServerType.http,
          ) ??
          McpServerType.http,
      trustState:
          $enumDecodeNullable(
            _$McpServerTrustStateEnumMap,
            json['trustState'],
            unknownValue: McpServerTrustState.trusted,
          ) ??
          McpServerTrustState.trusted,
      command: json['command'] as String? ?? '',
      args:
          (json['args'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const <String>[],
      trustedAt: json['trustedAt'] == null
          ? null
          : DateTime.parse(json['trustedAt'] as String),
    );

Map<String, dynamic> _$McpServerConfigToJson(_McpServerConfig instance) =>
    <String, dynamic>{
      'url': instance.url,
      'enabled': instance.enabled,
      'type': _$McpServerTypeEnumMap[instance.type]!,
      'trustState': _$McpServerTrustStateEnumMap[instance.trustState]!,
      'command': instance.command,
      'args': instance.args,
      'trustedAt': instance.trustedAt?.toIso8601String(),
    };

const _$McpServerTypeEnumMap = {
  McpServerType.http: 'http',
  McpServerType.stdio: 'stdio',
};

const _$McpServerTrustStateEnumMap = {
  McpServerTrustState.pending: 'pending',
  McpServerTrustState.trusted: 'trusted',
  McpServerTrustState.blocked: 'blocked',
};

_ModelCapabilityProfile _$ModelCapabilityProfileFromJson(
  Map<String, dynamic> json,
) => _ModelCapabilityProfile(
  id: json['id'] as String,
  provider:
      $enumDecodeNullable(
        _$LlmProviderEnumMap,
        json['provider'],
        unknownValue: LlmProvider.openAiCompatible,
      ) ??
      LlmProvider.openAiCompatible,
  baseUrl: json['baseUrl'] as String? ?? '',
  model: json['model'] as String,
  toolCallStyle:
      $enumDecodeNullable(
        _$ModelToolCallStyleEnumMap,
        json['toolCallStyle'],
        unknownValue: ModelToolCallStyle.unknown,
      ) ??
      ModelToolCallStyle.unknown,
  structuredOutputSupport:
      $enumDecodeNullable(
        _$ModelStructuredOutputSupportEnumMap,
        json['structuredOutputSupport'],
        unknownValue: ModelStructuredOutputSupport.unknown,
      ) ??
      ModelStructuredOutputSupport.unknown,
  editFormatPreference:
      $enumDecodeNullable(
        _$ModelEditFormatPreferenceEnumMap,
        json['editFormatPreference'],
        unknownValue: ModelEditFormatPreference.unknown,
      ) ??
      ModelEditFormatPreference.unknown,
  usableContextTokens: (json['usableContextTokens'] as num?)?.toInt() ?? 0,
  probedAt: json['probedAt'] == null
      ? null
      : DateTime.parse(json['probedAt'] as String),
  probeSummary: json['probeSummary'] as String? ?? '',
  probeMetadata:
      (json['probeMetadata'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const <String, String>{},
);

Map<String, dynamic> _$ModelCapabilityProfileToJson(
  _ModelCapabilityProfile instance,
) => <String, dynamic>{
  'id': instance.id,
  'provider': _$LlmProviderEnumMap[instance.provider]!,
  'baseUrl': instance.baseUrl,
  'model': instance.model,
  'toolCallStyle': _$ModelToolCallStyleEnumMap[instance.toolCallStyle]!,
  'structuredOutputSupport':
      _$ModelStructuredOutputSupportEnumMap[instance.structuredOutputSupport]!,
  'editFormatPreference':
      _$ModelEditFormatPreferenceEnumMap[instance.editFormatPreference]!,
  'usableContextTokens': instance.usableContextTokens,
  'probedAt': instance.probedAt?.toIso8601String(),
  'probeSummary': instance.probeSummary,
  'probeMetadata': instance.probeMetadata,
};

const _$LlmProviderEnumMap = {
  LlmProvider.openAiCompatible: 'openAiCompatible',
  LlmProvider.appleFoundationModels: 'appleFoundationModels',
};

const _$ModelToolCallStyleEnumMap = {
  ModelToolCallStyle.unknown: 'unknown',
  ModelToolCallStyle.nativeToolCalls: 'nativeToolCalls',
  ModelToolCallStyle.embeddedToolTags: 'embeddedToolTags',
  ModelToolCallStyle.none: 'none',
};

const _$ModelStructuredOutputSupportEnumMap = {
  ModelStructuredOutputSupport.unknown: 'unknown',
  ModelStructuredOutputSupport.jsonSchema: 'jsonSchema',
  ModelStructuredOutputSupport.jsonObject: 'jsonObject',
  ModelStructuredOutputSupport.none: 'none',
};

const _$ModelEditFormatPreferenceEnumMap = {
  ModelEditFormatPreference.unknown: 'unknown',
  ModelEditFormatPreference.wholeFile: 'wholeFile',
  ModelEditFormatPreference.searchReplace: 'searchReplace',
  ModelEditFormatPreference.unifiedDiff: 'unifiedDiff',
};

_AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) => _AppSettings(
  llmProvider:
      $enumDecodeNullable(
        _$LlmProviderEnumMap,
        json['llmProvider'],
        unknownValue: LlmProvider.openAiCompatible,
      ) ??
      LlmProvider.openAiCompatible,
  baseUrl: json['baseUrl'] as String,
  model: json['model'] as String,
  apiKey: json['apiKey'] as String,
  temperature: (json['temperature'] as num).toDouble(),
  maxTokens: (json['maxTokens'] as num).toInt(),
  reasoningEffort:
      $enumDecodeNullable(
        _$ReasoningEffortPreferenceEnumMap,
        json['reasoningEffort'],
        unknownValue: ReasoningEffortPreference.automatic,
      ) ??
      ReasoningEffortPreference.automatic,
  memoryExtractionModel: json['memoryExtractionModel'] as String? ?? '',
  subagentModel: json['subagentModel'] as String? ?? '',
  goalSuggestionModel: json['goalSuggestionModel'] as String? ?? '',
  approvalAutoReviewModel: json['approvalAutoReviewModel'] as String? ?? '',
  googleChatWebhookUrl: json['googleChatWebhookUrl'] as String? ?? '',
  mcpUrl: json['mcpUrl'] as String? ?? '',
  mcpUrls:
      (json['mcpUrls'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  mcpServers:
      (json['mcpServers'] as List<dynamic>?)
          ?.map((e) => McpServerConfig.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <McpServerConfig>[],
  mcpEnabled: json['mcpEnabled'] as bool? ?? false,
  ttsEnabled: json['ttsEnabled'] as bool? ?? true,
  autoReadEnabled: json['autoReadEnabled'] as bool? ?? false,
  speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.5,
  voiceModeAutoStop: json['voiceModeAutoStop'] as bool? ?? true,
  whisperUrl: json['whisperUrl'] as String? ?? 'http://localhost:8080',
  voicevoxUrl: json['voicevoxUrl'] as String? ?? 'http://localhost:50021',
  voicevoxSpeakerId: (json['voicevoxSpeakerId'] as num?)?.toInt() ?? 0,
  language: json['language'] as String? ?? 'system',
  assistantMode:
      $enumDecodeNullable(
        _$AssistantModeEnumMap,
        json['assistantMode'],
        unknownValue: AssistantMode.general,
      ) ??
      AssistantMode.general,
  codingApprovalMode:
      $enumDecodeNullable(
        _$ToolApprovalModeEnumMap,
        json['codingApprovalMode'],
        unknownValue: ToolApprovalMode.defaultPermissions,
      ) ??
      ToolApprovalMode.defaultPermissions,
  chatApprovalMode:
      $enumDecodeNullable(
        _$ToolApprovalModeEnumMap,
        json['chatApprovalMode'],
        unknownValue: ToolApprovalMode.defaultPermissions,
      ) ??
      ToolApprovalMode.defaultPermissions,
  confirmFileMutations: json['confirmFileMutations'] as bool? ?? true,
  confirmLocalCommands: json['confirmLocalCommands'] as bool? ?? true,
  confirmGitWrites: json['confirmGitWrites'] as bool? ?? true,
  enableCodingVerificationFeedback:
      json['enableCodingVerificationFeedback'] as bool? ?? true,
  codingVerificationTriggerPolicy:
      $enumDecodeNullable(
        _$CodingVerificationTriggerPolicyEnumMap,
        json['codingVerificationTriggerPolicy'],
        unknownValue: CodingVerificationTriggerPolicy.onCompletionClaim,
      ) ??
      CodingVerificationTriggerPolicy.onCompletionClaim,
  codingVerificationTimeoutSeconds:
      (json['codingVerificationTimeoutSeconds'] as num?)?.toInt() ?? 90,
  codingVerificationMaxFailures:
      (json['codingVerificationMaxFailures'] as num?)?.toInt() ?? 5,
  enableAgentsMd: json['enableAgentsMd'] as bool? ?? true,
  enablePrefixStableToolLoop:
      json['enablePrefixStableToolLoop'] as bool? ?? false,
  showMemoryUpdates: json['showMemoryUpdates'] as bool? ?? false,
  enableLlmSessionLogs: json['enableLlmSessionLogs'] as bool? ?? false,
  demoMode: json['demoMode'] as bool? ?? false,
  onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
  browserToolsEnabled: json['browserToolsEnabled'] as bool? ?? false,
  disabledBuiltInTools:
      (json['disabledBuiltInTools'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  localCommandPermissionRules:
      (json['localCommandPermissionRules'] as List<dynamic>?)
          ?.map(
            (e) =>
                LocalCommandPermissionRule.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const <LocalCommandPermissionRule>[],
  routineComputerUseActionAllowlist:
      (json['routineComputerUseActionAllowlist'] as List<dynamic>?)
          ?.map(
            (e) => RoutineComputerUseActionAllowlistEntry.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList() ??
      const <RoutineComputerUseActionAllowlistEntry>[],
  modelCapabilityProfiles: json['modelCapabilityProfiles'] == null
      ? const <ModelCapabilityProfile>[]
      : _modelCapabilityProfilesFromJson(
          json['modelCapabilityProfiles'] as List?,
        ),
);

Map<String, dynamic> _$AppSettingsToJson(
  _AppSettings instance,
) => <String, dynamic>{
  'llmProvider': _$LlmProviderEnumMap[instance.llmProvider]!,
  'baseUrl': instance.baseUrl,
  'model': instance.model,
  'apiKey': instance.apiKey,
  'temperature': instance.temperature,
  'maxTokens': instance.maxTokens,
  'reasoningEffort':
      _$ReasoningEffortPreferenceEnumMap[instance.reasoningEffort]!,
  'memoryExtractionModel': instance.memoryExtractionModel,
  'subagentModel': instance.subagentModel,
  'goalSuggestionModel': instance.goalSuggestionModel,
  'approvalAutoReviewModel': instance.approvalAutoReviewModel,
  'googleChatWebhookUrl': instance.googleChatWebhookUrl,
  'mcpUrl': instance.mcpUrl,
  'mcpUrls': instance.mcpUrls,
  'mcpServers': instance.mcpServers,
  'mcpEnabled': instance.mcpEnabled,
  'ttsEnabled': instance.ttsEnabled,
  'autoReadEnabled': instance.autoReadEnabled,
  'speechRate': instance.speechRate,
  'voiceModeAutoStop': instance.voiceModeAutoStop,
  'whisperUrl': instance.whisperUrl,
  'voicevoxUrl': instance.voicevoxUrl,
  'voicevoxSpeakerId': instance.voicevoxSpeakerId,
  'language': instance.language,
  'assistantMode': _$AssistantModeEnumMap[instance.assistantMode]!,
  'codingApprovalMode': _$ToolApprovalModeEnumMap[instance.codingApprovalMode]!,
  'chatApprovalMode': _$ToolApprovalModeEnumMap[instance.chatApprovalMode]!,
  'confirmFileMutations': instance.confirmFileMutations,
  'confirmLocalCommands': instance.confirmLocalCommands,
  'confirmGitWrites': instance.confirmGitWrites,
  'enableCodingVerificationFeedback': instance.enableCodingVerificationFeedback,
  'codingVerificationTriggerPolicy':
      _$CodingVerificationTriggerPolicyEnumMap[instance
          .codingVerificationTriggerPolicy]!,
  'codingVerificationTimeoutSeconds': instance.codingVerificationTimeoutSeconds,
  'codingVerificationMaxFailures': instance.codingVerificationMaxFailures,
  'enableAgentsMd': instance.enableAgentsMd,
  'enablePrefixStableToolLoop': instance.enablePrefixStableToolLoop,
  'showMemoryUpdates': instance.showMemoryUpdates,
  'enableLlmSessionLogs': instance.enableLlmSessionLogs,
  'demoMode': instance.demoMode,
  'onboardingCompleted': instance.onboardingCompleted,
  'browserToolsEnabled': instance.browserToolsEnabled,
  'disabledBuiltInTools': instance.disabledBuiltInTools,
  'localCommandPermissionRules': instance.localCommandPermissionRules,
  'routineComputerUseActionAllowlist':
      instance.routineComputerUseActionAllowlist,
  'modelCapabilityProfiles': _modelCapabilityProfilesToJson(
    instance.modelCapabilityProfiles,
  ),
};

const _$ReasoningEffortPreferenceEnumMap = {
  ReasoningEffortPreference.automatic: 'automatic',
  ReasoningEffortPreference.low: 'low',
  ReasoningEffortPreference.medium: 'medium',
  ReasoningEffortPreference.high: 'high',
};

const _$AssistantModeEnumMap = {
  AssistantMode.general: 'general',
  AssistantMode.coding: 'coding',
  AssistantMode.plan: 'plan',
};

const _$ToolApprovalModeEnumMap = {
  ToolApprovalMode.defaultPermissions: 'defaultPermissions',
  ToolApprovalMode.autoReview: 'autoReview',
  ToolApprovalMode.fullAccess: 'fullAccess',
};

const _$CodingVerificationTriggerPolicyEnumMap = {
  CodingVerificationTriggerPolicy.onCompletionClaim: 'onCompletionClaim',
  CodingVerificationTriggerPolicy.onRequestOnly: 'onRequestOnly',
  CodingVerificationTriggerPolicy.off: 'off',
};
