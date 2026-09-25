import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

/// Rejects a built-in tool call whose arguments do not match the JSON types
/// its schema declares, before any handler reads them.
///
/// Handlers read arguments with casts such as `arguments['content'] as
/// String?`, and a thrown cast ends the whole turn with the call unexecuted.
/// In session e3a9f3f0 a model passed `write_file` a JSON object as `content`
/// for a config.json twice; each attempt ended the turn and the file was never
/// written. A structured failure lets the model correct the call instead.
///
/// Only rejects. Coercing a value would guess at what the model meant.
final class ToolArgumentTypeGuard {
  const ToolArgumentTypeGuard();

  static const String code = 'invalid_tool_argument_type';

  /// Returns a failed result for the first mistyped argument, or null.
  ///
  /// [parameters] is the tool's JSON-schema `parameters` object. Arguments the
  /// schema does not declare, `null` values, and properties without a simple
  /// `type` are left for the handler to judge.
  McpToolResult? check(
    ToolCallInfo toolCall,
    Map<String, dynamic>? parameters,
  ) {
    final properties = parameters?['properties'];
    if (properties is! Map) return null;
    for (final entry in toolCall.arguments.entries) {
      final value = entry.value;
      if (value == null) continue;
      final property = properties[entry.key];
      if (property is! Map) continue;
      final expected = _declaredTypes(property['type']);
      if (expected.isEmpty || expected.any((type) => _matches(type, value))) {
        continue;
      }
      return _failure(toolCall.name, entry.key, expected, value);
    }
    return null;
  }

  static List<String> _declaredTypes(Object? type) => switch (type) {
    final String single => [single],
    final List<Object?> many => [...many.whereType<String>()],
    _ => const [],
  };

  static bool _matches(String type, Object value) => switch (type) {
    'string' => value is String,
    'boolean' => value is bool,
    'integer' => value is int,
    'number' => value is num,
    'array' => value is List,
    'object' => value is Map,
    'null' => false,
    // An unknown schema type is not ours to enforce.
    _ => true,
  };

  static String _describe(Object value) => switch (value) {
    Map() => 'a JSON object',
    List() => 'a JSON array',
    String() => 'a string',
    bool() => 'a boolean',
    num() => 'a number',
    _ => 'a ${value.runtimeType}',
  };

  static McpToolResult _failure(
    String toolName,
    String argument,
    List<String> expected,
    Object value,
  ) {
    final expectedText = expected.where((type) => type != 'null').join(' or ');
    final received = _describe(value);
    final hint = expected.contains('string') && (value is Map || value is List)
        ? ' To write JSON, pass the serialized JSON text as the string.'
        : '';
    final error =
        '$toolName argument "$argument" must be $expectedText, but '
        '$received was sent. Nothing was executed.$hint';
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        'code': code,
        ...ToolResultOrigin.malformed.marker,
        'executed': false,
        'argument': argument,
        'expected': expectedText,
        'received': received,
        'error': error,
      }),
      isSuccess: false,
      errorMessage: error,
    );
  }
}
