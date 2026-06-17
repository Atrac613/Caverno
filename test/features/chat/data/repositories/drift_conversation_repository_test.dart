import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';

Conversation _conversation(
  String id, {
  String title = 'Title',
  required DateTime updatedAt,
}) {
  final created = DateTime.fromMillisecondsSinceEpoch(0);
  return Conversation(
    id: id,
    title: title,
    messages: const [],
    createdAt: created,
    updatedAt: updatedAt,
  );
}

void main() {
  late AppDatabase db;
  late DriftConversationRepository repo;

  setUp(() {
    db = AppDatabase.memory();
    repo = DriftConversationRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('round-trips a conversation, preserving entity fields', () async {
    final conversation = _conversation(
      'c1',
      title: 'Parser work',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await repo.save(conversation);

    final loaded = await repo.getById('c1');
    expect(loaded, isNotNull);
    expect(loaded!.id, 'c1');
    expect(loaded.title, 'Parser work');
    expect(loaded.updatedAt, DateTime.fromMillisecondsSinceEpoch(1000));
  });

  test('getAll returns conversations most-recently-updated first', () async {
    await repo.save(
      _conversation('old', updatedAt: DateTime.fromMillisecondsSinceEpoch(10)),
    );
    await repo.save(
      _conversation('new', updatedAt: DateTime.fromMillisecondsSinceEpoch(99)),
    );
    await repo.save(
      _conversation('mid', updatedAt: DateTime.fromMillisecondsSinceEpoch(50)),
    );

    final all = await repo.getAll();
    expect(all.map((c) => c.id), ['new', 'mid', 'old']);
  });

  test('save upserts on the same id', () async {
    await repo.save(
      _conversation(
        'c1',
        title: 'First',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );
    await repo.save(
      _conversation(
        'c1',
        title: 'Renamed',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
      ),
    );

    final all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.single.title, 'Renamed');
  });

  test('delete removes one and deleteAll clears the store', () async {
    await repo.save(
      _conversation('a', updatedAt: DateTime.fromMillisecondsSinceEpoch(1)),
    );
    await repo.save(
      _conversation('b', updatedAt: DateTime.fromMillisecondsSinceEpoch(2)),
    );

    await repo.delete('a');
    expect((await repo.getAll()).map((c) => c.id), ['b']);
    expect(await repo.getById('a'), isNull);

    await repo.deleteAll();
    expect(await repo.getAll(), isEmpty);
  });

  test('skips a row whose payload is not valid conversation json', () async {
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: 'broken',
            payload: 'not json',
            updatedAtMs: const Value(5),
          ),
        );
    await repo.save(
      _conversation('ok', updatedAt: DateTime.fromMillisecondsSinceEpoch(1)),
    );

    final all = await repo.getAll();
    expect(all.map((c) => c.id), ['ok']);
    expect(await repo.getById('broken'), isNull);
  });
}
