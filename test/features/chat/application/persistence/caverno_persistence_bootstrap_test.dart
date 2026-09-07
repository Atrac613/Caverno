import 'dart:async';

import 'package:caverno/features/chat/application/persistence/caverno_persistence_bootstrap.dart';
import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/conversation_listing_codec.dart';
import 'package:caverno/features/chat/data/repositories/drift_chat_memory_store.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
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

  test('GUI hydrate lists conversations without message bodies', () async {
    final database = AppDatabase.memory();
    final conversation = _conversation(
      'conversation-3',
      messages: [
        Message(
          id: 'm1',
          content: 'unique-bootstrap-payload-token',
          role: MessageRole.user,
          timestamp: DateTime.utc(2026, 7, 16),
        ),
      ],
    );
    await DriftConversationRepository(database).save(conversation);

    final storage = await bootstrap.open(
      openDatabase: () async => database,
      conversationsMigrated: true,
      chatMemoryMigrated: true,
      readLegacyConversations: () => throw StateError('unexpected read'),
      readLegacyChatMemory: () => throw StateError('unexpected read'),
      markConversationsMigrated: () => throw StateError('unexpected marker'),
      markChatMemoryMigrated: () => throw StateError('unexpected marker'),
    );

    final listed = storage.conversationRepository.getById(conversation.id);
    expect(listed, isNotNull);
    expect(listed!.messages.single.id, ConversationListingCodec.stubMessageId);
    expect(listed.messages.single.content, isEmpty);

    final refreshed = await storage.conversationRepository.refresh(
      conversation.id,
    );
    expect(
      refreshed!.messages.single.content,
      'unique-bootstrap-payload-token',
    );

    await storage.close();
  });

  test('CLI hydrate keeps message bodies', () async {
    final database = AppDatabase.memory();
    final conversation = _conversation(
      'conversation-4',
      messages: [
        Message(
          id: 'm1',
          content: 'unique-cli-payload-token',
          role: MessageRole.user,
          timestamp: DateTime.utc(2026, 7, 16),
        ),
      ],
    );
    await DriftConversationRepository(database).save(conversation);

    final storage = await bootstrap.open(
      openDatabase: () async => database,
      conversationsMigrated: true,
      chatMemoryMigrated: true,
      readLegacyConversations: () => throw StateError('unexpected read'),
      readLegacyChatMemory: () => throw StateError('unexpected read'),
      markConversationsMigrated: () => throw StateError('unexpected marker'),
      markChatMemoryMigrated: () => throw StateError('unexpected marker'),
      hydrateConversationListingOnly: false,
    );

    expect(
      storage.conversationRepository
          .getById(conversation.id)!
          .messages
          .single
          .content,
      'unique-cli-payload-token',
    );

    await storage.close();
  });

  test('a failed database close stays retryable', () async {
    final database = AppDatabase.memory();
    var closeCount = 0;
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
        if (closeCount == 1) {
          throw StateError('close failed');
        }
        await database.close();
      },
    );

    await expectLater(storage.close(), throwsA(isA<StateError>()));
    await storage.close();
    expect(closeCount, 2);
  });

  test('concurrent close calls share one in-flight database close', () async {
    final database = AppDatabase.memory();
    final allowClose = Completer<void>();
    var closeCount = 0;
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
        await allowClose.future;
        await database.close();
      },
    );

    final first = storage.close();
    final second = storage.close();
    allowClose.complete();
    await first;
    await second;
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
        throwsA(
          isA<CavernoAuthoritativePersistenceException>().having(
            (error) => error.cause,
            'cause',
            isA<StateError>(),
          ),
        ),
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

    await expectLater(
      open(),
      throwsA(isA<CavernoAuthoritativePersistenceException>()),
    );
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

  test('pre-migration failure remains eligible for legacy fallback', () async {
    final database = AppDatabase.memory();

    await expectLater(
      bootstrap.open(
        openDatabase: () async => database,
        conversationsMigrated: false,
        chatMemoryMigrated: false,
        readLegacyConversations: () => throw StateError('legacy read failed'),
        readLegacyChatMemory: () async => const <String, String>{},
        markConversationsMigrated: () async {},
        markChatMemoryMigrated: () async {},
      ),
      throwsA(
        allOf(
          isA<StateError>(),
          isNot(isA<CavernoAuthoritativePersistenceException>()),
        ),
      ),
    );
  });

  test(
    'failure after the first completed migration is authoritative',
    () async {
      final database = AppDatabase.memory();
      var conversationMarked = false;

      await expectLater(
        bootstrap.open(
          openDatabase: () async => database,
          conversationsMigrated: false,
          chatMemoryMigrated: false,
          readLegacyConversations: () async => [_conversation('partial')],
          readLegacyChatMemory: () => throw StateError('memory read failed'),
          markConversationsMigrated: () async {
            conversationMarked = true;
          },
          markChatMemoryMigrated: () async {},
        ),
        throwsA(isA<CavernoAuthoritativePersistenceException>()),
      );

      expect(conversationMarked, isTrue);
    },
  );

  test('database-open failure is authoritative after migration', () async {
    await expectLater(
      bootstrap.open(
        openDatabase: () => throw StateError('database unavailable'),
        conversationsMigrated: true,
        chatMemoryMigrated: true,
        readLegacyConversations: () => throw StateError('unexpected read'),
        readLegacyChatMemory: () => throw StateError('unexpected read'),
        markConversationsMigrated: () => throw StateError('unexpected marker'),
        markChatMemoryMigrated: () => throw StateError('unexpected marker'),
      ),
      throwsA(
        isA<CavernoAuthoritativePersistenceException>().having(
          (error) => error.cause,
          'cause',
          isA<StateError>(),
        ),
      ),
    );
  });
}

Conversation _conversation(String id, {List<Message> messages = const []}) {
  final timestamp = DateTime.utc(2026, 7, 16);
  return Conversation(
    id: id,
    title: 'Conversation $id',
    messages: messages,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
