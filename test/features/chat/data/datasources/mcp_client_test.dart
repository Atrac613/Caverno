import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/mcp_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('McpClient HTTP transport', () {
    late HttpServer server;
    late Uri endpoint;
    StreamSubscription<HttpRequest>? serverSub;
    final requests = <Map<String, dynamic>>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/mcp',
      );
    });

    tearDown(() async {
      await serverSub?.cancel();
      await server.close(force: true);
    });

    test('selects the JSON-RPC tool list from concatenated JSON bodies', () async {
      serverSub = server.listen((request) async {
        final requestBody = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(requestBody) as Map<String, dynamic>;
        requests.add(decoded);

        request.response.headers.contentType = ContentType.json;
        if (decoded['method'] == 'initialize') {
          request.response.headers.set('mcp-session-id', 'session-123');
          request.response.write(
            '{"transport":"streamable-http-ish","path":"/mcp","response_count":1}'
            '{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"demo"}}}',
          );
        } else if (decoded['method'] == 'notifications/initialized') {
          request.response.write('{}');
        } else if (decoded['method'] == 'tools/list') {
          request.response.write(
            '{"transport":"streamable-http-ish","path":"/mcp","response_count":1}'
            '{"jsonrpc":"2.0","id":2,"result":{"tools":['
            '{"name":"remote_search","description":"Search remote content","inputSchema":{"type":"object"}}'
            ']}}',
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final client = McpClient(baseUrl: endpoint.toString());
      final tools = await client.listTools();

      expect(tools, hasLength(1));
      expect(tools.single.name, 'remote_search');
      expect(requests.map((request) => request['method']), [
        'initialize',
        'notifications/initialized',
        'tools/list',
      ]);
    });

    test(
      'prefers the matching JSON-RPC id when multiple documents are returned',
      () async {
        serverSub = server.listen((request) async {
          final requestBody = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(requestBody) as Map<String, dynamic>;
          requests.add(decoded);

          request.response.headers.contentType = ContentType.json;
          if (decoded['method'] == 'initialize') {
            request.response.headers.set('mcp-session-id', 'session-abc');
            request.response.write(
              '{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"demo"}}}',
            );
          } else if (decoded['method'] == 'notifications/initialized') {
            request.response.write('{}');
          } else if (decoded['method'] == 'tools/call') {
            request.response.write(
              '{"jsonrpc":"2.0","id":999,"result":{"content":[{"type":"text","text":"wrong"}]}}'
              '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"right"}]}}',
            );
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });

        final client = McpClient(baseUrl: endpoint.toString());
        final result = await client.callTool(
          name: 'remote_search',
          arguments: const {'query': 'caverno'},
        );

        expect(result, 'right');
      },
    );

    test('unwraps JSON-RPC payloads nested in SSE response envelopes', () async {
      serverSub = server.listen((request) async {
        final requestBody = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(requestBody) as Map<String, dynamic>;
        requests.add(decoded);

        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        if (decoded['method'] == 'initialize') {
          request.response.write(
            'event: open\n'
            'data: {"transport":"streamable-http-ish","path":"/mcp","response_count":1}\n\n'
            'event: message\n'
            'data: {"sequence":1,"response":{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"demo"}}}}\n\n'
            'event: done\n'
            'data: {"status":"completed","response_count":1}\n\n',
          );
        } else if (decoded['method'] == 'notifications/initialized') {
          request.response.write(
            'event: open\n'
            'data: {"transport":"streamable-http-ish","path":"/mcp","response_count":1}\n\n'
            'event: done\n'
            'data: {"status":"completed","response_count":0}\n\n',
          );
        } else if (decoded['method'] == 'tools/list') {
          request.response.write(
            'event: open\n'
            'data: {"transport":"streamable-http-ish","path":"/mcp","response_count":1}\n\n'
            'event: message\n'
            'data: {"sequence":1,"response":{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"get_wifi_health","description":"Return Wi-Fi health facts.","inputSchema":{"type":"object"}}]}}}\n\n'
            'event: done\n'
            'data: {"status":"completed","response_count":1}\n\n',
          );
        } else if (decoded['method'] == 'tools/call') {
          request.response.write(
            'event: open\n'
            'data: {"transport":"streamable-http-ish","path":"/mcp","response_count":1}\n\n'
            'event: message\n'
            'data: {"sequence":1,"response":{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"healthy"}]}}}\n\n'
            'event: done\n'
            'data: {"status":"completed","response_count":1}\n\n',
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final client = McpClient(baseUrl: endpoint.toString());
      final tools = await client.listTools();
      final result = await client.callTool(
        name: 'get_wifi_health',
        arguments: const {'minutes': 5},
      );

      expect(tools, hasLength(1));
      expect(tools.single.name, 'get_wifi_health');
      expect(result, 'healthy');
      expect(requests.map((request) => request['method']), [
        'initialize',
        'notifications/initialized',
        'tools/list',
        'tools/call',
      ]);
    });
  });
}
