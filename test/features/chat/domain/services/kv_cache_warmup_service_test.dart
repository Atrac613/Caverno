import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/kv_cache_warmup_service.dart';

void main() {
  group('KvCacheWarmupService', () {
    test('sends a minimal system + user prefix with the tool list', () async {
      List<Message>? sentMessages;
      List<Map<String, dynamic>>? sentTools;
      int? sentMaxTokens;
      double? sentTemperature;

      final outcome = await const KvCacheWarmupService().warm(
        systemPrompt: 'You are a coding assistant.\n<repo_map>...</repo_map>',
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'read_file'},
          },
        ],
        send:
            ({
              required messages,
              required tools,
              required maxTokens,
              required temperature,
            }) async {
              sentMessages = messages;
              sentTools = tools;
              sentMaxTokens = maxTokens;
              sentTemperature = temperature;
            },
      );

      expect(outcome.status, KvCacheWarmupStatus.warmed);
      expect(outcome.detail, contains('1 tool(s)'));
      expect(sentMessages!.map((m) => m.role), [
        MessageRole.system,
        MessageRole.user,
      ]);
      expect(sentMessages!.first.content, contains('<repo_map>'));
      expect(sentTools, hasLength(1));
      // Only the prefill matters: a single greedy token.
      expect(sentMaxTokens, 1);
      expect(sentTemperature, 0.0);
    });

    test('skips an empty system prompt without sending', () async {
      var sent = false;
      final outcome = await const KvCacheWarmupService().warm(
        systemPrompt: '   ',
        tools: const [],
        send:
            ({
              required messages,
              required tools,
              required maxTokens,
              required temperature,
            }) async {
              sent = true;
            },
      );

      expect(outcome.status, KvCacheWarmupStatus.skipped);
      expect(outcome.detail, contains('empty system prompt'));
      expect(sent, isFalse);
    });

    test(
      'reports failed when the sender throws (unreachable endpoint)',
      () async {
        final outcome = await const KvCacheWarmupService().warm(
          systemPrompt: 'prompt',
          tools: const [],
          send:
              ({
                required messages,
                required tools,
                required maxTokens,
                required temperature,
              }) async {
                throw Exception('connection refused');
              },
        );

        expect(outcome.status, KvCacheWarmupStatus.failed);
        expect(outcome.detail, contains('connection refused'));
      },
    );
  });
}
