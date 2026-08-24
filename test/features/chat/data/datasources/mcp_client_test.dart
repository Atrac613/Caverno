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

      final client = McpClient(
        baseUrl: endpoint.toString(),
        maxJsonDocuments: 2,
      );
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

    test('fails instead of hanging when the server never answers', () async {
      // A LAN server refuses fast when it is down, but one reached over the
      // internet simply never answers while the uplink is out, and the tool
      // loop has no wall-clock guard that would end the turn.
      serverSub = server.listen((request) {
        // Accept the connection and never respond.
      });

      final client = McpClient(
        baseUrl: endpoint.toString(),
        timeout: const Duration(milliseconds: 200),
      );

      final stopwatch = Stopwatch()..start();
      await expectLater(client.listTools(), throwsA(isA<TimeoutException>()));
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('rejects an oversized declared response before decoding', () async {
      serverSub = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.contentLength = 129;
        request.response.write('x' * 129);
        await request.response.close();
      });
      final client = McpClient(
        baseUrl: endpoint.toString(),
        maxResponseBodyBytes: 128,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.listTools(),
        throwsA(
          isA<McpResponseLimitException>().having(
            (error) => error.message,
            'message',
            contains('declared 129 bytes'),
          ),
        ),
      );
    });

    test('rejects a chunked response at the wire-byte ceiling', () async {
      serverSub = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write('a' * 64);
        await request.response.flush();
        request.response.write('b' * 65);
        await request.response.close();
      });
      final client = McpClient(
        baseUrl: endpoint.toString(),
        maxResponseBodyBytes: 128,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.listTools(),
        throwsA(
          isA<McpResponseLimitException>().having(
            (error) => error.message,
            'message',
            contains('exceeded the 128 byte limit'),
          ),
        ),
      );
    });

    test('fails when a response stalls between chunks', () async {
      serverSub = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{');
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          await request.response.close();
        } on HttpException {
          // The client intentionally closes the stalled response.
        }
      });
      final client = McpClient(
        baseUrl: endpoint.toString(),
        timeout: const Duration(seconds: 2),
        responseIdleTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(client.dispose);

      await expectLater(client.listTools(), throwsA(isA<TimeoutException>()));
    });

    test(
      'rejects excess concatenated JSON documents before decoding',
      () async {
        serverSub = server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"transport":"metadata"}'
            '{"sequence":1}'
            '{"jsonrpc":"2.0","id":1,"result":{}}',
          );
          await request.response.close();
        });
        final client = McpClient(
          baseUrl: endpoint.toString(),
          maxJsonDocuments: 2,
        );
        addTearDown(client.dispose);

        await expectLater(
          client.listTools(),
          throwsA(
            isA<McpResponseLimitException>().having(
              (error) => error.message,
              'message',
              contains('more than 2 JSON documents'),
            ),
          ),
        );
      },
    );

    test('rejects excess JSON documents across SSE events', () async {
      serverSub = server.listen((request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: {"transport":"metadata"}\n\n'
          'data: {"sequence":1}\n\n'
          'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n',
        );
        await request.response.close();
      });
      final client = McpClient(
        baseUrl: endpoint.toString(),
        maxJsonDocuments: 2,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.listTools(),
        throwsA(
          isA<McpResponseLimitException>().having(
            (error) => error.message,
            'message',
            contains('more than 2 JSON documents'),
          ),
        ),
      );
    });

    test('rejects excessive aggregate tool text content', () async {
      serverSub = server.listen((request) async {
        final requestBody = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(requestBody) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        if (decoded['method'] == 'initialize') {
          request.response.write(
            '{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{}}}',
          );
        } else if (decoded['method'] == 'notifications/initialized') {
          request.response.write('{}');
        } else {
          request.response.write(
            '{"jsonrpc":"2.0","id":2,"result":{"content":['
            '{"type":"text","text":"abc"},'
            '{"type":"text","text":"def"}'
            ']}}',
          );
        }
        await request.response.close();
      });
      final client = McpClient(
        baseUrl: endpoint.toString(),
        maxToolContentCharacters: 6,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.callTool(name: 'oversized', arguments: const {}),
        throwsA(
          isA<McpResponseLimitException>().having(
            (error) => error.message,
            'message',
            contains('tool text exceeded 6 characters'),
          ),
        ),
      );
    });

    test('rejects non-positive response bounds', () {
      expect(
        () => McpClient(baseUrl: endpoint.toString(), maxResponseBodyBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => McpClient(
          baseUrl: endpoint.toString(),
          responseIdleTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => McpClient(baseUrl: endpoint.toString(), maxJsonDocuments: 0),
        throwsArgumentError,
      );
      expect(
        () => McpClient(
          baseUrl: endpoint.toString(),
          maxToolContentCharacters: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
