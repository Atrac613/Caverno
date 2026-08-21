import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_completion_terminal_metadata.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('caverno_video_log_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Records one turn carrying [message] and returns the logged request.
  Future<Map<String, dynamic>> logRequestFor(Message message) async {
    final store = LlmSessionLogStore(rootDirectoryProvider: () async => tempDir);
    final startedAt = DateTime(2026, 8, 21, 15, 31);
    await store.record(
      context: const LlmSessionLogContext(
        workspaceMode: WorkspaceMode.chat,
        sessionId: 'conversation/1',
        conversationId: 'conversation/1',
      ),
      request: LlmSessionLogRequest(
        operation: 'streamChatCompletionWithTools',
        messages: [message],
        model: 'model-a',
        temperature: 0.2,
        maxTokens: 1000,
      ),
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(milliseconds: 10)),
      response: const LlmSessionLogResponse(
        content: 'ok',
        finishReason: 'stop',
        usage: TokenUsage.zero,
      ),
    );
    final file = tempDir
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.jsonl'));
    final entry =
        jsonDecode(file.readAsLinesSync().last) as Map<String, dynamic>;
    return entry['request'] as Map<String, dynamic>;
  }

  Message videoMessage({String? path, String? url}) => Message(
    id: 'user-1',
    content: '動画を解析',
    role: MessageRole.user,
    timestamp: DateTime(2026, 8, 21, 15, 31),
    videoPath: path,
    videoUrl: url,
    videoMimeType: path == null ? null : 'video/quicktime',
    videoSizeBytes: path == null ? null : 7932096,
    videoDurationMs: path == null ? null : 8200,
  );

  test('a logged turn names the video file it carried', () async {
    // Without this the log shows a bare text turn, and a turn that answered
    // without the attachment cannot be told from one that never had it.
    final request = await logRequestFor(
      videoMessage(path: '/Users/someone/Desktop/IMG_8129.mov'),
    );

    final video =
        (request['messages'] as List).single['video'] as Map<String, dynamic>;
    expect(video['path'], '/Users/someone/Desktop/IMG_8129.mov');
    expect(video['mediaType'], 'video/quicktime');
    expect(video['sizeBytes'], 7932096);
    expect(video['durationMs'], 8200);
    expect(video.containsKey('url'), isFalse);
  });

  test('a typed URL is recorded as a URL, not a path', () async {
    final request = await logRequestFor(
      videoMessage(url: 'https://cdn.example.com/clip.mp4'),
    );

    final video =
        (request['messages'] as List).single['video'] as Map<String, dynamic>;
    expect(video['url'], 'https://cdn.example.com/clip.mp4');
    expect(video.containsKey('path'), isFalse);
    expect(video['mediaType'], 'video/mp4', reason: 'the default container');
  });

  test('a turn with no video carries no video block', () async {
    final request = await logRequestFor(
      Message(
        id: 'user-1',
        content: 'hello',
        role: MessageRole.user,
        timestamp: DateTime(2026, 8, 21),
      ),
    );

    expect(
      (request['messages'] as List).single.containsKey('video'),
      isFalse,
    );
  });
}
