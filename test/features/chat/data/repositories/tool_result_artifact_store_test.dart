import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/repositories/tool_result_artifact_store.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolResultArtifactStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'caverno_tool_result_artifacts_',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('persists large results and returns a preview payload', () async {
      final store = ToolResultArtifactStore(
        baseDirectory: tempDir,
        now: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final largeResult = '${'A' * 7000}needle${'B' * 7000}';

      final persisted = await store.persistIfLarge(
        ToolResultInfo(
          id: 'call/1',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: largeResult,
        ),
        conversationId: 'conversation/1',
        thresholdChars: 1000,
      );

      expect(persisted.result, isNot(largeResult));
      final decoded = jsonDecode(persisted.result) as Map<String, dynamic>;
      expect(decoded['persisted_output'], isTrue);
      expect(decoded['original_char_count'], largeResult.length);
      expect(decoded['preview'], contains('Persisted output preview omitted'));

      final file = File(decoded['file_path'] as String);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), largeResult);
      expect(file.path, contains('tool-results/conversation_1'));
    });

    test('keeps small results inline', () async {
      final store = ToolResultArtifactStore(baseDirectory: tempDir);

      final result = await store.persistIfLarge(
        ToolResultInfo(
          id: 'call-1',
          name: 'web_search',
          arguments: const {},
          result: 'small result',
        ),
        thresholdChars: 1000,
      );

      expect(result.result, 'small result');
      expect(Directory('${tempDir.path}/tool-results').existsSync(), isFalse);
    });

    test('does not persist image payloads', () async {
      final store = ToolResultArtifactStore(baseDirectory: tempDir);
      final imagePayload = jsonEncode({
        'imageBase64': 'A' * 2000,
        'imageMimeType': 'image/png',
      });

      final result = await store.persistIfLarge(
        ToolResultInfo(
          id: 'call-1',
          name: 'computer_screenshot',
          arguments: const {},
          result: imagePayload,
        ),
        thresholdChars: 100,
      );

      expect(result.result, imagePayload);
    });

    test('deletes artifacts for one conversation', () async {
      final store = ToolResultArtifactStore(baseDirectory: tempDir);

      final first = await store.persistIfLarge(
        ToolResultInfo(
          id: 'call-1',
          name: 'read_file',
          arguments: const {},
          result: 'A' * 2000,
        ),
        conversationId: 'conversation-1',
        thresholdChars: 100,
      );
      final second = await store.persistIfLarge(
        ToolResultInfo(
          id: 'call-2',
          name: 'read_file',
          arguments: const {},
          result: 'B' * 2000,
        ),
        conversationId: 'conversation-2',
        thresholdChars: 100,
      );

      final firstFile = File(
        (jsonDecode(first.result) as Map<String, dynamic>)['file_path']
            as String,
      );
      final secondFile = File(
        (jsonDecode(second.result) as Map<String, dynamic>)['file_path']
            as String,
      );

      await store.deleteConversationArtifacts('conversation-1');

      expect(firstFile.existsSync(), isFalse);
      expect(secondFile.existsSync(), isTrue);
    });

    test('deletes old artifact files and keeps recent files', () async {
      final now = DateTime.utc(2026, 1, 10);
      final store = ToolResultArtifactStore(
        baseDirectory: tempDir,
        now: () => now,
      );
      final oldResult = await store.persistIfLarge(
        ToolResultInfo(
          id: 'old-call',
          name: 'read_file',
          arguments: const {},
          result: 'A' * 2000,
        ),
        conversationId: 'conversation-1',
        thresholdChars: 100,
      );
      final recentResult = await store.persistIfLarge(
        ToolResultInfo(
          id: 'recent-call',
          name: 'read_file',
          arguments: const {},
          result: 'B' * 2000,
        ),
        conversationId: 'conversation-2',
        thresholdChars: 100,
      );
      final oldFile = File(
        (jsonDecode(oldResult.result) as Map<String, dynamic>)['file_path']
            as String,
      );
      final recentFile = File(
        (jsonDecode(recentResult.result) as Map<String, dynamic>)['file_path']
            as String,
      );
      oldFile.setLastModifiedSync(now.subtract(const Duration(days: 40)));
      recentFile.setLastModifiedSync(now.subtract(const Duration(days: 2)));

      final deleted = await store.deleteArtifactsOlderThan(
        ToolResultArtifactStore.defaultRetention,
      );

      expect(deleted, 1);
      expect(oldFile.existsSync(), isFalse);
      expect(recentFile.existsSync(), isTrue);
    });
  });
}
