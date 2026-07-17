import 'dart:async';

import 'package:caverno/features/chat/data/datasources/mcp_client.dart';
import 'package:caverno/features/chat/data/datasources/remote_mcp_connection_manager.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteMcpConnectionManager', () {
    test('starts disconnected and clears state with no clients', () async {
      final manager = RemoteMcpConnectionManager(
        configuredClients: const [],
        reservedToolNames: const {},
        isDesktopPlatform: false,
      );

      expect(manager.status, McpConnectionStatus.disconnected);
      expect(manager.tools, isEmpty);
      expect(manager.serverStates, isEmpty);
      expect(manager.lastError, isNull);

      await manager.connect();

      expect(manager.status, McpConnectionStatus.disconnected);
      expect(manager.tools, isEmpty);
      expect(manager.serverStates, isEmpty);
      expect(manager.lastError, isNull);
    });

    test(
      'preserves client order when discovery completes out of order',
      () async {
        final firstTools = Completer<List<McpTool>>();
        final secondTools = Completer<List<McpTool>>();
        final first = _FakeMcpClient(
          identifier: 'https://first.example/mcp',
          listToolsHandler: () => firstTools.future,
        );
        final second = _FakeMcpClient(
          identifier: 'https://second.example/mcp',
          listToolsHandler: () => secondTools.future,
        );
        final manager = RemoteMcpConnectionManager(
          configuredClients: [first, second],
          reservedToolNames: const {},
          isDesktopPlatform: false,
        );

        final connectFuture = manager.connect();
        expect(manager.status, McpConnectionStatus.connecting);
        expect(manager.serverStates.map((state) => state.identifier), [
          first.identifier,
          second.identifier,
        ]);

        secondTools.complete([_tool('second_tool')]);
        await Future<void>.delayed(Duration.zero);
        expect(manager.status, McpConnectionStatus.connecting);
        firstTools.complete([_tool('first_tool')]);
        await connectFuture;

        expect(manager.status, McpConnectionStatus.connected);
        expect(manager.tools.map((tool) => tool.name), [
          'first_tool',
          'second_tool',
        ]);
        expect(manager.serverStates.map((state) => state.identifier), [
          first.identifier,
          second.identifier,
        ]);
      },
    );

    test(
      'retains partial success and clears cache after total failure',
      () async {
        final clients = <McpClientBase>[
          _FakeMcpClient(
            identifier: 'https://healthy.example/mcp',
            tools: [_tool('healthy_tool')],
          ),
          _FakeMcpClient(
            identifier: 'https://failed.example/mcp',
            listToolsError: StateError('partial failure'),
          ),
        ];
        final manager = RemoteMcpConnectionManager(
          configuredClients: clients,
          reservedToolNames: const {},
          isDesktopPlatform: false,
        );

        await manager.connect();

        expect(manager.status, McpConnectionStatus.connected);
        expect(manager.tools.single.name, 'healthy_tool');
        expect(
          manager.lastError,
          'https://failed.example/mcp: Bad state: partial failure',
        );
        expect(manager.serverStates.map((state) => state.status), [
          McpConnectionStatus.connected,
          McpConnectionStatus.error,
        ]);

        clients[0] = _FakeMcpClient(
          identifier: 'https://also-failed.example/mcp',
          listToolsError: StateError('total failure'),
        );
        await manager.connect();

        expect(manager.status, McpConnectionStatus.error);
        expect(manager.tools, isEmpty);
        expect(
          manager.lastError,
          'https://also-failed.example/mcp: Bad state: total failure | '
          'https://failed.example/mcp: Bad state: partial failure',
        );
        expect(
          manager.serverStates.every(
            (state) => state.status == McpConnectionStatus.error,
          ),
          isTrue,
        );
      },
    );

    test('honors override precedence and keeps raw URL strings', () async {
      final configured = _FakeMcpClient(
        identifier: 'https://configured.example/mcp',
        tools: [_tool('configured_tool')],
      );
      final httpUrls = <String>[];
      final manager = RemoteMcpConnectionManager(
        configuredClients: [configured],
        reservedToolNames: const {},
        httpClientFactory: (baseUrl) {
          httpUrls.add(baseUrl);
          return _FakeMcpClient(
            identifier: baseUrl,
            tools: [_tool('override_tool')],
          );
        },
        isDesktopPlatform: false,
      );

      await manager.connect(
        overrideServers: const [
          McpServerConfig(
            url: '  https://pending.example/mcp  ',
            trustState: McpServerTrustState.pending,
          ),
        ],
        overrideUrls: const ['https://ignored-list.example/mcp'],
        overrideUrl: 'https://ignored-single.example/mcp',
      );

      expect(httpUrls, ['https://pending.example/mcp']);
      expect(configured.listToolsCallCount, 0);
      expect(manager.tools.single.sourceUrl, 'https://pending.example/mcp');

      const rawUrl = '  https://raw.example/mcp  ';
      await manager.connect(
        overrideUrls: const [rawUrl],
        overrideUrl: 'https://ignored.example/mcp',
      );
      expect(httpUrls, ['https://pending.example/mcp', rawUrl]);
      expect(manager.tools.single.sourceUrl, rawUrl);

      await manager.connect(
        overrideUrls: const [],
        overrideUrl: 'https://must-not-connect.example/mcp',
      );
      expect(httpUrls, ['https://pending.example/mcp', rawUrl]);
      expect(manager.status, McpConnectionStatus.disconnected);
      expect(manager.tools, isEmpty);
    });

    test(
      'filters server trust and normalizes stdio inputs on desktop',
      () async {
        final httpUrls = <String>[];
        final stdioRequests = <Map<String, Object>>[];
        final manager = RemoteMcpConnectionManager(
          configuredClients: const [],
          reservedToolNames: const {},
          httpClientFactory: (baseUrl) {
            httpUrls.add(baseUrl);
            return _FakeMcpClient(identifier: baseUrl);
          },
          stdioClientFactory: (command, args, environment) {
            stdioRequests.add({
              'command': command,
              'args': List<String>.from(args),
              'environment': Map<String, String>.from(environment),
            });
            return _FakeMcpClient(identifier: '$command ${args.join(' ')}');
          },
          isDesktopPlatform: true,
        );

        await manager.connect(
          overrideServers: const [
            McpServerConfig(
              url: 'https://disabled.example/mcp',
              enabled: false,
            ),
            McpServerConfig(url: ''),
            McpServerConfig(
              url: 'https://blocked.example/mcp',
              trustState: McpServerTrustState.blocked,
            ),
            McpServerConfig(
              url: ' https://pending.example/mcp ',
              trustState: McpServerTrustState.pending,
            ),
            McpServerConfig(
              url: 'https://trusted.example/mcp',
              trustState: McpServerTrustState.trusted,
            ),
            McpServerConfig(
              type: McpServerType.stdio,
              trustState: McpServerTrustState.pending,
              command: '  dart  ',
              args: ['run', 'tool/server.dart'],
              env: {' TOKEN ': ' secret ', ' ': 'ignored'},
            ),
          ],
        );

        expect(httpUrls, [
          'https://pending.example/mcp',
          'https://trusted.example/mcp',
        ]);
        expect(stdioRequests, [
          {
            'command': 'dart',
            'args': ['run', 'tool/server.dart'],
            'environment': {'TOKEN': 'secret'},
          },
        ]);
        expect(manager.status, McpConnectionStatus.connected);
        expect(manager.serverStates, hasLength(3));
      },
    );

    test('skips stdio overrides outside desktop platforms', () async {
      var stdioFactoryCalls = 0;
      final manager = RemoteMcpConnectionManager(
        configuredClients: const [],
        reservedToolNames: const {},
        stdioClientFactory: (command, args, environment) {
          stdioFactoryCalls += 1;
          return _FakeMcpClient(identifier: command);
        },
        isDesktopPlatform: false,
      );

      await manager.connect(
        overrideServers: const [
          McpServerConfig(
            type: McpServerType.stdio,
            trustState: McpServerTrustState.pending,
            command: 'dart',
          ),
        ],
      );

      expect(stdioFactoryCalls, 0);
      expect(manager.status, McpConnectionStatus.disconnected);
      expect(manager.serverStates, isEmpty);
    });

    test('keeps aliases ordered, unique, and within 64 characters', () async {
      final longName = List.filled(80, 'x').join();
      final first = _FakeMcpClient(
        identifier: 'https://duplicate.example:8443/mcp',
        tools: [
          _tool('reserved_name', description: 'First reserved'),
          _tool(longName, description: 'Long tool'),
        ],
      );
      final second = _FakeMcpClient(
        identifier: 'https://duplicate.example:8443/mcp',
        tools: [_tool('reserved_name', description: 'Second reserved')],
      );
      final manager = RemoteMcpConnectionManager(
        configuredClients: [first, second],
        reservedToolNames: const {'reserved_name'},
        isDesktopPlatform: false,
      );

      await manager.connect();

      expect(manager.tools.map((tool) => tool.description), [
        'First reserved',
        'Long tool',
        'Second reserved',
      ]);
      expect(manager.tools.map((tool) => tool.name).toSet(), hasLength(3));
      expect(manager.tools.every((tool) => tool.name.length <= 64), isTrue);
      expect(manager.tools.first.name, startsWith('reserved_name__'));
      expect(manager.tools[1].name, longName.substring(0, 64));
      expect(manager.tools.last.name, endsWith('_2'));
      expect(manager.tools.map((tool) => tool.sourceUrl).toSet(), {
        first.identifier,
      });
    });

    test(
      'routes duplicate reserved-prefix aliases to their originating clients',
      () async {
        final first = _FakeMcpClient(
          identifier: 'https://duplicate.example.com/mcp',
          tools: [_tool('browser_export_state')],
          callResults: const {'browser_export_state': 'first result'},
        );
        final second = _FakeMcpClient(
          identifier: 'https://duplicate.example.com/mcp',
          tools: [_tool('browser_export_state')],
          callResults: const {'browser_export_state': 'second result'},
        );
        final manager = RemoteMcpConnectionManager(
          configuredClients: [first, second],
          reservedToolNames: const {},
          reservedToolNamePrefixes: const {'browser_', 'computer_'},
          isDesktopPlatform: false,
        );

        await manager.connect();

        expect(manager.tools, hasLength(2));
        expect(manager.tools.map((tool) => tool.originalName), [
          'browser_export_state',
          'browser_export_state',
        ]);
        expect(manager.tools.map((tool) => tool.name).toSet(), hasLength(2));
        expect(manager.tools.first.name, startsWith('mcp__browser_'));
        expect(manager.tools.last.name, endsWith('_2'));

        final firstResult = await manager.tryExecute(
          name: manager.tools.first.name,
          arguments: const {'client': 'first'},
        );
        final secondResult = await manager.tryExecute(
          name: manager.tools.last.name,
          arguments: const {'client': 'second'},
        );

        expect(firstResult?.result, 'first result');
        expect(secondResult?.result, 'second result');
        expect(first.calledToolNames, ['browser_export_state']);
        expect(second.calledToolNames, ['browser_export_state']);
        expect(first.calledArguments, [
          {'client': 'first'},
        ]);
        expect(second.calledArguments, [
          {'client': 'second'},
        ]);
      },
    );

    test(
      'routes invocations and preserves success and failure envelopes',
      () async {
        final client = _FakeMcpClient(
          identifier: 'https://tools.example/mcp',
          tools: [_tool('original_tool')],
          callResults: const {'original_tool': 'remote result'},
        );
        final manager = RemoteMcpConnectionManager(
          configuredClients: [client],
          reservedToolNames: const {'original_tool'},
          isDesktopPlatform: false,
        );

        expect(
          await manager.tryExecute(name: 'missing', arguments: const {}),
          isNull,
        );
        await manager.connect();
        final exposedName = manager.tools.single.name;

        final success = await manager.tryExecute(
          name: exposedName,
          arguments: const {'query': 'value'},
        );

        expect(success, isNotNull);
        expect(success!.toolName, exposedName);
        expect(success.result, 'remote result');
        expect(success.isSuccess, isTrue);
        expect(success.isExternalMcpResult, isTrue);
        expect(manager.isExternalToolName(exposedName), isTrue);
        expect(manager.isExternalToolName('missing'), isFalse);
        expect(client.calledToolNames, ['original_tool']);
        expect(client.calledArguments, [
          {'query': 'value'},
        ]);

        client.callToolError = StateError('call failed');
        final failure = await manager.tryExecute(
          name: exposedName,
          arguments: const {'query': 'retry'},
        );
        expect(failure, isNotNull);
        expect(failure!.isSuccess, isFalse);
        expect(failure.isExternalMcpResult, isTrue);
        expect(failure.result, isEmpty);
        expect(failure.errorMessage, 'Bad state: call failed');

        await manager.connect(overrideUrls: const []);
        expect(manager.isExternalToolName(exposedName), isFalse);
        expect(
          await manager.tryExecute(name: exposedName, arguments: const {}),
          isNull,
        );
      },
    );

    test('keeps tools mutable and server states unmodifiable', () async {
      final manager = RemoteMcpConnectionManager(
        configuredClients: [
          _FakeMcpClient(
            identifier: 'https://mutable.example/mcp',
            tools: [_tool('mutable_tool')],
          ),
        ],
        reservedToolNames: const {},
        isDesktopPlatform: false,
      );
      await manager.connect();

      manager.tools.clear();

      expect(manager.tools, isEmpty);
      expect(
        () => manager.serverStates.add(
          const McpServerConnectionInfo(
            identifier: 'extra',
            status: McpConnectionStatus.connected,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}

McpTool _tool(String name, {String? description}) {
  return McpTool(
    name: name,
    description: description ?? 'Remote $name tool',
    inputSchema: const {'type': 'object'},
  );
}

class _FakeMcpClient implements McpClientBase {
  _FakeMcpClient({
    required this.identifier,
    this.tools = const [],
    this.listToolsHandler,
    this.listToolsError,
    this.callResults = const {},
  });

  @override
  final String identifier;
  final List<McpTool> tools;
  final Future<List<McpTool>> Function()? listToolsHandler;
  final Object? listToolsError;
  final Map<String, String> callResults;
  Object? callToolError;
  final List<String> calledToolNames = [];
  final List<Map<String, dynamic>> calledArguments = [];
  int listToolsCallCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<McpTool>> listTools() async {
    listToolsCallCount += 1;
    if (listToolsHandler != null) {
      return listToolsHandler!();
    }
    if (listToolsError != null) {
      throw listToolsError!;
    }
    return tools;
  }

  @override
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    calledToolNames.add(name);
    calledArguments.add(Map<String, dynamic>.from(arguments));
    if (callToolError != null) {
      throw callToolError!;
    }
    return callResults[name] ?? '';
  }

  @override
  Future<void> dispose() async {}
}
