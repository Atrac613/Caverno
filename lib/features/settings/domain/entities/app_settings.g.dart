// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_McpServerConfig _$McpServerConfigFromJson(Map<String, dynamic> json) =>
    _McpServerConfig(
      url: json['url'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );

Map<String, dynamic> _$McpServerConfigToJson(_McpServerConfig instance) =>
    <String, dynamic>{'url': instance.url, 'enabled': instance.enabled};

_AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) => _AppSettings(
  baseUrl: json['baseUrl'] as String,
  model: json['model'] as String,
  apiKey: json['apiKey'] as String,
  temperature: (json['temperature'] as num).toDouble(),
  maxTokens: (json['maxTokens'] as num).toInt(),
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
  confirmFileMutations: json['confirmFileMutations'] as bool? ?? true,
  confirmLocalCommands: json['confirmLocalCommands'] as bool? ?? true,
  confirmGitWrites: json['confirmGitWrites'] as bool? ?? true,
  demoMode: json['demoMode'] as bool? ?? false,
  disabledBuiltInTools:
      (json['disabledBuiltInTools'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
);

Map<String, dynamic> _$AppSettingsToJson(_AppSettings instance) =>
    <String, dynamic>{
      'baseUrl': instance.baseUrl,
      'model': instance.model,
      'apiKey': instance.apiKey,
      'temperature': instance.temperature,
      'maxTokens': instance.maxTokens,
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
      'confirmFileMutations': instance.confirmFileMutations,
      'confirmLocalCommands': instance.confirmLocalCommands,
      'confirmGitWrites': instance.confirmGitWrites,
      'demoMode': instance.demoMode,
      'disabledBuiltInTools': instance.disabledBuiltInTools,
    };

const _$AssistantModeEnumMap = {
  AssistantMode.general: 'general',
  AssistantMode.coding: 'coding',
};
