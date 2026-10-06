import 'dart:async';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/embeddings_client.dart';
import 'package:caverno/features/chat/data/repositories/drift_embedding_store.dart';
import 'package:caverno/features/chat/data/repositories/semantic_indexing_service.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/conversation_semantic_index_sync.dart';
import 'package:caverno/features/chat/presentation/providers/semantic_search_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conversation(String title) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Conversation(
    id: 'conversation',
    title: title,
    messages: const [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('coalesces newer saves behind one active embedding job', () async {
    final db = AppDatabase.memory();
    final store = DriftEmbeddingStore(db);
    final firstStarted = Completer<void>();
    final firstRelease = Completer<void>();
    final secondStarted = Completer<void>();
    final secondRelease = Completer<void>();
    var active = 0;
    var maximumActive = 0;
    var calls = 0;
    final indexer = SemanticIndexingService(
      embed: (inputs) async => null,
      embedWithCancellation: (inputs, signal) async {
        calls++;
        active++;
        if (active > maximumActive) maximumActive = active;
        if (calls == 1) {
          firstStarted.complete();
          await firstRelease.future;
          active--;
          return EmbeddingsResult(
            vectors: const [
              [1.0, 0.0],
            ],
            model: 'm',
          );
        }
        secondStarted.complete();
        await secondRelease.future;
        active--;
        return EmbeddingsResult(
          vectors: const [
            [0.0, 1.0],
          ],
          model: 'm',
        );
      },
      store: store,
      model: 'm',
    );
    final syncProvider = Provider<ConversationSemanticIndexSync>(
      ConversationSemanticIndexSync.new,
    );
    final container = ProviderContainer(
      overrides: [semanticIndexingServiceProvider.overrideWithValue(indexer)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final sync = container.read(syncProvider);
    sync.schedule(_conversation('old'));
    await firstStarted.future;
    sync.schedule(_conversation('old'));
    sync.schedule(_conversation('new'));
    sync.schedule(_conversation('newest'));
    expect(calls, 1);
    expect(secondStarted.isCompleted, isFalse);
    firstRelease.complete();
    await secondStarted.future.timeout(const Duration(seconds: 1));
    expect(maximumActive, 1);
    expect(calls, 2);
    secondRelease.complete();
    for (var attempt = 0; attempt < 50 && await store.count() == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await store.count(), 1);
    final matches = await store.search(queryVector: [0, 1]);
    expect(matches.single.snippet, 'newest');
  });

  test('deleting a conversation cancels its active embedding', () async {
    final db = AppDatabase.memory();
    final store = DriftEmbeddingStore(db);
    final started = Completer<void>();
    final cancelled = Completer<void>();
    final indexer = SemanticIndexingService(
      embed: (inputs) async => null,
      embedWithCancellation: (inputs, signal) async {
        started.complete();
        await signal;
        cancelled.complete();
        return null;
      },
      store: store,
      model: 'm',
    );
    final syncProvider = Provider<ConversationSemanticIndexSync>(
      ConversationSemanticIndexSync.new,
    );
    final container = ProviderContainer(
      overrides: [semanticIndexingServiceProvider.overrideWithValue(indexer)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final sync = container.read(syncProvider);
    sync.schedule(_conversation('old'));
    await started.future;
    sync.remove(['conversation']);
    await cancelled.future.timeout(const Duration(seconds: 1));
    expect(await store.count(), 0);
  });
}
