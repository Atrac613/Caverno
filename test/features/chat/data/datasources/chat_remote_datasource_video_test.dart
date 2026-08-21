import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/video_delivery.dart';

const String _videoUrl = 'http://192.168.1.5:49152/v/token';

Message _videoMessage({
  String id = 'message-video',
  String content = 'what happens in this clip?',
  bool isSynthesizedPrompt = false,
}) => Message(
  id: id,
  content: content,
  role: MessageRole.user,
  timestamp: DateTime(2026),
  videoPath: '/tmp/clip.mp4',
  videoMimeType: 'video/mp4',
  isSynthesizedPrompt: isSynthesizedPrompt,
);

http.Response _completion() => http.Response(
  jsonEncode({
    'id': 'completion-1',
    'object': 'chat.completion',
    'created': 0,
    'model': 'test-model',
    'choices': [
      {
        'index': 0,
        'message': {'role': 'assistant', 'content': 'done'},
        'finish_reason': 'stop',
      },
    ],
  }),
  200,
  headers: const {'content-type': 'application/json'},
);

/// Sends [messages] and returns the JSON body that reached the wire.
Future<Map<String, dynamic>> send(
  List<Message> messages, {
  Map<String, VideoDelivery> resolved = const {
    'message-video': VideoDelivery.url(_videoUrl),
  },
}) async {
  late Map<String, dynamic> body;
  final client = MockClient((request) async {
    body = jsonDecode(request.body) as Map<String, dynamic>;
    return _completion();
  });
  final dataSource = ChatRemoteDataSource(
    baseUrl: 'http://localhost:1234/v1',
    apiKey: 'no-key',
    httpClient: client,
    videoAttachmentResolver: (_) async => resolved,
  );

  await dataSource.createChatCompletion(
    messages: messages,
    model: 'test-model',
  );
  return body;
}

List<dynamic> _partsOfFirstMessage(Map<String, dynamic> body) =>
    (body['messages'] as List).first['content'] as List<dynamic>;

void main() {
  test('sends the video as a video_url part beside the text', () async {
    final body = await send([_videoMessage()]);

    final parts = _partsOfFirstMessage(body);
    expect(parts, hasLength(2));
    expect(parts[0]['text'], 'what happens in this clip?');
    expect(parts[1], {
      'type': 'video_url',
      'video_url': {'url': _videoUrl},
    });
  });

  test('names the omission when the video is not carried', () async {
    final body = await send([_videoMessage()], resolved: const {});

    final content = (body['messages'] as List).first['content'];
    expect(
      content,
      'what happens in this clip?\n\n'
      '[video attachment omitted from this request]',
    );
  });

  test('never leaves the internal marker in the prompt', () async {
    final body = await send([_videoMessage()]);

    expect(jsonEncode(body), isNot(contains('caverno-video')));
  });

  test('sends a video-only message with no empty text part', () async {
    final body = await send([_videoMessage(content: '')]);

    final parts = _partsOfFirstMessage(body);
    expect(parts, hasLength(1));
    expect(parts.single['type'], 'video_url');
  });

  test('does not disturb a request that carries no video', () async {
    final body = await send([
      Message(
        id: 'plain',
        content: 'hello',
        role: MessageRole.user,
        timestamp: DateTime(2026),
      ),
    ], resolved: const {});

    expect((body['messages'] as List).first['content'], 'hello');
  });
}
