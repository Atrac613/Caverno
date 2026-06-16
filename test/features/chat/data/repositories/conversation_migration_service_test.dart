import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/conversation_migration_service.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';

Conversation _conversation(String id) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Conversation(
    id: id,
    title: 'Title $id',
    messages: const [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const service = ConversationMigrationService();
  late AppDatabase db;
  late DriftConversationRepository target;

  setUp(() {
    db = AppDatabase.memory();
    target = DriftConversationRepository(db);
  });

  tearDown(() async => db.close());

  test('imports legacy conversations and marks migration done', () async {
    var marked = false;
    var reads = 0;

    final result = await service.migrateIfNeeded(
      alreadyMigrated: false,
      readLegacyConversations: () async {
        reads += 1;
        return [_conversation('a'), _conversation('b')];
      },
      target: target,
      markMigrated: () async => marked = true,
    );

    expect(result.migratedCount, 2);
    expect(result.skippedAlreadyMigrated, isFalse);
    expect(marked, isTrue);
    expect(reads, 1);
    expect((await target.getAll()).map((c) => c.id).toSet(), {'a', 'b'});
  });

  test('skips entirely when already migrated (never reads Hive)', () async {
    var reads = 0;
    var marked = false;

    final result = await service.migrateIfNeeded(
      alreadyMigrated: true,
      readLegacyConversations: () async {
        reads += 1;
        return [_conversation('a')];
      },
      target: target,
      markMigrated: () async => marked = true,
    );

    expect(result.skippedAlreadyMigrated, isTrue);
    expect(result.migratedCount, 0);
    expect(reads, 0, reason: 'no legacy read after migration');
    expect(marked, isFalse);
    expect(await target.getAll(), isEmpty);
  });

  test('marks migration done even with no legacy conversations', () async {
    var marked = false;
    final result = await service.migrateIfNeeded(
      alreadyMigrated: false,
      readLegacyConversations: () async => const [],
      target: target,
      markMigrated: () async => marked = true,
    );

    expect(result.migratedCount, 0);
    expect(result.skippedAlreadyMigrated, isFalse);
    expect(marked, isTrue);
  });

  test('a retried import does not duplicate rows (upsert by id)', () async {
    Future<void> runOnce() => service.migrateIfNeeded(
      alreadyMigrated: false,
      readLegacyConversations: () async => [_conversation('a')],
      target: target,
      markMigrated: () async {},
    );

    await runOnce();
    await runOnce(); // simulates an interrupted-then-retried migration

    expect(await target.getAll(), hasLength(1));
  });
}
