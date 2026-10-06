import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/sticky_tool_result_policy.dart';
import 'package:test/test.dart';

const _policy = StickyToolResultPolicy();

ToolResultInfo _answeredAsk(String question, {String id = 'a'}) =>
    ToolResultInfo(
      id: id,
      name: 'ask_user_question',
      arguments: {'question': question},
      result: '{"status":"answered","question":"$question","answer":"Watcher"}',
    );

// The type guard's failure shape, as session b41b57fa logged it.
ToolResultInfo _rejectedAsk(String question, {String id = 'x'}) =>
    ToolResultInfo(
      id: id,
      name: 'ask_user_question',
      arguments: {'question': question, 'options': '[]}'},
      result:
          '{"ok":false,"code":"invalid_tool_argument_type",'
          '"executed":false,"argument":"options"}',
    );

ToolResultInfo _read(String path) => ToolResultInfo(
  id: 'r',
  name: 'read_file',
  arguments: {'path': path},
  result: '{"path":"$path","content":"x"}',
);

List<String> _ids(List<ToolResultInfo> results) =>
    results.map((result) => result.id).toList();

void main() {
  group('StickyToolResultPolicy', () {
    test('a rejected question does not supersede the answered one', () {
      final answered = _answeredAsk('which project?');
      final rejected = _rejectedAsk('which direction?');

      final resolved = _policy.resolve(
        batchToolResults: [rejected],
        executedToolResults: [answered, rejected],
      );

      expect(_ids(resolved), ['a', 'x']);
    });

    test('a rejected question is not carried as history', () {
      final rejected = _rejectedAsk('which project?');
      final answered = _answeredAsk('which project?');
      final read = _read('watcher.py');

      final resolved = _policy.resolve(
        batchToolResults: [read],
        executedToolResults: [rejected, answered, read],
      );

      expect(_ids(resolved), ['a', 'r']);
    });

    test('a newly answered question still supersedes the older answer', () {
      final older = _answeredAsk('which project?', id: 'old');
      final newer = _answeredAsk('which direction?', id: 'new');

      final resolved = _policy.resolve(
        batchToolResults: [newer],
        executedToolResults: [older, newer],
      );

      expect(_ids(resolved), ['new']);
    });

    test('keeps a non-JSON sticky result, such as a load_skill error', () {
      final skillError = ToolResultInfo(
        id: 's',
        name: 'load_skill',
        arguments: {'name': 'bump'},
        result: 'Error: No matching enabled skill found',
      );
      final read = _read('pubspec.yaml');

      final resolved = _policy.resolve(
        batchToolResults: [read],
        executedToolResults: [skillError, read],
      );

      expect(_ids(resolved), ['s', 'r']);
    });
  });
}
