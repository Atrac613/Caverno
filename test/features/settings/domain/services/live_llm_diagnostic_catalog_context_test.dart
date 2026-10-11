import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_catalog_context.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> tool(String name, {Object? remote}) => {
  'type': 'function',
  'function': {'name': name, 'description': 'fixture'},
  McpToolEntity.openAiExternalToolKey: ?remote,
};

LiveLlmDiagnosticCatalogContext build(List<Map<String, dynamic>> definitions) =>
    LiveLlmDiagnosticCatalogContext.fromDefinitions(
      definitions,
      remoteServerCount: 2,
      connectionSummary: 'state\nerror',
    );

void main() {
  test('empty availability snapshot retains summary and zero counts', () {
    final context = LiveLlmDiagnosticCatalogContext.empty('unavailable');
    expect(context.definitions, isEmpty);
    expect(context.initialDefinitions, isEmpty);
    expect(context.selectedToolNames, isEmpty);
    expect(context.toolSearchEnabled, false);
    expect(context.catalog.totalToolCount, 0);
    expect(context.catalog.initialToolCount, 0);
    expect(context.catalog.remoteToolCount, 0);
    expect(context.catalog.remoteServerCount, 0);
    expect(context.catalog.mcpConnectionSummary, 'unavailable');
  });

  test('acquired empty catalog still reports configured servers and state', () {
    final context = build([]);
    expect(context.catalog.totalToolCount, 0);
    expect(context.catalog.remoteServerCount, 2);
    expect(context.catalog.mcpConnectionSummary, 'state\nerror');
    expect(context.initialDefinitions, isEmpty);
    expect(context.toolSearchEnabled, false);
  });

  test(
    'raw order and duplicates survive while initial selection deduplicates',
    () {
      final first = tool('z_remote', remote: true);
      final duplicate = tool('z_remote', remote: true);
      final definitions = [
        first,
        tool('get_current_datetime'),
        duplicate,
        <String, dynamic>{'type': 'function'},
      ];
      final context = build(definitions);
      expect(context.definitions, same(definitions));
      expect(context.catalog.totalToolCount, 4);
      expect(context.catalog.toolNames, [
        'z_remote',
        'get_current_datetime',
        'z_remote',
      ]);
      expect(context.catalog.remoteToolNames, ['z_remote', 'z_remote']);
      expect(context.catalog.remoteToolCount, 2);
      expect(context.catalog.initialToolCount, 2);
      expect(context.catalog.initialToolNames, [
        'z_remote',
        'get_current_datetime',
      ]);
      expect(context.initialDefinitions.first, same(first));
      expect(context.selectedToolNames, {'z_remote', 'get_current_datetime'});
      expect(context.toolSearchEnabled, false);
    },
  );

  test('remote marker must be boolean true and missing names are omitted', () {
    final context = build([
      tool('bool', remote: true),
      tool('string', remote: 'true'),
      tool('false', remote: false),
      {'type': 'function', McpToolEntity.openAiExternalToolKey: true},
    ]);
    expect(context.catalog.remoteToolNames, ['bool']);
    expect(context.catalog.remoteToolCount, 1);
    expect(context.catalog.totalToolCount, 4);
    expect(context.catalog.toolNames, ['bool', 'string', 'false']);
  });

  for (final count in [24, 25]) {
    test('tool search threshold is strictly above 24: $count', () {
      final definitions = [
        tool('get_current_datetime'),
        for (var i = 1; i < count; i++) tool('deferred_$i'),
      ];
      final context = build(definitions);
      final enabled = count == 25;
      expect(context.catalog.totalToolCount, count);
      expect(context.toolSearchEnabled, enabled);
      expect(context.catalog.toolSearchEnabled, enabled);
      expect(context.catalog.initialToolCount, enabled ? 2 : 24);
      expect(
        context.catalog.initialToolNames,
        enabled
            ? ['tool_search', 'get_current_datetime']
            : [
                'get_current_datetime',
                for (var i = 1; i < count; i++) 'deferred_$i',
              ],
      );
      expect(
        context.selectedToolNames,
        enabled
            ? {'tool_search', 'get_current_datetime'}
            : {
                'get_current_datetime',
                for (var i = 1; i < count; i++) 'deferred_$i',
              },
      );
    });
  }

  test('duplicate definitions do not activate tool search', () {
    final context = build([for (var i = 0; i < 30; i++) tool('same')]);
    expect(context.catalog.totalToolCount, 30);
    expect(context.toolSearchEnabled, false);
    expect(context.catalog.initialToolNames, ['same']);
  });

  test('legacy search-only selection defers unclassified tools', () {
    final context = build([
      tool('deferred'),
      tool('search_web'),
      tool('get_current_datetime'),
    ]);
    expect(context.toolSearchEnabled, false);
    expect(context.catalog.toolNames, [
      'deferred',
      'search_web',
      'get_current_datetime',
    ]);
    expect(context.catalog.initialToolNames, [
      'search_web',
      'get_current_datetime',
    ]);
    expect(context.selectedToolNames, {'search_web', 'get_current_datetime'});
  });

  test('search and browser enable search and retain selected input order', () {
    final context = build([
      tool('deferred'),
      tool('get_current_datetime'),
      tool('search_web'),
      tool('browser_open'),
    ]);
    expect(context.toolSearchEnabled, true);
    expect(context.catalog.initialToolNames, [
      'tool_search',
      'get_current_datetime',
      'search_web',
    ]);
    expect(context.selectedToolNames, {
      'tool_search',
      'get_current_datetime',
      'search_web',
    });
  });
}
