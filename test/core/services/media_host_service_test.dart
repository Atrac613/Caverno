import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/media_host_service.dart';

/// The endpoint is on this machine, so every test binds loopback.
final Uri _localEndpoint = Uri.parse('http://127.0.0.1:1234/v1');

void main() {
  late Directory tempDir;
  late File videoFile;
  late MediaHostService service;
  late HttpClient client;
  var now = DateTime(2026, 8, 21, 12);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_host_test');
    videoFile = File('${tempDir.path}/clip.mp4');
    await videoFile.writeAsBytes(List<int>.generate(64, (i) => i));
    now = DateTime(2026, 8, 21, 12);
    service = MediaHostService(clock: () => now);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await service.stop();
    await tempDir.delete(recursive: true);
  });

  Future<HttpClientResponse> get(Uri url, {String method = 'GET'}) async {
    final request = await client.openUrl(method, url);
    return request.close();
  }

  Future<MediaHostTicket> publish() async {
    final ticket = await service.publish(
      file: videoFile,
      mimeType: 'video/mp4',
      endpoint: _localEndpoint,
    );
    return ticket!;
  }

  test('serves the registered file for its token', () async {
    final ticket = await publish();

    final response = await get(ticket.url);

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType.toString(), 'video/mp4');
    expect(response.contentLength, 64);
    expect(service.wasFetched(ticket.token), isTrue);
  });

  test('reports 404 for a token that was never registered', () async {
    final ticket = await publish();

    final response = await get(ticket.url.replace(path: '/v/madeuptoken'));

    expect(response.statusCode, HttpStatus.notFound);
  });

  test('reports 404 once the handle has expired', () async {
    final ticket = await publish();
    now = now.add(MediaHostService.ttl).add(const Duration(seconds: 1));

    final response = await get(ticket.url);

    expect(response.statusCode, HttpStatus.notFound);
    expect(service.wasFetched(ticket.token), isFalse);
  });

  test('stops serving once the fetch budget is spent', () async {
    final ticket = await publish();

    for (var i = 0; i < MediaHostService.maxFetches; i++) {
      final response = await get(ticket.url);
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
    }

    // The listener is gone with the last handle, so the request fails at the
    // connection rather than coming back with a status. Whether that surfaces
    // as a refused connect or a dropped keep-alive depends on which socket
    // HttpClient reaches for, so both count.
    await expectLater(
      get(ticket.url),
      throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
    );
    expect(service.isRunning, isFalse);
    expect(service.wasFetched(ticket.token), isTrue);
  });

  test('names the peer that fetched, not null', () async {
    // connectionInfo is gone once the response closes, and the log is written
    // after closing; reading it late reported every fetch as coming from null.
    final logged = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = previous);

    final ticket = await publish();
    final response = await get(ticket.url);
    await response.drain<void>();

    final line = logged.firstWhere(
      (l) => l.contains('[MediaHost]'),
      orElse: () => '',
    );
    expect(line, contains('sent 64 bytes'));
    expect(line, contains('from 127.0.0.1'));
  });

  test('refuses a method that is not a read', () async {
    final ticket = await publish();

    final response = await get(ticket.url, method: 'DELETE');

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });

  test('answers a byte range without spending the whole budget twice', () async {
    final ticket = await publish();
    final request = await client.getUrl(ticket.url);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');

    final response = await request.close();

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 10-19/64');
    final body = <int>[];
    await for (final chunk in response) {
      body.addAll(chunk);
    }
    expect(body, List<int>.generate(10, (i) => i + 10));
  });

  test('a HEAD request describes the file without consuming a fetch', () async {
    final ticket = await publish();

    final response = await get(ticket.url, method: 'HEAD');

    expect(response.statusCode, HttpStatus.ok);
    expect(response.contentLength, 64);
    expect(service.wasFetched(ticket.token), isFalse);
  });

  test('revoking a token takes the listener down with it', () async {
    final ticket = await publish();
    expect(service.isRunning, isTrue);

    await service.revoke(ticket.token);

    expect(service.isRunning, isFalse);
  });

  test('tolerates a filename extension on the token path', () async {
    final ticket = await publish();

    final response = await get(ticket.url.replace(path: '/v/${ticket.token}.mp4'));

    expect(response.statusCode, HttpStatus.ok);
  });
}
