import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:caverno/features/chat/data/datasources/video_content_part_client.dart';
import 'package:caverno/features/chat/domain/entities/video_attachment_part.dart';

/// Captures the request the interceptor hands down, exactly as it hands it.
class _CapturingClient extends http.BaseClient {
  http.Request? captured;
  String? capturedBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    captured = request as http.Request;
    capturedBody = request.body;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}

http.Request _chatRequest(Object body) =>
    http.Request('POST', Uri.parse('http://localhost:1234/v1/chat/completions'))
      ..body = jsonEncode(body);

Map<String, dynamic> _bodyWithParts(List<Object> parts) => <String, dynamic>{
  'model': 'test',
  'messages': <Object>[
    <String, dynamic>{'role': 'user', 'content': parts},
  ],
};

List<dynamic> _partsOf(String body) =>
    (jsonDecode(body) as Map)['messages'][0]['content'] as List<dynamic>;

void main() {
  test('rewrites the marker into a video_url content part', () async {
    final inner = _CapturingClient();
    final client = VideoContentPartClient(delegate: inner);

    await client.send(
      _chatRequest(
        _bodyWithParts(<Object>[
          <String, dynamic>{'type': 'text', 'text': 'what happens here?'},
          <String, dynamic>{
            'type': 'text',
            'text': VideoAttachmentPart.encode('http://192.168.1.5:5000/v/tok'),
          },
        ]),
      ),
    );

    final parts = _partsOf(inner.capturedBody!);
    expect(parts, hasLength(2));
    expect(parts[0], <String, dynamic>{
      'type': 'text',
      'text': 'what happens here?',
    });
    expect(parts[1], <String, dynamic>{
      'type': 'video_url',
      'video_url': <String, dynamic>{'url': 'http://192.168.1.5:5000/v/tok'},
    });
  });

  test('carries a data URI through unchanged', () async {
    final inner = _CapturingClient();
    const dataUri = 'data:video/mp4;base64,AAAAIGZ0eXA=';

    await VideoContentPartClient(delegate: inner).send(
      _chatRequest(
        _bodyWithParts(<Object>[
          <String, dynamic>{
            'type': 'text',
            'text': VideoAttachmentPart.encode(dataUri),
          },
        ]),
      ),
    );

    expect(_partsOf(inner.capturedBody!).single, <String, dynamic>{
      'type': 'video_url',
      'video_url': <String, dynamic>{'url': dataUri},
    });
  });

  test('rewrites a marker in every message that carries one', () async {
    final inner = _CapturingClient();
    await VideoContentPartClient(delegate: inner).send(
      _chatRequest(<String, dynamic>{
        'model': 'test',
        'messages': <Object>[
          <String, dynamic>{
            'role': 'user',
            'content': <Object>[
              <String, dynamic>{
                'type': 'text',
                'text': VideoAttachmentPart.encode('http://host/v/a'),
              },
            ],
          },
          <String, dynamic>{'role': 'assistant', 'content': 'ok'},
          <String, dynamic>{
            'role': 'user',
            'content': <Object>[
              <String, dynamic>{
                'type': 'text',
                'text': VideoAttachmentPart.encode('http://host/v/b'),
              },
            ],
          },
        ],
      }),
    );

    final messages = (jsonDecode(inner.capturedBody!) as Map)['messages'];
    expect(messages[0]['content'][0]['video_url']['url'], 'http://host/v/a');
    expect(messages[1]['content'], 'ok');
    expect(messages[2]['content'][0]['video_url']['url'], 'http://host/v/b');
  });

  test('leaves a body with no marker byte for byte', () async {
    final inner = _CapturingClient();
    final request = _chatRequest(
      _bodyWithParts(<Object>[
        <String, dynamic>{'type': 'text', 'text': 'no video here'},
      ]),
    );
    final original = request.body;

    await VideoContentPartClient(delegate: inner).send(request);

    expect(inner.capturedBody, original);
  });

  test('ignores a request that is not a chat completion', () async {
    final inner = _CapturingClient();
    final request =
        http.Request('POST', Uri.parse('http://localhost:1234/v1/embeddings'))
          ..body = jsonEncode(
            _bodyWithParts(<Object>[
              <String, dynamic>{
                'type': 'text',
                'text': VideoAttachmentPart.encode('http://host/v/a'),
              },
            ]),
          );
    final original = request.body;

    await VideoContentPartClient(delegate: inner).send(request);

    expect(inner.capturedBody, original);
  });
}
