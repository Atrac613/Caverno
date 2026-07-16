import 'package:caverno/features/chat/application/persistence/caverno_persistence_bootstrap.dart';
import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/drift_chat_memory_store.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bootstrap = CavernoPersistenceBootstrap();

  test('migrates legacy data and hydrates drift repositories', () async {
    final database = AppDatabase.memory();
    final conversation = _conversation('conversation-1');
    var conversationMarked = false;
    var memoryMarked = false;

    final storage = await bootstrap.open(
      openDatabase: () async => database,
      conversationsMigrated: false,
      chatMemoryMigrated: false,
      readLegacyConversations: () async => [conversation],
      readLegacyChatMemory: () async => {'profile': '{"name":"Ada"}'},
      markConversationsMigrated: () async {
        conversationMarked = true;
      },
      markChatMemoryMigrated: () async {
        memoryMarked = true;
      },
    );

    expect(
      storage.conversationRepository.getById(conversation.id),
      conversation,
    );
    expect(
      await DriftChatMemoryStore(database).getValue('profile'),
      '{"name":"Ada"}',
    );
    expect(conversationMarked, isTrue);
    expect(memoryMarked, isTrue);

    await storage.close();
  });

  test('completed migrations never invoke legacy readers', () async {
    final database = AppDatabase.memory();
    final conversation = _conversation('conversation-2');
    var closeCount = 0;
    await DriftConversationRepository(database).save(conversation);

    final storage = await bootstrap.open(
      openDatabase: () async => database,
      conversationsMigrated: true,
      chatMemoryMigrated: true,
      readLegacyConversations: () => throw StateError('unexpected read'),
      readLegacyChatMemory: () => throw StateError('unexpected read'),
      markConversationsMigrated: () => throw StateError('unexpected marker'),
      markChatMemoryMigrated: () => throw StateError('unexpected marker'),
      closeDatabase: (database) async {
        closeCount += 1;
        await database.close();
      },
    );

    expect(
      storage.conversationRepository.getById(conversation.id),
      conversation,
    );

    await storage.close();
    await storage.close();
    expect(closeCount, 1);
  });

  test(
    'failed migration leaves its marker unset and closes the database',
    () async {
      final database = AppDatabase.memory();
      var conversationMarked = false;
      var databaseClosed = false;

      await expectLater(
        bootstrap.open(
          openDatabase: () async => database,
          conversationsMigrated: false,
          chatMemoryMigrated: true,
          readLegacyConversations: () => throw StateError('legacy read failed'),
          readLegacyChatMemory: () async => const {},
          markConversationsMigrated: () async {
            conversationMarked = true;
          },
          markChatMemoryMigrated: () async {},
          closeDatabase: (database) async {
            databaseClosed = true;
            await database.close();
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(conversationMarked, isFalse);
      expect(databaseClosed, isTrue);
    },
  );

  test('a failed migration can be retried by the next bootstrap', () async {
    final conversation = _conversation('conversation-retry');
    var attempts = 0;
    var migrationCompleted = false;
    var closeCount = 0;

    Future<CavernoPersistenceStorage> open() {
      final database = AppDatabase.memory();
      return bootstrap.open(
        openDatabase: () async => database,
        conversationsMigrated: migrationCompleted,
        chatMemoryMigrated: true,
        readLegacyConversations: () async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('temporary legacy read failure');
          }
          return <Conversation>[conversation];
        },
        readLegacyChatMemory: () async => const <String, String>{},
        markConversationsMigrated: () async {
          migrationCompleted = true;
        },
        markChatMemoryMigrated: () async {},
        closeDatabase: (database) async {
          closeCount += 1;
          await database.close();
        },
      );
    }

    await expectLater(open(), throwsA(isA<StateError>()));
    expect(migrationCompleted, isFalse);
    expect(closeCount, 1);

    final recovered = await open();
    expect(
      recovered.conversationRepository.getById(conversation.id),
      conversation,
    );
    expect(migrationCompleted, isTrue);
    await recovered.close();
    expect(closeCount, 2);
  });
}

Conversation _conversation(String id) {
  final timestamp = DateTime.utc(2026, 7, 16);
  return Conversation(
    id: id,
    title: 'Conversation $id',
    messages: const [],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
