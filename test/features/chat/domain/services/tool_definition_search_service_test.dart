import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/settings/domain/entities/built_in_tool_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolDefinitionSearchService', () {
    test(
      'adds tool_search and defers non-initial tools for large catalogs',
      () {
        final definitions = [
          _tool('get_current_datetime', 'Return the current date and time.'),
          _tool('read_file', 'Read a local project file.'),
          for (var i = 0; i < 30; i++)
            _tool('remote_tool_$i', 'Remote MCP capability number $i.'),
        ];

        final selection = ToolDefinitionSearchService.buildInitialSelection(
          ToolDefinitionSearchService.appendSearchToolIfUseful(definitions),
        );
        final names = ToolDefinitionSearchService.toolNamesFromDefinitions(
          selection.toolDefinitions,
        );

        expect(selection.toolSearchEnabled, isTrue);
        expect(names, contains(ToolDefinitionSearchService.toolName));
        expect(names, contains('get_current_datetime'));
        expect(names, contains('read_file'));
        expect(names, isNot(contains('remote_tool_29')));
        expect(selection.selectedToolNames, contains('read_file'));
      },
    );

    test('keeps network diagnostic tools available in large catalogs', () {
      final definitions = [
        _tool('get_current_datetime', 'Return the current date and time.'),
        _tool('get_wifi_health', 'Return Wi-Fi health facts.'),
        _tool('wifi_get_connection_info', 'Return current Wi-Fi connection.'),
        _tool('get_wan_status', 'Return WAN and ISP reachability status.'),
        for (var i = 0; i < 30; i++)
          _tool('remote_tool_$i', 'Remote MCP capability number $i.'),
      ];

      final selection = ToolDefinitionSearchService.buildInitialSelection(
        ToolDefinitionSearchService.appendSearchToolIfUseful(definitions),
      );
      final names = ToolDefinitionSearchService.toolNamesFromDefinitions(
        selection.toolDefinitions,
      );

      expect(selection.toolSearchEnabled, isTrue);
      expect(names, contains(ToolDefinitionSearchService.toolName));
      expect(names, contains('get_wifi_health'));
      expect(names, contains('wifi_get_connection_info'));
      expect(names, contains('get_wan_status'));
      expect(names, isNot(contains('remote_tool_29')));
    });

    test(
      'loads search tools first and defers browser tools in large catalogs',
      () {
        final definitions = [
          _tool('search_web', 'Search the web using SearXNG.'),
          _tool('search_news', 'Search recent news using SearXNG.'),
          _tool('search_images', 'Search images using SearXNG.'),
          _tool('browser_open', 'Open a URL in the built-in browser pane.'),
          _tool('browser_snapshot', 'List visible browser page elements.'),
          _tool('browser_click', 'Click an element in the browser page.'),
          _tool('http_get', 'Fetch a URL as an HTTP GET request.'),
          for (var i = 0; i < 30; i++)
            _tool('remote_tool_$i', 'Remote MCP capability number $i.'),
        ];

        final selection = ToolDefinitionSearchService.buildInitialSelection(
          ToolDefinitionSearchService.appendSearchToolIfUseful(definitions),
        );
        final names = ToolDefinitionSearchService.toolNamesFromDefinitions(
          selection.toolDefinitions,
        );

        expect(selection.toolSearchEnabled, isTrue);
        expect(names, contains(ToolDefinitionSearchService.toolName));
        expect(names, contains('search_web'));
        expect(names, contains('search_news'));
        expect(names, contains('search_images'));
        expect(names, isNot(contains('browser_open')));
        expect(names, isNot(contains('browser_snapshot')));
        expect(names, isNot(contains('browser_click')));
        expect(names, contains('http_get'));
        expect(names, isNot(contains('remote_tool_29')));
      },
    );

    test('defers browser tools when a small catalog has search tools', () {
      final selection = ToolDefinitionSearchService.buildInitialSelection([
        _tool('search_web', 'Search the web using SearXNG.'),
        _tool('browser_open', 'Open a URL in the built-in browser pane.'),
        _tool('browser_snapshot', 'List visible browser page elements.'),
      ]);
      final names = ToolDefinitionSearchService.toolNamesFromDefinitions(
        selection.toolDefinitions,
      );

      expect(selection.toolSearchEnabled, isTrue);
      expect(names, contains(ToolDefinitionSearchService.toolName));
      expect(names, contains('search_web'));
      expect(names, isNot(contains('browser_open')));
      expect(names, isNot(contains('browser_snapshot')));
    });

    test('keeps interactive and skill tools available in large catalogs', () {
      final definitions = [
        _tool('ask_user_question', 'Ask the user a choice question.'),
        _tool('load_skill', 'Load a saved user skill.'),
        _tool('save_skill', 'Save a reusable skill from this conversation.'),
        _tool('spawn_subagent', 'Delegate a sub-task to a child agent.'),
        _tool('get_subagent_result', 'Get a background subagent result.'),
        for (var i = 0; i < 30; i++)
          _tool('remote_tool_$i', 'Remote MCP capability number $i.'),
      ];

      final selection = ToolDefinitionSearchService.buildInitialSelection(
        ToolDefinitionSearchService.appendSearchToolIfUseful(definitions),
      );
      final names = ToolDefinitionSearchService.toolNamesFromDefinitions(
        selection.toolDefinitions,
      );

      expect(selection.toolSearchEnabled, isTrue);
      expect(names, contains('ask_user_question'));
      expect(names, contains('load_skill'));
      // Regression: save_skill must stay in the initial selection so in-chat
      // skill authoring is reachable without the model first calling tool_search.
      expect(names, contains('save_skill'));
      expect(names, contains('spawn_subagent'));
      expect(names, contains('get_subagent_result'));
      expect(names, contains(ToolDefinitionSearchService.toolName));
      expect(names, isNot(contains('remote_tool_29')));
    });

    test('keeps process monitoring tools available in large catalogs', () {
      final definitions = [
        _tool('process_start', 'Start a background local process.'),
        _tool('process_status', 'Check background process status.'),
        _tool('process_tail', 'Read a background process tail.'),
        _tool('process_wait', 'Wait briefly for a background process.'),
        _tool('process_cancel', 'Cancel a background process.'),
        _tool('process_list', 'List monitored background processes.'),
        for (var i = 0; i < 30; i++)
          _tool('remote_tool_$i', 'Remote MCP capability number $i.'),
      ];

      final selection = ToolDefinitionSearchService.buildInitialSelection(
        ToolDefinitionSearchService.appendSearchToolIfUseful(definitions),
      );
      final names = ToolDefinitionSearchService.toolNamesFromDefinitions(
        selection.toolDefinitions,
      );

      expect(selection.toolSearchEnabled, isTrue);
      expect(names, contains('process_start'));
      expect(names, contains('process_status'));
      expect(names, contains('process_tail'));
      expect(names, contains('process_wait'));
      expect(names, contains('process_cancel'));
      expect(names, contains('process_list'));
      expect(names, isNot(contains('remote_tool_29')));
      expect(names, contains(ToolDefinitionSearchService.toolName));
    });

    test('keeps legacy initial search behavior for small catalogs', () {
      final selection = ToolDefinitionSearchService.buildInitialSelection([
        _tool('web_search', 'Search the web.'),
        _tool('get_current_datetime', 'Return the current date and time.'),
        _tool('web_url_read', 'Read a web page.'),
      ]);
      final names = ToolDefinitionSearchService.toolNamesFromDefinitions(
        selection.toolDefinitions,
      );

      expect(selection.toolSearchEnabled, isFalse);
      expect(names, contains('web_search'));
      expect(names, contains('get_current_datetime'));
      expect(names, isNot(contains('web_url_read')));
    });

    test('searches names, descriptions, and schemas', () {
      final result = ToolDefinitionSearchService.searchToolDefinitions(
        definitions: [
          _tool(
            'read_mcp_resource',
            'Read a resource exposed by an MCP server.',
          ),
          _tool('query_database', 'Run a readonly SQL query.'),
          ToolDefinitionSearchService.toolDefinition,
        ],
        query: 'mcp resource',
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final matches = decoded['matched_tools'] as List<dynamic>;

      expect(matches, isNotEmpty);
      expect(matches.first, containsPair('name', 'read_mcp_resource'));
      expect(
        matches.map((match) => (match as Map)['name']),
        isNot(contains(ToolDefinitionSearchService.toolName)),
      );
    });

    test('does not match tools on a generic recurring term alone', () {
      final definitions = [
        for (var i = 0; i < 5; i++)
          _tool('ble_op_$i', 'Operate on a connected BLE device by device_id.'),
        _tool('read_file', 'Read a local project file.'),
        ToolDefinitionSearchService.toolDefinition,
      ];

      final result = ToolDefinitionSearchService.searchToolDefinitions(
        definitions: definitions,
        query: 'gpu vram affordable device',
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final names = (decoded['matched_tools'] as List)
          .map((match) => (match as Map)['name'])
          .toList();

      // "device" is generic (5 tools); gpu/vram/affordable match nothing, so
      // the BLE tools are not surfaced for a GPU query.
      expect(names, isEmpty);
    });

    test('still matches a tool by name when a query term is generic', () {
      final definitions = [
        for (var i = 0; i < 5; i++)
          _tool('ble_op_$i', 'Operate on a connected BLE device by device_id.'),
        _tool('device_inventory', 'List warehouse inventory items.'),
        ToolDefinitionSearchService.toolDefinition,
      ];

      final result = ToolDefinitionSearchService.searchToolDefinitions(
        definitions: definitions,
        query: 'device inventory',
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final names = (decoded['matched_tools'] as List)
          .map((match) => (match as Map)['name'])
          .toList();

      // Name-level matches still count even though "device" is generic.
      expect(names.first, 'device_inventory');
    });

    test('matches a discriminating description term in a large catalog', () {
      final definitions = [
        for (var i = 0; i < 5; i++)
          _tool('ble_op_$i', 'Operate on a connected BLE device by device_id.'),
        _tool('query_database', 'Run a readonly SQL query.'),
        ToolDefinitionSearchService.toolDefinition,
      ];

      final result = ToolDefinitionSearchService.searchToolDefinitions(
        definitions: definitions,
        query: 'sql',
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final names = (decoded['matched_tools'] as List)
          .map((match) => (match as Map)['name'])
          .toList();

      // "sql" appears in a single tool, so it is discriminating and still
      // matches by description alone.
      expect(names, contains('query_database'));
    });

    test('extracts discovered names from tool_search results', () {
      final result = ToolDefinitionSearchService.searchToolDefinitions(
        definitions: [_tool('query_database', 'Run a readonly SQL query.')],
        query: 'sql',
      );

      final names = ToolDefinitionSearchService.discoveredToolNamesFromResults([
        ToolResultInfo(
          id: 'call-1',
          name: ToolDefinitionSearchService.toolName,
          arguments: const {'query': 'sql'},
          result: result,
        ),
      ]);

      expect(names, {'query_database'});
    });
  });

  // F6 guard: every built-in tool must be explicitly classified as tool-search
  // initial-load or intentionally deferred, so a new tool can never be silently
  // hidden behind tool_search (as save_skill and resolve_installed_dependency
  // were before this guard existed).
  group('built-in tool initial-load classification (F6)', () {
    // The deferral metadata is owned by BuiltInToolRegistry (single source of
    // truth); shouldLoadInitially derives the initial set from it.
    const deferredCategories = BuiltInToolRegistry.toolSearchDeferredCategories;
    const deferredNames = BuiltInToolRegistry.toolSearchDeferredToolNames;

    test('every built-in tool is initial-load or intentionally deferred', () {
      final unclassified = <String>[];
      for (final info in BuiltInToolRegistry.tools) {
        final initial = ToolDefinitionSearchService.shouldLoadInitially(
          info.name,
        );
        final deferred =
            deferredCategories.contains(info.category) ||
            deferredNames.contains(info.name);
        if (!initial && !deferred) {
          unclassified.add('${info.name} (${info.category})');
        }
        expect(
          initial && deferred,
          isFalse,
          reason:
              '${info.name} is both initial-load and intentionally deferred',
        );
      }
      expect(
        unclassified,
        isEmpty,
        reason:
            'These built-in tools are neither initial-loaded nor intentionally '
            'deferred, so they would be silently hidden behind tool_search. Add '
            'each to a non-deferred BuiltInToolRegistry category, or to the '
            'deferred categories/names: $unclassified',
      );
    });

    test('skill authoring and dependency grounding load initially', () {
      expect(
        ToolDefinitionSearchService.shouldLoadInitially('save_skill'),
        isTrue,
      );
      expect(
        ToolDefinitionSearchService.shouldLoadInitially(
          'resolve_installed_dependency',
        ),
        isTrue,
      );
    });

    test('worktree finish tool loads initially', () {
      expect(
        ToolDefinitionSearchService.shouldLoadInitially(
          'git_finish_worktree_session',
        ),
        isTrue,
      );
    });

    test('non-registry built-in tools still load initially', () {
      // These are not in BuiltInToolRegistry but must stay in the initial set.
      for (final name in [
        'search_web',
        'process_start',
        'get_dns_health',
        'explain_network_slowdown_context',
      ]) {
        expect(
          ToolDefinitionSearchService.shouldLoadInitially(name),
          isTrue,
          reason: '$name must remain initial-loaded',
        );
      }
    });

    test('deferred tools are not in the initial selection', () {
      for (final name in [
        'http_post',
        'run_python_script',
        'browser_open',
        'computer_click',
        'ssh_connect',
      ]) {
        expect(
          ToolDefinitionSearchService.shouldLoadInitially(name),
          isFalse,
          reason: '$name should be deferred behind tool_search',
        );
      }
    });

    test('unknown remote/MCP tools are deferred', () {
      expect(
        ToolDefinitionSearchService.shouldLoadInitially('some_remote_mcp_tool'),
        isFalse,
      );
    });
  });
}

Map<String, dynamic> _tool(String name, String description) {
  return {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': const {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
      },
    },
  };
}
