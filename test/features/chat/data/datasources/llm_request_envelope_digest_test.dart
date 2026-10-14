import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_response_telemetry.dart';
import 'package:caverno/features/chat/data/datasources/llm_request_envelope_digest.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/system_prompt_section_registry.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/token_usage.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_sections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' show PromptTokensDetails, Usage;

Message _message(String id, MessageRole role, String content) => Message(
  id: id,
  content: content,
  role: role,
  timestamp: DateTime(2026, 10, 13, 12),
);

const _readFile = {
  'type': 'function',
  'function': {'name': 'read_file', 'description': 'Read a file'},
};
const _listDir = {
  'type': 'function',
  'function': {'name': 'list_directory', 'description': 'List a directory'},
};

LlmRequestEnvelopeDigest _digest({
  String system = 'You are Caverno. Current time: 12:00.',
  List<Message> conversation = const [],
  List<Map<String, dynamic>> tools = const [_readFile],
  double temperature = 0.3,
}) => LlmRequestEnvelopeDigest.compute(
  messages: [_message('s', MessageRole.system, system), ...conversation],
  tools: tools,
  temperature: temperature,
  maxTokens: 900,
);

void main() {
  test('digests stay stable across two requests of one tool loop', () {
    final first = _digest(
      conversation: [_message('u', MessageRole.user, 'Read README')],
    );
    final second = _digest(
      conversation: [
        _message('u', MessageRole.user, 'Read README'),
        _message('a', MessageRole.assistant, 'Reading it.'),
        _message('u2', MessageRole.user, 'Thanks'),
      ],
    );
    expect(second.toJson(), first.toJson());
  });

  test('an unpinned prompt clock changes only the system-prompt digest', () {
    // The per-minute clock re-prefilled 11.4 of 71.7 minutes of one session
    // before it was pinned per turn; this is the shape that regression has.
    final before = _digest(system: 'You are Caverno. Current time: 12:00.');
    final after = _digest(system: 'You are Caverno. Current time: 12:01.');
    expect(after.systemPrompt, isNot(before.systemPrompt));
    expect(after.tools, before.tools);
    expect(after.config, before.config);
  });

  test('a changed tool catalog or config changes its own digest', () {
    final base = _digest();
    final flapped = _digest(tools: const [_readFile, _listDir]);
    expect(flapped.tools, isNot(base.tools));
    expect(flapped.systemPrompt, base.systemPrompt);
    final cooler = _digest(temperature: 0.1);
    expect(cooler.config, isNot(base.config));
    expect(cooler.tools, base.tools);
  });

  test('key order inside a tool definition does not change the digest', () {
    final reordered = {
      'function': {'description': 'Read a file', 'name': 'read_file'},
      'type': 'function',
    };
    expect(_digest(tools: [reordered]).tools, _digest().tools);
  });

  group('session log', () {
    late Directory tempDir;
    late LlmSessionLogStore store;
    const context = LlmSessionLogContext(
      workspaceMode: WorkspaceMode.coding,
      sessionId: 'envelope-1',
      conversationId: 'envelope-1',
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('envelope_digest_');
      store = LlmSessionLogStore(rootDirectoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<Map<String, dynamic>> recordWith(TokenUsage usage) async {
      final now = DateTime.utc(2026, 10, 13);
      await store.record(
        context: context,
        request: LlmSessionLogRequest(
          operation: 'createChatCompletion',
          messages: [_message('s', MessageRole.system, 'You are Caverno.')],
          tools: const [_readFile],
          model: 'model-a',
        ),
        response: LlmSessionLogResponse(content: 'ok', usage: usage),
        startedAt: now,
        finishedAt: now,
      );
      final line = (await (await store.fileForContext(
        context,
      )).readAsLines()).last;
      return jsonDecode(line) as Map<String, dynamic>;
    }

    test('records the envelope and a reported cache miss as 0', () async {
      final usage = ChatResponseTelemetry.extractUsage(
        const Usage(
          promptTokens: 1200,
          completionTokens: 10,
          totalTokens: 1210,
          promptTokensDetails: PromptTokensDetails(cachedTokens: 0),
        ),
      );
      final decoded = await recordWith(usage);
      expect(decoded['schemaVersion'], 7);
      expect(decoded['request']['envelope'], {
        'config': isA<String>(),
        'systemPrompt': isA<String>(),
        'tools': isA<String>(),
      });
      expect(decoded['response']['usage']['cachedPromptTokens'], 0);
    });

    test('records the sections of a registered system prompt', () async {
      SystemPromptSectionRegistry.instance.record('You are Caverno.', const [
        SystemPromptSection('core_principles', 10),
        SystemPromptSection('temporal_context', 6),
      ]);
      final decoded = await recordWith(TokenUsage.zero);
      expect(decoded['request']['systemPromptSections'], [
        {'id': 'core_principles', 'chars': 10},
        {'id': 'temporal_context', 'chars': 6},
      ]);
    });

    test(
      'omits the cache count when the provider never reported one',
      () async {
        final usage = ChatResponseTelemetry.extractUsage(
          const Usage(
            promptTokens: 1200,
            completionTokens: 10,
            totalTokens: 1210,
          ),
        );
        final decoded = await recordWith(usage);
        expect(
          (decoded['response']['usage'] as Map).containsKey(
            'cachedPromptTokens',
          ),
          isFalse,
        );
      },
    );
  });
}
