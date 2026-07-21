import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_tool_result_pruner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Message message(String id, String content) => Message(
    id: id,
    content: content,
    role: MessageRole.user,
    timestamp: DateTime(2026, 7, 21),
  );

  String section(String name, Map<String, dynamic> arguments, Object result) {
    final payload = result is String ? result : jsonEncode(result);
    return '[Tool: $name]\n'
        'Arguments: ${jsonEncode(arguments)}\n'
        'Result:\n'
        '$payload';
  }

  test('summarizes key arguments and parsed outcomes', () {
    final result = ConversationToolResultPruner.prune([
      message(
        'results',
        [
          section(
            'local_execute_command',
            {'command': 'flutter test'},
            {'exit_code': 0, 'stdout': 'one\ntwo\nthree'},
          ),
          section(
            'read_file',
            {'path': 'lib/main.dart', 'offset': 20},
            {'content': 'class App {}'},
          ),
          section(
            'search_files',
            {'query': 'preflightEditFile'},
            {'match_count': 4, 'matches': []},
          ),
        ].join('\n\n'),
      ),
    ]);

    final content = result.messages.single.content;
    expect(
      content,
      contains(
        '[local_execute_command] `flutter test` -> exit 0, 3 output lines',
      ),
    );
    expect(
      content,
      contains('[read_file] lib/main.dart from line 21 -> 12 content chars'),
    );
    expect(
      content,
      contains('[search_files] "preflightEditFile" -> 4 results'),
    );
    expect(result.summarizedResultCount, 3);
    expect(result.duplicateResultCount, 0);
  });

  test('marks older exact duplicates and keeps the newer outcome', () {
    final duplicate = section(
      'read_file',
      {'path': 'lib/app.dart'},
      {'content': 'same file body'},
    );

    final result = ConversationToolResultPruner.prune([
      message('older', duplicate),
      message('newer', duplicate),
    ]);

    expect(
      result.messages.first.content,
      contains('duplicate of later result; 14 content chars'),
    );
    expect(result.messages.last.content, isNot(contains('duplicate')));
    expect(result.duplicateResultCount, 1);
    expect(result.savedCharacterCount, greaterThan(0));
  });

  test('preserves malformed sections and unrelated messages', () {
    final malformed = message(
      'malformed',
      '[Tool: edit_file]\nArguments: {not-json}\nNo result marker',
    );
    final unrelated = message('plain', 'Keep this message exactly.');

    final result = ConversationToolResultPruner.prune([malformed, unrelated]);

    expect(result.messages[0], malformed);
    expect(result.messages[1], unrelated);
    expect(result.summarizedResultCount, 0);
  });

  test('preserves user prose that only resembles a rendered result', () {
    final pasted = message(
      'pasted',
      'Please inspect this example:\n'
          '[Tool: read_file]\n'
          'Arguments: {"path":"README.md"}\n'
          'Result:\n'
          '{"content":"example"}',
    );

    final result = ConversationToolResultPruner.prune([pasted]);

    expect(result.messages.single, pasted);
    expect(result.summarizedResultCount, 0);
  });

  test('falls back safely for invalid result JSON', () {
    final result = ConversationToolResultPruner.prune([
      message(
        'raw',
        section('read_file', {'path': 'README.md'}, 'plain file contents'),
      ),
    ]);

    expect(
      result.messages.single.content,
      '[read_file] README.md -> 19 content chars',
    );
  });
}
