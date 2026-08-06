import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/searxng_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearxngClient', () {
    late HttpServer server;
    late String baseUrl;
    StreamSubscription<HttpRequest>? serverSub;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://${server.address.host}:${server.port}';
    });

    tearDown(() async {
      await serverSub?.cancel();
      await server.close(force: true);
    });

    test('parses results from a responding instance', () async {
      serverSub = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'results': [
              {
                'title': 'Raspberry Pi',
                'url': 'https://example.invalid/pi',
                'content': 'A small computer',
              },
            ],
          }),
        );
        await request.response.close();
      });

      final result = await SearxngClient(baseUrl: baseUrl).search(query: 'pi');

      expect(result.results, hasLength(1));
      expect(result.results.single.title, 'Raspberry Pi');
    });

    test('fails instead of hanging when the instance never answers', () async {
      // Web search is the tool most likely to be reached for while the uplink
      // is down, and the tool loop has no wall-clock guard of its own: an
      // unbounded `http.get` here holds the whole turn open indefinitely.
      serverSub = server.listen((request) {
        // Accept the connection and never respond.
      });

      final client = SearxngClient(
        baseUrl: baseUrl,
        timeout: const Duration(milliseconds: 200),
      );

      final stopwatch = Stopwatch()..start();
      await expectLater(
        client.search(query: 'pi'),
        throwsA(isA<TimeoutException>()),
      );
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
