import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/features/chat/data/datasources/openai_modalities_probe.dart';

Future<EndpointModalitySupport> probe(
  http.Response Function(http.Request request) respond, {
  String baseUrl = 'http://localhost:8080/v1',
}) {
  return const OpenAiModalitiesProbe().videoSupport(
    baseUrl: baseUrl,
    client: MockClient((request) async => respond(request)),
  );
}

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {
      'content-type': 'application/json',
    });

void main() {
  group('propsUriFor', () {
    test('strips the OpenAI version prefix', () {
      expect(
        OpenAiModalitiesProbe.propsUriFor('http://192.168.1.5:8080/v1'),
        Uri.parse('http://192.168.1.5:8080/props'),
      );
    });

    test('handles a base URL with no version segment', () {
      expect(
        OpenAiModalitiesProbe.propsUriFor('http://192.168.1.5:8080'),
        Uri.parse('http://192.168.1.5:8080/props'),
      );
    });

    test('keeps a path prefix that is not a version', () {
      expect(
        OpenAiModalitiesProbe.propsUriFor('https://gw.example.com/llama/v1'),
        Uri.parse('https://gw.example.com/llama/props'),
      );
    });

    test('rejects a base URL it cannot address', () {
      expect(OpenAiModalitiesProbe.propsUriFor('   '), isNull);
      expect(OpenAiModalitiesProbe.propsUriFor('not a url'), isNull);
    });
  });

  test('reads an advertised yes', () async {
    final support = await probe(
      (_) => _json({
        'modalities': {'vision': true, 'video': true, 'audio': false},
      }),
    );

    expect(support, EndpointModalitySupport.supported);
  });

  test('reads an advertised no', () async {
    final support = await probe(
      (_) => _json({
        'modalities': {'vision': true, 'video': false},
      }),
    );

    expect(support, EndpointModalitySupport.unsupported);
  });

  test('treats a modality list without video as a no', () async {
    // A server old enough to predate video support still answers the question.
    final support = await probe(
      (_) => _json({
        'modalities': {'vision': true},
      }),
    );

    expect(support, EndpointModalitySupport.unsupported);
  });

  test('treats a missing endpoint as unknown, not a refusal', () async {
    final support = await probe((_) => http.Response('Not Found', 404));

    expect(support, EndpointModalitySupport.unknown);
  });

  test('treats a non-JSON body as unknown', () async {
    final support = await probe((_) => http.Response('<html>hi</html>', 200));

    expect(support, EndpointModalitySupport.unknown);
  });

  test('treats a JSON body with no modalities as unknown', () async {
    final support = await probe((_) => _json({'model_path': '/models/x.gguf'}));

    expect(support, EndpointModalitySupport.unknown);
  });

  test('treats a transport failure as unknown', () async {
    final support = await probe(
      (_) => throw const SocketExceptionStub(),
    );

    expect(support, EndpointModalitySupport.unknown);
  });

  test('asks the props endpoint, not the chat endpoint', () async {
    Uri? requested;
    await probe((request) {
      requested = request.url;
      return _json({
        'modalities': {'video': true},
      });
    });

    expect(requested, Uri.parse('http://localhost:8080/props'));
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
