import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/chat_tool_dispatcher.dart';

void main() {
  group('ChatToolDispatcher', () {
    test('returns planning policy result before other handlers', () async {
      final events = <String>[];
      final dispatcher = _buildDispatcher(
        events: events,
        planningPolicy: (_) => _result('planning_policy'),
      );

      final result = await dispatcher.dispatch(_toolCall('browser_click'));

      expect(result.toolName, 'planning_policy');
      expect(events, isEmpty);
    });

    test(
      'routes approval-gated computer tools before registry handlers',
      () async {
        final events = <String>[];
        final dispatcher = _buildDispatcher(
          events: events,
          registry: ChatToolHandlerRegistry({
            'computer_click': (toolCall) async {
              events.add('registry');
              return _result('registry');
            },
          }),
        );

        final result = await dispatcher.dispatch(_toolCall('computer_click'));

        expect(result.toolName, 'computer_action');
        expect(events, ['computer_action']);
      },
    );

    test('routes observe-only computer tools without approval', () async {
      final events = <String>[];
      final dispatcher = _buildDispatcher(events: events);

      final result = await dispatcher.dispatch(
        _toolCall('computer_screenshot'),
      );

      expect(result.toolName, 'computer_observation');
      expect(events, ['computer_observation']);
    });

    test(
      'routes approval-gated browser tools before registry handlers',
      () async {
        final events = <String>[];
        final dispatcher = _buildDispatcher(
          events: events,
          registry: ChatToolHandlerRegistry({
            'browser_click': (toolCall) async {
              events.add('registry');
              return _result('registry');
            },
          }),
        );

        final result = await dispatcher.dispatch(_toolCall('browser_click'));

        expect(result.toolName, 'browser_action');
        expect(events, ['browser_action']);
      },
    );

    test('routes observe-only browser tools without approval', () async {
      final events = <String>[];
      final dispatcher = _buildDispatcher(events: events);

      final result = await dispatcher.dispatch(_toolCall('browser_snapshot'));

      expect(result.toolName, 'browser_observation');
      expect(events, ['browser_observation']);
    });

    test('uses registered handlers before fallback tools', () async {
      final events = <String>[];
      final dispatcher = _buildDispatcher(
        events: events,
        registry: ChatToolHandlerRegistry({
          'write_file': (toolCall) async {
            events.add('registry');
            return _result('registry');
          },
        }),
      );

      final result = await dispatcher.dispatch(_toolCall('write_file'));

      expect(result.toolName, 'registry');
      expect(events, ['registry']);
    });

    test('builds a registry from handler modules', () async {
      final registry = ChatToolHandlerRegistry.fromModules([
        _TestHandlerModule({
          'read_file': (_) async => _result('first'),
          'write_file': (_) async => _result('write'),
        }),
        _TestHandlerModule({'read_file': (_) async => _result('second')}),
      ]);

      final readResult = await registry.dispatch(_toolCall('read_file'));
      final writeResult = await registry.dispatch(_toolCall('write_file'));
      final missingResult = await registry.dispatch(_toolCall('edit_file'));

      expect(readResult?.toolName, 'second');
      expect(writeResult?.toolName, 'write');
      expect(missingResult, isNull);
    });

    test(
      'falls back to generic tool execution when no handler matches',
      () async {
        final events = <String>[];
        final dispatcher = _buildDispatcher(events: events);

        final result = await dispatcher.dispatch(_toolCall('external_tool'));

        expect(result.toolName, 'fallback');
        expect(events, ['fallback']);
      },
    );

    test('routes neutral remote MCP aliases only through fallback', () async {
      final events = <String>[];
      final dispatcher = _buildDispatcher(events: events);

      for (final name in const [
        'mcp__browser_open__server_hash',
        'mcp__computer_click__server_hash',
      ]) {
        final result = await dispatcher.dispatch(_toolCall(name));
        expect(result.toolName, 'fallback');
      }

      expect(events, ['fallback', 'fallback']);
    });
  });
}

ChatToolDispatcher _buildDispatcher({
  required List<String> events,
  ChatToolPlanningPolicy? planningPolicy,
  ChatToolHandlerRegistry registry = const ChatToolHandlerRegistry({}),
}) {
  return ChatToolDispatcher(
    enforcePlanningPolicy: planningPolicy ?? (_) => null,
    handleComputerUseAction: (_) async {
      events.add('computer_action');
      return _result('computer_action');
    },
    handleComputerUseObservation: (_) async {
      events.add('computer_observation');
      return _result('computer_observation');
    },
    handleBrowserAction: (_) async {
      events.add('browser_action');
      return _result('browser_action');
    },
    handleBrowserObservation: (_) async {
      events.add('browser_observation');
      return _result('browser_observation');
    },
    handlerRegistry: registry,
    executeFallbackTool: (_) async {
      events.add('fallback');
      return _result('fallback');
    },
  );
}

ToolCallInfo _toolCall(String name) {
  return ToolCallInfo(id: 'tool-$name', name: name, arguments: const {});
}

McpToolResult _result(String toolName) {
  return McpToolResult(toolName: toolName, result: toolName, isSuccess: true);
}

final class _TestHandlerModule implements ChatToolHandlerModule {
  const _TestHandlerModule(this.handlers);

  @override
  final Map<String, ChatToolHandler> handlers;
}
