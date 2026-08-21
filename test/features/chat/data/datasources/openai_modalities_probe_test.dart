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
    model: 'qwen3.8-27b-vision',
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

    test('names the model so a router answers about it', () {
      // A bare /props on a router describes the router, which has no
      // modalities at all; the model has to be named to get an answer.
      expect(
        OpenAiModalitiesProbe.propsUriFor(
          'http://192.168.100.241:1234/v1',
          model: 'qwen3.8-27b-vision',
        ),
        Uri.parse(
          'http://192.168.100.241:1234/props?model=qwen3.8-27b-vision',
        ),
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

  test('asks the props endpoint about the model, not the chat endpoint',
      () async {
    Uri? requested;
    await probe((request) {
      requested = request.url;
      return _json({
        'modalities': {'video': true},
      });
    });

    expect(
      requested,
      Uri.parse('http://localhost:8080/props?model=qwen3.8-27b-vision'),
    );
  });

  test('reads a real router answer for a video-capable model', () async {
    // Captured from a llama.cpp router at build b10523-d59d455fd. The bare
    // /props on the same server carries no modalities key whatsoever.
    final support = await probe(
      (_) => _json({
        'model_path': '/mnt/storage1/models/qwen3.8/27B/Qwen3.8-27B.gguf',
        'modalities': {'vision': true, 'video': true, 'audio': false},
      }),
    );

    expect(support, EndpointModalitySupport.supported);
  });

  test('a router asked about itself reports unknown, not a refusal', () async {
    final support = await probe(
      (_) => _json({
        'role': 'router',
        'model_path': 'none',
        'max_instances': 2,
        'build_info': 'b10523-d59d455fd',
      }),
    );

    expect(support, EndpointModalitySupport.unknown);
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
