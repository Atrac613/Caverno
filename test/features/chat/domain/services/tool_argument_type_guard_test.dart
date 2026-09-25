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
    final result = guard
        .check(
          call({
            'path': 'config.json',
            'content': {'webhook_url': 'https://example.invalid', 'limit': 20},
          }),
          writeFileParameters,
        )
        .failure;

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

  test('rejects a string that is not the JSON text of the declared type', () {
    final result = guard
        .check(
          call({'path': 'a.txt', 'content': 'x', 'create_parents': 'yes'}),
          writeFileParameters,
        )
        .failure;

    final payload = jsonDecode(result!.result) as Map<String, dynamic>;
    expect(payload['argument'], 'create_parents');
    expect(payload['expected'], 'boolean');
    expect(payload['error'], isNot(contains('serialized JSON text')));
  });

  test('decodes stringified values of the declared type', () {
    // Session 42f1b8d5: options as JSON text and allow_other as "True".
    final parameters = {
      'type': 'object',
      'properties': {
        'options': {'type': 'array'},
        'allow_other': {'type': 'boolean'},
        'limit': {'type': 'integer'},
        'ratio': {'type': 'number'},
        'filter': {'type': 'object'},
      },
    };
    final original = ToolCallInfo(
      id: 'call_9',
      name: 'ask_user_question',
      arguments: {
        'options': '[{"id": "a", "label": "A"}]',
        'allow_other': 'True',
        'limit': ' 5 ',
        'ratio': '0.5',
        'filter': '{"k": 1}',
      },
    );

    final checked = guard.check(original, parameters);

    expect(checked.failure, isNull);
    expect(checked.toolCall.id, 'call_9');
    expect(checked.toolCall.arguments, {
      'options': [
        {'id': 'a', 'label': 'A'},
      ],
      'allow_other': true,
      'limit': 5,
      'ratio': 0.5,
      'filter': {'k': 1},
    });
    expect(original.arguments['allow_other'], 'True');
  });

  test('rejects JSON text of the wrong shape', () {
    final parameters = {
      'properties': {
        'options': {'type': 'array'},
        'limit': {'type': 'integer'},
      },
    };

    expect(
      guard.check(call({'options': '{"a": 1}'}), parameters).failure,
      isNotNull,
    );
    expect(
      guard.check(call({'options': '[1,'}), parameters).failure,
      isNotNull,
    );
    expect(guard.check(call({'limit': '5.5'}), parameters).failure, isNotNull);
  });

  test('accepts well-typed, null, and undeclared arguments', () {
    final arguments = {
      'path': 'config.json',
      'content': '{"limit": 20}',
      'create_parents': true,
      'reason': null,
      'undeclared': {'any': 'shape'},
    };
    final original = call(arguments);
    final checked = guard.check(original, writeFileParameters);
    expect(checked.failure, isNull);
    expect(identical(checked.toolCall, original), isTrue);
  });

  test('passes through when no schema is known', () {
    expect(
      guard.check(call({'content': <String, dynamic>{}}), null).failure,
      isNull,
    );
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

    expect(
      guard.check(call({'limit': 5, 'custom': 1}), parameters).failure,
      isNull,
    );
    final result = guard.check(call({'limit': 'five'}), parameters).failure;
    final payload = jsonDecode(result!.result) as Map<String, dynamic>;
    expect(payload['expected'], 'integer');
    expect(payload['received'], 'a string');
  });
}
