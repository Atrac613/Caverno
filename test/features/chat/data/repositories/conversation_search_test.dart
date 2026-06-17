import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

Conversation _conversation(
  String id, {
  String title = 'Title',
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
  late AppDatabase db;
  late DriftConversationRepository repo;

  setUp(() {
    db = AppDatabase.memory();
    repo = DriftConversationRepository(db);
  });

  tearDown(() async => db.close());

  test('finds a conversation by a word in its title', () async {
    await repo.save(_conversation('a', title: 'Parser refactor'));
    await repo.save(_conversation('b', title: 'Weather app'));

    final results = await repo.search('parser');
    expect(results.map((c) => c.id), ['a']);
  });

  test('finds a conversation by a word in a message body', () async {
    await repo.save(
      _conversation('a', title: 'T1', messages: ['the tokenizer is broken']),
    );
    await repo.save(
      _conversation('b', title: 'T2', messages: ['the weather is nice']),
    );

    final results = await repo.search('tokenizer');
    expect(results.map((c) => c.id), ['a']);
  });

  test('returns empty for no match or a blank query', () async {
    await repo.save(_conversation('a', messages: ['hello']));
    expect(await repo.search('zzznomatch'), isEmpty);
    expect(await repo.search('   '), isEmpty);
  });

  test('delete removes the conversation from the search index', () async {
    await repo.save(_conversation('a', title: 'uniquetoken'));
    expect((await repo.search('uniquetoken')).map((c) => c.id), ['a']);

    await repo.delete('a');
    expect(await repo.search('uniquetoken'), isEmpty);
  });

  test('deleteAll clears the search index', () async {
    await repo.save(_conversation('a', title: 'alpha'));
    await repo.save(_conversation('b', title: 'alpha'));

    await repo.deleteAll();
    expect(await repo.search('alpha'), isEmpty);
  });

  test(
    'rebuild backfills rows inserted without sync (migration path)',
    () async {
      // Insert directly, bypassing repo.save, to simulate a pre-FTS v1 row.
      await db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              id: 'legacy',
              title: const Value('Legacy'),
              payload: jsonEncode(
                _conversation(
                  'legacy',
                  title: 'Legacy',
                  messages: ['indexme please'],
                ).toJson(),
              ),
            ),
          );

      expect(await repo.search('indexme'), isEmpty);
      await db.rebuildConversationSearch();
      expect((await repo.search('indexme')).map((c) => c.id), ['legacy']);
    },
  );
}
