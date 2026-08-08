import 'package:caverno/features/chat/domain/services/turn_tool_catalog_cache.dart';
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

  test('a blinking catalogue cannot shrink the request mid-loop', () {
    // Session 6035277f: the same ten MCP tools vanished and came back across
    // one turn. The selection never changed, so neither may the catalogue.
    final cache = TurnToolCatalogCache();
    final selection = {'read_file', 'search_web'};
    var reads = 0;
    List<Map<String, dynamic>> liveCatalogue() {
      reads += 1;
      return reads.isOdd
          ? definitions(['read_file', 'search_web'])
          : definitions(['read_file']);
    }

    final first = cache.resolve(selection: selection, compute: liveCatalogue);
    final second = cache.resolve(selection: selection, compute: liveCatalogue);
    final third = cache.resolve(selection: selection, compute: liveCatalogue);

    expect(namesOf(first), ['read_file', 'search_web']);
    expect(namesOf(second), ['read_file', 'search_web']);
    expect(namesOf(third), ['read_file', 'search_web']);
    expect(cache.computeCount, 1);
    expect(reads, 1, reason: 'the live catalogue is read once per selection');
  });

  test('a grown selection gets a fresh catalogue', () {
    // tool_search discovering a tool is the one case where the loop does want
    // a new catalogue.
    final cache = TurnToolCatalogCache();
    var reads = 0;
    List<Map<String, dynamic>> liveCatalogue() {
      reads += 1;
      return definitions(['read_file', 'search_web']);
    }

    cache.resolve(selection: {'read_file'}, compute: liveCatalogue);
    cache.resolve(
      selection: {'read_file', 'search_web'},
      compute: liveCatalogue,
    );

    expect(cache.computeCount, 2);
    expect(reads, 2);
  });

  test('selection order does not create a second catalogue', () {
    final cache = TurnToolCatalogCache();
    var reads = 0;
    List<Map<String, dynamic>> liveCatalogue() {
      reads += 1;
      return definitions(['a', 'b']);
    }

    cache.resolve(selection: {'a', 'b'}, compute: liveCatalogue);
    cache.resolve(selection: {'b', 'a'}, compute: liveCatalogue);

    expect(cache.computeCount, 1);
    expect(reads, 1);
  });

  test('an empty selection is cached like any other', () {
    final cache = TurnToolCatalogCache();
    var reads = 0;
    List<Map<String, dynamic>> liveCatalogue() {
      reads += 1;
      return definitions(const []);
    }

    cache.resolve(selection: const {}, compute: liveCatalogue);
    cache.resolve(selection: const {}, compute: liveCatalogue);

    expect(cache.computeCount, 1);
    expect(reads, 1);
  });

  test('a returning selection reuses its own catalogue', () {
    final cache = TurnToolCatalogCache();
    List<Map<String, dynamic>> liveCatalogue() => definitions(['read_file']);

    cache.resolve(selection: {'read_file'}, compute: liveCatalogue);
    cache.resolve(selection: {'read_file', 'x'}, compute: liveCatalogue);
    cache.resolve(selection: {'read_file'}, compute: liveCatalogue);

    expect(cache.computeCount, 2);
  });
}
