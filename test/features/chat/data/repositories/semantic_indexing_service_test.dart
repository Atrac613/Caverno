import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/embeddings_client.dart';
import 'package:caverno/features/chat/data/repositories/conversation_chunker.dart';
import 'package:caverno/features/chat/data/repositories/drift_embedding_store.dart';
import 'package:caverno/features/chat/data/repositories/semantic_indexing_service.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conversation(
  String id, {
  String title = '',
  List<String> messages = const [],
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Conversation(
    id: id,
    title: title,
    messages: [
      for (var i = 0; i < messages.length; i += 1)
        Message(
          id: '$id-$i',
          content: messages[i],
          role: MessageRole.user,
          timestamp: now,
        ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('ConversationChunker', () {
    test('chunks title then non-empty messages, collapsing whitespace', () {
      final chunks = const ConversationChunker().chunk(
        _conversation(
          'a',
          title: 'My   Title',
          messages: ['  hello\n\nworld ', '', 'second'],
        ),
      );
      expect(chunks.map((c) => c.text), ['My Title', 'hello world', 'second']);
      expect(chunks.map((c) => c.index), [0, 1, 2]);
    });

    test('caps text length and adds an ellipsis snippet', () {
      final long = 'x' * 5000;
      final chunks = const ConversationChunker(
        maxCharsPerChunk: 100,
        maxSnippetChars: 10,
      ).chunk(_conversation('a', title: long));
      expect(chunks.single.text.length, 100);
      expect(chunks.single.snippet, '${'x' * 10}…');
    });
  });

  group('SemanticIndexingService', () {
    late AppDatabase db;
    late DriftEmbeddingStore store;

    setUp(() {
      db = AppDatabase.memory();
      store = DriftEmbeddingStore(db);
    });
    tearDown(() async => db.close());

    SemanticIndexingService service(EmbedTexts embed) =>
        SemanticIndexingService(embed: embed, store: store, model: 'm');

    test('embeds chunks and stores one row per chunk', () async {
      final svc = service(
        (inputs) async => EmbeddingsResult(
          vectors: [
            for (var i = 0; i < inputs.length; i += 1) [i.toDouble(), 1],
          ],
          model: 'm',
        ),
      );
      final ok = await svc.indexConversation(
        _conversation('a', title: 'T', messages: ['one', 'two']),
      );
      expect(ok, isTrue);
      expect(await store.count(), 3); // title + 2 messages
    });

    test(
      'splits by input count and request bytes without losing order',
      () async {
        final batches = <List<String>>[];
        final svc = SemanticIndexingService(
          embed: (inputs) async {
            batches.add([...inputs]);
            return EmbeddingsResult(
              vectors: [
                for (final input in inputs) [double.parse(input.substring(1))],
              ],
              model: 'm',
            );
          },
          store: store,
          model: 'm',
          maxInputsPerRequest: 2,
          maxRequestBytes: 55,
        );
        final ok = await svc.indexConversation(
          _conversation('a', messages: ['x1', 'x2', 'x3', 'x4']),
        );
        expect(ok, isTrue);
        expect(batches.expand((batch) => batch), ['x1', 'x2', 'x3', 'x4']);
        expect(batches.every((batch) => batch.length <= 2), isTrue);
        expect(
          batches.every(
            (batch) =>
                utf8
                    .encode(jsonEncode({'model': 'm', 'input': batch}))
                    .length <=
                55,
          ),
          isTrue,
        );
        expect(await store.count(), 4);
      },
    );

    test('splits multibyte inputs before the byte limit', () async {
      final batches = <List<String>>[];
      final svc = SemanticIndexingService(
        embed: (inputs) async {
          batches.add([...inputs]);
          return EmbeddingsResult(
            vectors: [
              for (final _ in inputs) [1.0],
            ],
            model: 'm',
          );
        },
        store: store,
        model: 'm',
        maxRequestBytes: 60,
      );
      expect(
        await svc.indexConversation(
          _conversation('a', messages: ['日本語の入力', '日本語の入力']),
        ),
        isTrue,
      );
      expect(batches, hasLength(2));
      expect(batches.every((batch) => batch.length == 1), isTrue);
      expect(
        batches.every(
          (batch) =>
              utf8.encode(jsonEncode({'model': 'm', 'input': batch})).length <=
              60,
        ),
        isTrue,
      );
    });

    test('keeps the previous index when a later batch fails', () async {
      final initial = service(
        (inputs) async => EmbeddingsResult(
          vectors: [
            for (final _ in inputs) [1.0],
          ],
          model: 'm',
        ),
      );
      expect(
        await initial.indexConversation(_conversation('a', title: 'old')),
        isTrue,
      );

      var calls = 0;
      final replacement = SemanticIndexingService(
        embed: (inputs) async {
          calls++;
          if (calls == 2) return null;
          return EmbeddingsResult(
            vectors: [
              for (final _ in inputs) [2.0],
            ],
            model: 'm',
          );
        },
        store: store,
        model: 'm',
        maxInputsPerRequest: 1,
      );
      expect(
        await replacement.indexConversation(
          _conversation('a', title: 'new', messages: ['next']),
        ),
        isFalse,
      );
      expect(calls, 2);
      expect(await store.count(), 1);
    });

    test(
      'returns false and stores nothing when embeddings are unavailable',
      () async {
        final svc = service((inputs) async => null);
        final ok = await svc.indexConversation(
          _conversation('a', title: 'T', messages: ['one']),
        );
        expect(ok, isFalse);
        expect(await store.count(), 0);
      },
    );

    test('returns false on a vector-count mismatch', () async {
      final svc = service(
        (inputs) async => EmbeddingsResult(
          vectors: const [
            [1, 0],
          ],
          model: 'm',
        ),
      );
      final ok = await svc.indexConversation(
        _conversation('a', title: 'T', messages: ['one', 'two']),
      );
      expect(ok, isFalse);
      expect(await store.count(), 0);
    });

    test('clears the index for an empty conversation', () async {
      final svc = service(
        (inputs) async => EmbeddingsResult(
          vectors: const [
            [1, 0],
          ],
          model: 'm',
        ),
      );
      await svc.indexConversation(_conversation('a', title: 'T'));
      expect(await store.count(), 1);

      final ok = await svc.indexConversation(_conversation('a'));
      expect(ok, isTrue);
      expect(await store.count(), 0);
    });

    test('deleteConversation removes only the given conversation', () async {
      final svc = service(
        (inputs) async => EmbeddingsResult(
          vectors: [
            for (var i = 0; i < inputs.length; i += 1) [i.toDouble(), 1],
          ],
          model: 'm',
        ),
      );
      await svc.indexConversation(_conversation('a', title: 'A'));
      await svc.indexConversation(_conversation('b', title: 'B'));
      expect(await store.count(), 2);

      await svc.deleteConversation('a');
      expect(await store.count(), 1);
    });
  });
}
