import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/successful_read_result_replay_cache.dart';

void main() {
  ToolCallInfo read(
    String id,
    String path, {
    String? reason,
    int? offset,
    int? limit,
  }) {
    return ToolCallInfo(
      id: id,
      name: 'read_file',
      arguments: {
        'path': path,
        'reason': ?reason,
        'offset': ?offset,
        'limit': ?limit,
      },
    );
  }

  String? resolvePath(String path) => path.startsWith('/')
      ? path
      : '/workspace/${path.replaceFirst(RegExp(r'^\./'), '')}';

  test('replays a successful semantic read in the same generations', () {
    final cache = SuccessfulReadResultReplayCache();
    cache.record(
      toolCall: read('first', 'lib/main.dart', reason: 'inspect'),
      result: '{"content":"void main() {}"}',
      isSuccess: true,
      interactionGeneration: 4,
      mutationGeneration: 2,
      resolveProjectPath: resolvePath,
    );

    final replay = cache.lookup(
      toolCall: read(
        'second',
        '/workspace/lib/main.dart',
        reason: 'double-check',
      ),
      interactionGeneration: 4,
      mutationGeneration: 2,
      resolveProjectPath: resolvePath,
    );

    expect(replay, '{"content":"void main() {}"}');
  });

  test('misses after a mutation generation change', () {
    final cache = SuccessfulReadResultReplayCache();
    cache.record(
      toolCall: read('first', 'lib/main.dart'),
      result: 'old',
      isSuccess: true,
      interactionGeneration: 4,
      mutationGeneration: 2,
    );

    expect(
      cache.lookup(
        toolCall: read('second', 'lib/main.dart'),
        interactionGeneration: 4,
        mutationGeneration: 3,
      ),
      isNull,
    );
  });

  test('misses in a new interaction generation', () {
    final cache = SuccessfulReadResultReplayCache();
    cache.record(
      toolCall: read('first', 'lib/main.dart'),
      result: 'old',
      isSuccess: true,
      interactionGeneration: 4,
      mutationGeneration: 2,
    );

    expect(
      cache.lookup(
        toolCall: read('second', 'lib/main.dart'),
        interactionGeneration: 5,
        mutationGeneration: 2,
      ),
      isNull,
    );
  });

  test('does not cache failed reads or non-read tools', () {
    final cache = SuccessfulReadResultReplayCache();
    final failedRead = read('first', 'lib/main.dart');
    cache.record(
      toolCall: failedRead,
      result: 'not found',
      isSuccess: false,
      interactionGeneration: 4,
      mutationGeneration: 2,
    );
    cache.record(
      toolCall: ToolCallInfo(
        id: 'list',
        name: 'list_directory',
        arguments: {'path': 'lib'},
      ),
      result: 'listing',
      isSuccess: true,
      interactionGeneration: 4,
      mutationGeneration: 2,
    );

    expect(
      cache.lookup(
        toolCall: read('second', 'lib/main.dart'),
        interactionGeneration: 4,
        mutationGeneration: 2,
      ),
      isNull,
    );
  });

  test('keeps offset and limit as semantic cache arguments', () {
    final cache = SuccessfulReadResultReplayCache();
    cache.record(
      toolCall: read('first', 'large.log', offset: 10, limit: 20),
      result: 'page',
      isSuccess: true,
      interactionGeneration: 4,
      mutationGeneration: 2,
    );

    expect(
      cache.lookup(
        toolCall: read('second', 'large.log', offset: 30, limit: 20),
        interactionGeneration: 4,
        mutationGeneration: 2,
      ),
      isNull,
    );
  });
}
