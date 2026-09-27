import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

/// The call to dispatch, with arguments normalized where that was lossless, or
/// the failure to return instead of dispatching.
final class ToolArgumentCheck {
  const ToolArgumentCheck._(this.toolCall, this.failure);

  final ToolCallInfo toolCall;
  final McpToolResult? failure;
}

/// Matches a built-in tool call's arguments to the JSON types its schema
/// declares, before any handler reads them.
///
/// Handlers read arguments with casts such as `arguments['content'] as
/// String?`, and a thrown cast ends the whole turn with the call unexecuted.
/// In session e3a9f3f0 a model passed `write_file` a JSON object as `content`
/// for a config.json twice. JSON file content can be serialized before any
/// policy or approval sees the call; other file types still require text.
///
/// A string that is exactly the JSON text of the declared type is decoded:
/// the model's tool-call serializer sometimes stringifies nested values, and
/// in session 42f1b8d5 it sent `ask_user_question` an options array as JSON
/// text and `allow_other` as "True", could not produce anything else, and the
/// turn aborted on the repeat. Decoding reads the value; it does not guess at
/// one. Anything else is rejected with a structured failure the model can act
/// on.
///
/// None of the stringified `options` the model has actually sent was exact
/// JSON: all 8 in the corpus were a complete array followed by more text. In 3
/// the text was only a stray `}` (session b41b57fa). The value is complete and
/// the closer holds nothing, so it is decoded. In the other 5 the text was the
/// rest of the arguments object (`], "allow_other": true}`). That text holds
/// values, so the call is rejected and the error names the trailing text.
/// "a string was sent" alone told the model nothing it could see: it re-sent
/// identical bytes and the turn aborted.
final class ToolArgumentTypeGuard {
  const ToolArgumentTypeGuard();

  static const String code = 'invalid_tool_argument_type';

  static final RegExp _integerText = RegExp(r'^-?\d+$');

  /// [parameters] is the tool's JSON-schema `parameters` object. Arguments the
  /// schema does not declare, `null` values, and properties without a simple
  /// `type` are left for the handler to judge.
  ToolArgumentCheck check(
    ToolCallInfo toolCall,
    Map<String, dynamic>? parameters,
  ) {
    final properties = parameters?['properties'];
    if (properties is! Map) return ToolArgumentCheck._(toolCall, null);
    Map<String, dynamic>? decoded;
    for (final entry in toolCall.arguments.entries) {
      final value = entry.value;
      if (value == null) continue;
      final property = properties[entry.key];
      if (property is! Map) continue;
      final expected = _declaredTypes(property['type']);
      if (expected.isEmpty || expected.any((type) => _matches(type, value))) {
        continue;
      }
      final replacement = value is String
          ? _decode(value, expected)
          : _encodeJsonWriteContent(toolCall, entry.key, value, expected);
      if (replacement == null) {
        return ToolArgumentCheck._(
          toolCall,
          _failure(
            toolCall.name,
            entry.key,
            expected,
            value,
            trailing: value is String
                ? _trailingAfterJson(value, expected)
                : null,
          ),
        );
      }
      (decoded ??= {...toolCall.arguments})[entry.key] = replacement;
    }
    if (decoded == null) return ToolArgumentCheck._(toolCall, null);
    return ToolArgumentCheck._(
      ToolCallInfo(id: toolCall.id, name: toolCall.name, arguments: decoded),
      null,
    );
  }

  static List<String> _declaredTypes(Object? type) => switch (type) {
    final String single => [single],
    final List<Object?> many => [...many.whereType<String>()],
    _ => const [],
  };

  static String? _encodeJsonWriteContent(
    ToolCallInfo toolCall,
    String argument,
    Object value,
    List<String> expected,
  ) {
    if (toolCall.name != 'write_file' ||
        argument != 'content' ||
        !expected.contains('string') ||
        (value is! Map && value is! List)) {
      return null;
    }
    final path = toolCall.arguments['path'];
    if (path is! String || !path.toLowerCase().endsWith('.json')) {
      return null;
    }
    try {
      return jsonEncode(value);
    } on JsonUnsupportedObjectError {
      return null;
    }
  }

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

  /// The value [text] is the JSON text of, when that value has one of the
  /// [expected] types; otherwise null.
  static Object? _decode(String text, List<String> expected) {
    final trimmed = text.trim();
    for (final type in expected) {
      final value = switch (type) {
        'array' || 'object' => _jsonValue(trimmed),
        'boolean' => switch (trimmed.toLowerCase()) {
          'true' => true,
          'false' => false,
          _ => null,
        },
        'integer' =>
          _integerText.hasMatch(trimmed) ? int.tryParse(trimmed) : null,
        'number' => num.tryParse(trimmed),
        _ => null,
      };
      if (value != null && _matches(type, value)) return value;
    }
    return null;
  }

  static Object? _jsonValue(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      final leading = _leadingJson(text);
      if (leading == null || !_onlyClosers.hasMatch(leading.rest)) return null;
      return leading.value;
    }
  }

  static final RegExp _onlyClosers = RegExp(r'^[\s}\]]+$');

  /// The complete JSON array or object [text] starts with, and the text after
  /// it; null when [text] does not start with one.
  static ({Object? value, String rest})? _leadingJson(String text) {
    if (text.isEmpty || (text[0] != '[' && text[0] != '{')) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '[' || char == '{') {
        depth++;
      } else if (char == ']' || char == '}') {
        depth--;
        if (depth == 0) {
          try {
            return (
              value: jsonDecode(text.substring(0, index + 1)),
              rest: text.substring(index + 1),
            );
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// The text after a complete JSON value of an [expected] container type
  /// that [text] starts with, or null when there is no such value.
  static String? _trailingAfterJson(String text, List<String> expected) {
    final leading = _leadingJson(text.trim());
    if (leading == null) return null;
    final type = switch (leading.value) {
      List() => 'array',
      Map() => 'object',
      _ => null,
    };
    if (type == null || !expected.contains(type)) return null;
    final rest = leading.rest.trim();
    return rest.isEmpty ? null : rest;
  }

  static const int _maxTrailingPreview = 120;

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
    Object value, {
    String? trailing,
  }) {
    final expectedText = expected.where((type) => type != 'null').join(' or ');
    final received = _describe(value);
    final hint = expected.contains('string') && (value is Map || value is List)
        ? ' To write JSON, pass the serialized JSON text as the string.'
        : '';
    final preview = trailing == null
        ? null
        : trailing.length <= _maxTrailingPreview
        ? trailing
        : '${trailing.substring(0, _maxTrailingPreview)}...';
    final detail = preview == null
        ? ''
        : ' The string holds a complete JSON $expectedText followed by '
              '`$preview`, which is not part of it. Send "$argument" as the '
              '$expectedText alone, and pass any other argument as its own '
              'argument.';
    final error =
        '$toolName argument "$argument" must be $expectedText, but '
        '$received was sent.$detail Nothing was executed.$hint';
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
        'trailing_text': ?preview,
        'error': error,
      }),
      isSuccess: false,
      errorMessage: error,
    );
  }
}
