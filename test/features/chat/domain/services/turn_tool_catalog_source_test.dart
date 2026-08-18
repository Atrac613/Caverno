import 'package:caverno/features/chat/domain/services/turn_tool_catalog_cache.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_catalog_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Map<String, dynamic>> definitions(List<String> names) => [
    for (final name in names)
      {
        'type': 'function',
        'function': {'name': name},
      },
  ];

  List<String> namesOf(List<Map<String, dynamic>> tools) => [
    for (final tool in tools)
      ((tool['function'] as Map<String, dynamic>)['name'] as String),
  ];

  test('a selection that grows during a blink keeps the whole catalogue', () {
    // Session d904b342: the selection grew (every executed tool adds its name),
    // so the loop missed the per-selection cache and rebuilt while the same ten
    // search and network tools were briefly absent, then kept the short list
    // for the rest of the turn.
    final cache = TurnToolCatalogCache();
    final source = TurnToolCatalogSource();
    var reads = 0;
    List<Map<String, dynamic>> liveCatalogue() {
      reads += 1;
      return reads == 1
          ? definitions(['read_file', 'git_execute_command', 'search_web'])
          : definitions(['read_file', 'git_execute_command']);
    }

    List<Map<String, dynamic>> resolveFor(Set<String> selection) =>
        cache.resolve(
          selection: selection,
          compute: () => source.read(liveCatalogue),
        );

    final opening = resolveFor({'read_file'});
    final afterFirstTool = resolveFor({'read_file', 'git_execute_command'});

    expect(namesOf(opening), [
      'read_file',
      'git_execute_command',
      'search_web',
    ]);
    expect(
      namesOf(afterFirstTool),
      namesOf(opening),
      reason: 'a blink between two selections must not rewrite the prefix',
    );
    expect(cache.computeCount, 2, reason: 'the filtering still reruns');
    expect(source.readCount, 1);
    expect(reads, 1);
  });

  test('the live catalogue is read once and then reused', () {
    final source = TurnToolCatalogSource();
    var reads = 0;
    List<Map<String, dynamic>> liveCatalogue() {
      reads += 1;
      return definitions(['read_file']);
    }

    final first = source.read(liveCatalogue);
    final second = source.read(liveCatalogue);

    expect(identical(first, second), isTrue);
    expect(reads, 1);
    expect(source.readCount, 1);
  });

  test('an empty catalogue is still a snapshot, not a retry', () {
    final source = TurnToolCatalogSource();
    var reads = 0;
    List<Map<String, dynamic>> liveCatalogue() {
      reads += 1;
      return definitions(const []);
    }

    source.read(liveCatalogue);
    source.read(liveCatalogue);

    expect(reads, 1);
  });
}
