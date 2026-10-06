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

  test('serializes JSON object content for write_file', () {
    // Session e3a9f3f0: config.json content sent as an object, twice.
    final original = call({
      'path': 'config.json',
      'content': {'webhook_url': 'https://example.invalid', 'limit': 20},
    });
    final checked = guard.check(original, writeFileParameters);

    expect(checked.failure, isNull);
    expect(checked.toolCall.id, original.id);
    expect(jsonDecode(checked.toolCall.arguments['content'] as String), {
      'webhook_url': 'https://example.invalid',
      'limit': 20,
    });
    expect(original.arguments['content'], isA<Map>());
  });

  test('serializes JSON array content for write_file', () {
    final checked = guard.check(
      call({
        'path': 'CONFIG.JSON',
        'content': [
          1,
          {'enabled': true},
        ],
      }),
      writeFileParameters,
    );

    expect(checked.failure, isNull);
    expect(jsonDecode(checked.toolCall.arguments['content'] as String), [
      1,
      {'enabled': true},
    ]);
  });

  test('rejects structured content for non-JSON files and other tools', () {
    for (final path in ['config.yaml', 'script.py', 'config.jsonl']) {
      final result = guard.check(
        call({
          'path': path,
          'content': {'limit': 20},
        }),
        writeFileParameters,
      );
      expect(result.failure, isNotNull, reason: path);
      final payload =
          jsonDecode(result.failure!.result) as Map<String, dynamic>;
      expect(payload['code'], ToolArgumentTypeGuard.code);
      expect(payload['executed'], isFalse);
    }

    final otherTool = ToolCallInfo(
      id: 'call_2',
      name: 'edit_file',
      arguments: const {
        'path': 'config.json',
        'content': {'limit': 20},
      },
    );
    expect(guard.check(otherTool, writeFileParameters).failure, isNotNull);
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
    // Session 42f1b8d5 sent allow_other as "True"; exact JSON text for the
    // containers is the contract, not a logged payload (see below).
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

  // Payloads below are copied verbatim from session b41b57fa's log. All 8
  // stringified `options` in the corpus were one of these two shapes.
  final askParameters = {
    'properties': {
      'options': {'type': 'array'},
      'allow_other': {'type': 'boolean'},
    },
  };
  ToolCallInfo ask(Object options) => ToolCallInfo(
    id: 'call_ask',
    name: 'ask_user_question',
    arguments: {'question': 'q', 'options': options, 'allow_other': 'True'},
  );

  test('decodes a complete array followed only by a stray closer', () {
    const options =
        r'[{"id": "robustness", "label": "堅牢性・運用強化", "description": "リトライ/バックオフ、レート制限、エラー時の通知、ログ、cron/launchd 化、ヘルスチェック。"}, {"id": "features", "label": "機能拡張", "description": "価格変動検知、複数クエリごとのフィルタ（価格帯/状態）、通知のバッチ化、画像添付。"}, {"id": "api", "label": "取得手段の強化", "description": "非公式APIの安定化、公式API/スクレイピングへの対応、ヘッダ/セッション管理。"}, {"id": "quality", "label": "品質・テスト", "description": "ユニットテスト、型チェック、CI、ドキュメント整備。"}]}';

    final checked = guard.check(ask(options), askParameters);

    expect(checked.failure, isNull);
    final decoded = checked.toolCall.arguments['options'] as List;
    expect(decoded, hasLength(4));
    expect((decoded.first as Map)['id'], 'robustness');
    expect(checked.toolCall.arguments['allow_other'], isTrue);
  });

  test('rejects an array followed by more arguments and names the text', () {
    const options =
        r'[{"id": "watcher", "label": "Watcher (Mercari 在庫監視)", "description": "現在の作業プロジェクト。Mercari の在庫監視スクリプトの今後の機能計画。"}, {"id": "caverno", "label": "Caverno (iOS/macOS チャットクライアント)", "description": "Flutter 製チャットクライアントのロードマップ。"}, {"id": "other", "label": "その他", "description": "gs1_flutter_app、agent-kb、herpes など別のプロジェクト。"}], "allow_other": true, "other_placeholder": "プロジェクト名や目的を記入"}]';

    final failure = guard.check(ask(options), askParameters).failure;

    expect(failure, isNotNull);
    final payload = jsonDecode(failure!.result) as Map<String, dynamic>;
    expect(payload['argument'], 'options');
    expect(payload['executed'], isFalse);
    expect(payload['trailing_text'], startsWith(', "allow_other": true'));
    expect(payload['error'], contains('a complete JSON array followed by'));
    expect(payload['error'], contains('"options" as the array alone'));
  });

  test('names no trailing text when the string is not JSON at all', () {
    final failure = guard
        .check(ask('robustness, features'), askParameters)
        .failure;

    final payload = jsonDecode(failure!.result) as Map<String, dynamic>;
    expect(payload.containsKey('trailing_text'), isFalse);
    expect(payload['error'], isNot(contains('followed by')));
  });

  test('keeps rejecting a closer that leaves the value incomplete', () {
    expect(guard.check(ask('[{"id": "a"}'), askParameters).failure, isNotNull);
    expect(
      guard.check(ask('[{"id": "a"}]] extra'), askParameters).failure,
      isNotNull,
    );
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
