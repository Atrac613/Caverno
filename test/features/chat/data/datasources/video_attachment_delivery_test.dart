import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/media_host_listen_policy.dart';
import 'package:caverno/core/services/media_host_service.dart';
import 'package:caverno/features/chat/data/datasources/video_attachment_delivery.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/video_delivery.dart';

final Uri _localEndpoint = Uri.parse('http://127.0.0.1:1234/v1');
final Uri _cloudEndpoint = Uri.parse('https://api.example.com/v1');

Message _userMessage({
  String id = 'm1',
  String content = 'what happens here?',
  String? videoPath,
  String? videoUrl,
  bool isSynthesizedPrompt = false,
}) => Message(
  id: id,
  content: content,
  role: MessageRole.user,
  timestamp: DateTime(2026, 8, 21),
  videoPath: videoPath,
  videoUrl: videoUrl,
  isSynthesizedPrompt: isSynthesizedPrompt,
);

Message _assistantMessage(String id) => Message(
  id: id,
  content: 'a reply',
  role: MessageRole.assistant,
  timestamp: DateTime(2026, 8, 21),
);

void main() {
  late Directory tempDir;
  late File videoFile;
  late MediaHostService mediaHost;
  late VideoAttachmentDelivery delivery;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video_delivery_test');
    videoFile = File('${tempDir.path}/clip.mp4');
    await videoFile.writeAsBytes(<int>[0, 1, 2, 3, 4, 5, 6, 7]);
    mediaHost = MediaHostService();
    delivery = VideoAttachmentDelivery(mediaHost: mediaHost);
  });

  tearDown(() async {
    await mediaHost.stop();
    await tempDir.delete(recursive: true);
  });

  test('publishes a local file as a URL the endpoint can fetch', () async {
    final resolved = await delivery.resolve(
      [_userMessage(videoPath: videoFile.path)],
      endpoint: _localEndpoint,
    );

    expect(resolved.keys, ['m1']);
    expect(resolved['m1']!.url, startsWith('http://127.0.0.1:'));
    expect(resolved['m1']!.mode, VideoDeliveryMode.url);
    expect(mediaHost.isRunning, isTrue);
  });

  test('inlines when no address could reach the endpoint', () async {
    final offline = VideoAttachmentDelivery(
      mediaHost: MediaHostService(
        policy: MediaHostListenPolicy(interfaces: () => const []),
      ),
    );

    final resolved = await offline.resolve(
      [_userMessage(videoPath: videoFile.path)],
      endpoint: _cloudEndpoint,
    );

    expect(resolved['m1']!.url, 'data:video/mp4;base64,${base64Encode(<int>[
      0, 1, 2, 3, 4, 5, 6, 7,
    ])}');
    expect(resolved['m1']!.mode, VideoDeliveryMode.inline);
    expect(
      resolved['m1']!.loggableUrl,
      startsWith('data: URI ('),
      reason: 'a log must not carry megabytes of the person\'s video',
    );
  });

  test('remembers an unreachable endpoint instead of retrying discovery',
      () async {
    final host = _CountingMediaHost(
      policy: MediaHostListenPolicy(interfaces: () => const []),
    );
    final offline = VideoAttachmentDelivery(mediaHost: host);

    for (var i = 0; i < 3; i++) {
      await offline.resolve(
        [_userMessage(videoPath: videoFile.path)],
        endpoint: _cloudEndpoint,
      );
    }

    expect(host.publishCalls, 1);
  });

  test('a failed publish inlines once without writing the endpoint off',
      () async {
    final host = _ThrowingMediaHost();
    final flaky = VideoAttachmentDelivery(mediaHost: host);

    final first = await flaky.resolve(
      [_userMessage(videoPath: videoFile.path)],
      endpoint: _localEndpoint,
    );
    final second = await flaky.resolve(
      [_userMessage(videoPath: videoFile.path)],
      endpoint: _localEndpoint,
    );

    expect(first['m1']!.url, startsWith('data:video/mp4;base64,'));
    expect(second['m1']!.url, startsWith('data:video/mp4;base64,'));
    // A bind that failed for a passing reason is retried, unlike a network
    // with no address the endpoint could ever reach.
    expect(host.publishCalls, 2);
  });

  test('hands a typed URL over verbatim', () async {
    final resolved = await delivery.resolve(
      [_userMessage(videoUrl: 'https://cdn.example.com/clip.mp4')],
      endpoint: _cloudEndpoint,
    );

    expect(resolved['m1']!.url, 'https://cdn.example.com/clip.mp4');
    expect(mediaHost.isRunning, isFalse);
  });

  test('sends nothing when the latest turn carries no video', () async {
    final resolved = await delivery.resolve(
      [
        _userMessage(id: 'old', videoPath: videoFile.path),
        _assistantMessage('a1'),
        _userMessage(id: 'new'),
      ],
      endpoint: _localEndpoint,
    );

    expect(resolved, isEmpty);
  });

  test('looks past a prompt Caverno composed itself', () async {
    // The tool-result envelope is sent as a user message but is not the
    // person's turn; treating it as the latest one dropped the attachment.
    final resolved = await delivery.resolve(
      [
        _userMessage(id: 'real', videoPath: videoFile.path),
        _assistantMessage('a1'),
        _userMessage(id: 'envelope', isSynthesizedPrompt: true),
      ],
      endpoint: _localEndpoint,
    );

    expect(resolved.keys, ['real']);
  });

  test('sends nothing when the file has gone missing', () async {
    await videoFile.delete();

    final resolved = await delivery.resolve(
      [_userMessage(videoPath: videoFile.path)],
      endpoint: _localEndpoint,
    );

    expect(resolved, isEmpty);
  });
}

class _CountingMediaHost extends MediaHostService {
  _CountingMediaHost({required super.policy});

  int publishCalls = 0;

  @override
  Future<MediaHostTicket?> publish({
    required File file,
    required String mimeType,
    required Uri endpoint,
  }) {
    publishCalls++;
    return super.publish(file: file, mimeType: mimeType, endpoint: endpoint);
  }
}


class _ThrowingMediaHost extends MediaHostService {
  int publishCalls = 0;

  @override
  Future<MediaHostTicket?> publish({
    required File file,
    required String mimeType,
    required Uri endpoint,
  }) async {
    publishCalls++;
    throw const SocketException('bind failed');
  }
}
