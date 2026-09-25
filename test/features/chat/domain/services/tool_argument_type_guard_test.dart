import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_definitions.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_argument_type_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guard = ToolArgumentTypeGuard();
  final writeFileParameters =
      (BuiltInFilesystemToolDefinitions.writeFileTool['function']
              as Map<String, dynamic>)['parameters']
          as Map<String, dynamic>;

  ToolCallInfo call(Map<String, dynamic> arguments) =>
      ToolCallInfo(id: 'call_1', name: 'write_file', arguments: arguments);

  test('rejects a JSON object passed as write_file content', () {
    // Session e3a9f3f0: config.json content sent as an object, twice.
    final result = guard.check(
      call({
        'path': 'config.json',
        'content': {'webhook_url': 'https://example.invalid', 'limit': 20},
      }),
      writeFileParameters,
    );

    expect(result, isNotNull);
    expect(result!.isSuccess, isFalse);
    final payload = jsonDecode(result.result) as Map<String, dynamic>;
    expect(payload['code'], ToolArgumentTypeGuard.code);
    expect(payload['executed'], isFalse);
    expect(payload['result_origin'], 'malformed');
    expect(payload['argument'], 'content');
    expect(payload['expected'], 'string');
    expect(payload['received'], 'a JSON object');
    expect(payload['error'], contains('serialized JSON text'));
  });

  test('rejects a string passed for a boolean argument', () {
    final result = guard.check(
      call({'path': 'a.txt', 'content': 'x', 'create_parents': 'true'}),
      writeFileParameters,
    );

    final payload = jsonDecode(result!.result) as Map<String, dynamic>;
    expect(payload['argument'], 'create_parents');
    expect(payload['expected'], 'boolean');
    expect(payload['error'], isNot(contains('serialized JSON text')));
  });

  test('accepts well-typed, null, and undeclared arguments', () {
    expect(
      guard.check(
        call({
          'path': 'config.json',
          'content': '{"limit": 20}',
          'create_parents': true,
          'reason': null,
          'undeclared': {'any': 'shape'},
        }),
        writeFileParameters,
      ),
      isNull,
    );
  });

  test('passes through when no schema is known', () {
    expect(guard.check(call({'content': <String, dynamic>{}}), null), isNull);
  });

  test('honors a union type list and ignores unknown type names', () {
    final parameters = {
      'type': 'object',
      'properties': {
        'limit': {
          'type': ['integer', 'null'],
        },
        'custom': {'type': 'uuid'},
      },
    };

    expect(guard.check(call({'limit': 5, 'custom': 1}), parameters), isNull);
    final result = guard.check(call({'limit': 'five'}), parameters);
    final payload = jsonDecode(result!.result) as Map<String, dynamic>;
    expect(payload['expected'], 'integer');
    expect(payload['received'], 'a string');
  });
}
