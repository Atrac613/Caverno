import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_migration_service.dart';
import 'package:caverno/features/chat/data/repositories/drift_chat_memory_store.dart';

void main() {
  late AppDatabase db;
  late DriftChatMemoryStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftChatMemoryStore(db);
  });

  tearDown(() async => db.close());

  group('DriftChatMemoryStore', () {
    test('round-trips, upserts, and deletes key/value blobs', () async {
      expect(await store.getValue('profile'), isNull);

      await store.setValue('profile', '{"persona":"dev"}');
      expect(await store.getValue('profile'), '{"persona":"dev"}');

      await store.setValue('profile', '{"persona":"engineer"}');
      expect(await store.getValue('profile'), '{"persona":"engineer"}');

      await store.setValue('memories', '[]');
      expect(await store.getAll(), {
        'profile': '{"persona":"engineer"}',
        'memories': '[]',
      });

      await store.deleteValue('profile');
      expect(await store.getValue('profile'), isNull);
      expect(await store.getAll(), {'memories': '[]'});
    });
  });

  group('ChatMemoryMigrationService', () {
    const service = ChatMemoryMigrationService();

    test('imports legacy blobs once and marks migration done', () async {
      var marked = false;
      var reads = 0;

      final result = await service.migrateIfNeeded(
        alreadyMigrated: false,
        readLegacyEntries: () async {
          reads += 1;
          return {'profile': '{"a":1}', 'memories': '[{"text":"x"}]'};
        },
        target: store,
        markMigrated: () async => marked = true,
      );

      expect(result.migratedCount, 2);
      expect(result.skippedAlreadyMigrated, isFalse);
      expect(marked, isTrue);
      expect(reads, 1);
      expect(await store.getValue('profile'), '{"a":1}');
      expect(await store.getValue('memories'), '[{"text":"x"}]');
    });

    test('skips entirely when already migrated', () async {
      var reads = 0;
      final result = await service.migrateIfNeeded(
        alreadyMigrated: true,
        readLegacyEntries: () async {
          reads += 1;
          return {'profile': '{"a":1}'};
        },
        target: store,
        markMigrated: () async {},
      );

      expect(result.skippedAlreadyMigrated, isTrue);
      expect(reads, 0);
      expect(await store.getAll(), isEmpty);
    });

    test(
      'a retried import does not duplicate values (upsert by key)',
      () async {
        Future<void> runOnce() => service.migrateIfNeeded(
          alreadyMigrated: false,
          readLegacyEntries: () async => {'profile': '{"a":1}'},
          target: store,
          markMigrated: () async {},
        );

        await runOnce();
        await runOnce();

        expect(await store.getAll(), {'profile': '{"a":1}'});
      },
    );
  });
}
