// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_tool_entity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_McpToolEntity _$McpToolEntityFromJson(Map<String, dynamic> json) =>
    _McpToolEntity(
      name: json['name'] as String,
      description: json['description'] as String,
      inputSchema: json['inputSchema'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$McpToolEntityToJson(_McpToolEntity instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'inputSchema': instance.inputSchema,
    };

_McpToolResult _$McpToolResultFromJson(Map<String, dynamic> json) =>
    _McpToolResult(
      toolName: json['toolName'] as String,
      result: json['result'] as String,
      isSuccess: json['isSuccess'] as bool,
      errorMessage: json['errorMessage'] as String?,
    );

Map<String, dynamic> _$McpToolResultToJson(_McpToolResult instance) =>
    <String, dynamic>{
      'toolName': instance.toolName,
      'result': instance.result,
      'isSuccess': instance.isSuccess,
      'errorMessage': instance.errorMessage,
    };
