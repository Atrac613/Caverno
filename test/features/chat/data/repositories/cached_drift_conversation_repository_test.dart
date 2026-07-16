import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/cached_drift_conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';

Conversation _conversation(String id, {required int updatedAtMs}) {
  return Conversation(
    id: id,
    title: 'Title $id',
    messages: const [],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
  );
}

void main() {
  late AppDatabase db;
  late DriftConversationRepository store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftConversationRepository(db);
  });

  tearDown(() async => db.close());

  test('hydrates the cache from the store, newest first', () async {
    await store.save(_conversation('a', updatedAtMs: 10));
    await store.save(_conversation('b', updatedAtMs: 30));
    await store.save(_conversation('c', updatedAtMs: 20));

    final repo = await CachedDriftConversationRepository.hydrate(store);

    expect(repo.getAll().map((c) => c.id), ['b', 'c', 'a']);
    expect(repo.getById('a')!.id, 'a');
    expect(repo.getById('missing'), isNull);
  });

  test(
    'save updates the synchronous cache and writes through to drift',
    () async {
      final repo = await CachedDriftConversationRepository.hydrate(store);

      await repo.save(_conversation('x', updatedAtMs: 5));

      // Synchronous read reflects the write immediately.
      expect(repo.getById('x'), isNotNull);
      // And it persisted: a fresh repository hydrated from the same store sees it.
      final reloaded = await CachedDriftConversationRepository.hydrate(store);
      expect(reloaded.getById('x'), isNotNull);
    },
  );

  test('refresh replaces a stale cache entry from drift', () async {
    await store.save(_conversation('x', updatedAtMs: 5));
    final repo = await CachedDriftConversationRepository.hydrate(store);

    await store.save(_conversation('x', updatedAtMs: 25));
    expect(repo.getById('x')!.updatedAt.millisecondsSinceEpoch, 5);

    final refreshed = await repo.refresh('x');

    expect(refreshed!.updatedAt.millisecondsSinceEpoch, 25);
    expect(repo.getById('x'), same(refreshed));
  });

  test('refresh removes a cache entry deleted from drift', () async {
    await store.save(_conversation('x', updatedAtMs: 5));
    final repo = await CachedDriftConversationRepository.hydrate(store);

    await store.delete('x');
    expect(repo.getById('x'), isNotNull);

    expect(await repo.refresh('x'), isNull);
    expect(repo.getById('x'), isNull);
  });

  test('search delegates to the drift store FTS index', () async {
    final repo = await CachedDriftConversationRepository.hydrate(store);
    await repo.save(_conversation('a', updatedAtMs: 1));

    final results = await repo.search('Title a');
    expect(results.map((c) => c.id), ['a']);
    expect(await repo.search('nomatchxyz'), isEmpty);
  });

  test('delete and deleteAll clear the cache and drift together', () async {
    final repo = await CachedDriftConversationRepository.hydrate(store);
    await repo.save(_conversation('a', updatedAtMs: 1));
    await repo.save(_conversation('b', updatedAtMs: 2));

    await repo.delete('a');
    expect(repo.getById('a'), isNull);
    expect((await store.getAll()).map((c) => c.id), ['b']);

    await repo.deleteAll();
    expect(repo.getAll(), isEmpty);
    expect(await store.getAll(), isEmpty);
  });
}
