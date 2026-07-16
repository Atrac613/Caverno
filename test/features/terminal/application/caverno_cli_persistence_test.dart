import 'dart:io';

import 'package:caverno/features/chat/application/persistence/caverno_chat_memory_mutation_coordinator.dart';
import 'package:caverno/features/chat/application/persistence/caverno_persistence_bootstrap.dart';
import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/terminal/application/caverno_cli_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dataDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dataDirectory = await Directory.systemTemp.createTemp(
      'caverno_cli_persistence_',
    );
    Hive.init(dataDirectory.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await dataDirectory.exists()) {
      await dataDirectory.delete(recursive: true);
    }
  });

  test(
    'explicit data directory migrates Hive into its own SQLite file',
    () async {
      final conversationBox = await Hive.openBox<String>('conversations');
      final memoryBox = await Hive.openBox<String>('chat_memory');
      final migrationBox = await Hive.openBox<bool>(cavernoCliMigrationBoxName);
      final preferences = await SharedPreferences.getInstance();
      final conversation = _conversation('conversation-1', 'Legacy title');
      await ConversationRepository(conversationBox).save(conversation);
      await memoryBox.put('profile', '{"name":"Ada"}');

      final storage = await openCavernoCliPersistence(
        dataDirectory: dataDirectory,
        preferences: preferences,
        conversationBox: conversationBox,
        memoryBox: memoryBox,
        migrationBox: migrationBox,
      );

      expect(File('${dataDirectory.path}/caverno.sqlite').existsSync(), isTrue);
      expect(
        storage.conversationRepository.getById(conversation.id),
        conversation,
      );
      expect(migrationBox.get(cavernoConversationsMigrationKey), isTrue);
      expect(migrationBox.get(cavernoChatMemoryMigrationKey), isTrue);

      await storage.close();
    },
  );

  test(
    'data-directory markers prevent stale Hive from replacing drift',
    () async {
      final conversationBox = await Hive.openBox<String>('conversations');
      final memoryBox = await Hive.openBox<String>('chat_memory');
      final migrationBox = await Hive.openBox<bool>(cavernoCliMigrationBoxName);
      final preferences = await SharedPreferences.getInstance();
      final legacy = _conversation('conversation-2', 'Legacy title');
      await ConversationRepository(conversationBox).save(legacy);

      final firstStorage = await openCavernoCliPersistence(
        dataDirectory: dataDirectory,
        preferences: preferences,
        conversationBox: conversationBox,
        memoryBox: memoryBox,
        migrationBox: migrationBox,
      );
      await firstStorage.conversationRepository.save(
        legacy.copyWith(title: 'Drift title'),
      );
      await firstStorage.close();

      final secondStorage = await openCavernoCliPersistence(
        dataDirectory: dataDirectory,
        preferences: preferences,
        conversationBox: conversationBox,
        memoryBox: memoryBox,
        migrationBox: migrationBox,
      );

      expect(
        secondStorage.conversationRepository.getById(legacy.id)?.title,
        'Drift title',
      );

      await secondStorage.close();
    },
  );

  test(
    'application-default storage uses the existing global markers',
    () async {
      final conversationBox = await Hive.openBox<String>('conversations');
      final memoryBox = await Hive.openBox<String>('chat_memory');
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(cavernoConversationsMigrationKey, true);
      await preferences.setBool(cavernoChatMemoryMigrationKey, true);
      final database = AppDatabase.memory();
      final driftConversation = _conversation('conversation-3', 'Drift title');
      await DriftConversationRepository(database).save(driftConversation);
      await ConversationRepository(
        conversationBox,
      ).save(driftConversation.copyWith(title: 'Stale Hive title'));

      final storage = await openCavernoCliPersistence(
        dataDirectory: null,
        preferences: preferences,
        conversationBox: conversationBox,
        memoryBox: memoryBox,
        migrationBox: null,
        openDatabase: () async => database,
      );

      expect(
        storage.conversationRepository.getById(driftConversation.id)?.title,
        'Drift title',
      );

      await storage.close();
    },
  );

  test('completed migrations do not require legacy Hive boxes', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(cavernoConversationsMigrationKey, true);
    await preferences.setBool(cavernoChatMemoryMigrationKey, true);
    final database = AppDatabase.memory();
    final conversation = _conversation('conversation-4', 'Drift only');
    await DriftConversationRepository(database).save(conversation);

    final storage = await openCavernoCliPersistence(
      dataDirectory: null,
      preferences: preferences,
      conversationBox: null,
      memoryBox: null,
      migrationBox: null,
      openDatabase: () async => database,
    );

    expect(
      storage.conversationRepository.getById(conversation.id),
      conversation,
    );

    await storage.close();
  });

  test('application-default processes share persisted chat memory', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(cavernoConversationsMigrationKey, true);
    await preferences.setBool(cavernoChatMemoryMigrationKey, true);
    final databaseFile = File('${dataDirectory.path}/default-caverno.sqlite');
    final profile = UserMemoryProfile(
      persona: const <String>['Default frontend user'],
      preferences: const <String>['Share memory across frontends'],
      doNot: const <String>[],
      updatedAt: DateTime.utc(2026, 7, 16, 5),
    );

    final firstStorage = await openCavernoCliPersistence(
      dataDirectory: null,
      preferences: preferences,
      conversationBox: null,
      memoryBox: null,
      migrationBox: null,
      openDatabase: () => openAppDatabase(databaseFile: databaseFile),
    );
    await firstStorage.chatMemoryRepository.saveProfile(profile);
    await firstStorage.close();

    final secondStorage = await openCavernoCliPersistence(
      dataDirectory: null,
      preferences: preferences,
      conversationBox: null,
      memoryBox: null,
      migrationBox: null,
      openDatabase: () => openAppDatabase(databaseFile: databaseFile),
    );

    final restored = secondStorage.chatMemoryRepository.loadProfile();
    expect(restored.persona, profile.persona);
    expect(restored.preferences, profile.preferences);
    expect(restored.doNot, profile.doNot);
    expect(restored.updatedAt, profile.updatedAt);
    await secondStorage.close();
  });

  test(
    'independently hydrated frontends merge memories and summaries',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(cavernoConversationsMigrationKey, true);
      await preferences.setBool(cavernoChatMemoryMigrationKey, true);
      final databaseFile = File('${dataDirectory.path}/shared-caverno.sqlite');
      final firstStorage = await openCavernoCliPersistence(
        dataDirectory: null,
        preferences: preferences,
        conversationBox: null,
        memoryBox: null,
        migrationBox: null,
        openDatabase: () => openAppDatabase(databaseFile: databaseFile),
        mutationCoordinator: CavernoChatMemoryMutationCoordinator(
          dataRoot: dataDirectory,
          frontend: 'gui',
        ),
      );
      final secondStorage = await openCavernoCliPersistence(
        dataDirectory: null,
        preferences: preferences,
        conversationBox: null,
        memoryBox: null,
        migrationBox: null,
        openDatabase: () => openAppDatabase(databaseFile: databaseFile),
        mutationCoordinator: CavernoChatMemoryMutationCoordinator(
          dataRoot: dataDirectory,
          frontend: 'terminal',
        ),
      );

      await firstStorage.chatMemoryRepository.addOrUpdateMemories(<MemoryEntry>[
        _memory('memory-gui', 'GUI memory', 'conversation-gui'),
      ]);
      await firstStorage.chatMemoryRepository.upsertSessionSummary(
        _summary('conversation-gui', 'GUI summary'),
      );
      await secondStorage.chatMemoryRepository.addOrUpdateMemories(
        <MemoryEntry>[
          _memory(
            'memory-terminal',
            'Terminal memory',
            'conversation-terminal',
          ),
        ],
      );
      await secondStorage.chatMemoryRepository.upsertSessionSummary(
        _summary('conversation-terminal', 'Terminal summary'),
      );

      await firstStorage.close();
      await secondStorage.close();
      final reopened = await openCavernoCliPersistence(
        dataDirectory: null,
        preferences: preferences,
        conversationBox: null,
        memoryBox: null,
        migrationBox: null,
        openDatabase: () => openAppDatabase(databaseFile: databaseFile),
      );

      expect(
        reopened.chatMemoryRepository.loadMemories().map((item) => item.id),
        containsAll(<String>['memory-gui', 'memory-terminal']),
      );
      expect(
        reopened.chatMemoryRepository.loadSessionSummaries().map(
          (item) => item.conversationId,
        ),
        containsAll(<String>['conversation-gui', 'conversation-terminal']),
      );
      await reopened.close();
    },
  );

  test('explicit data roots isolate persisted chat memory', () async {
    final migrationBox = await Hive.openBox<bool>(cavernoCliMigrationBoxName);
    await migrationBox.put(cavernoConversationsMigrationKey, true);
    await migrationBox.put(cavernoChatMemoryMigrationKey, true);
    final preferences = await SharedPreferences.getInstance();
    final otherDataDirectory = await Directory.systemTemp.createTemp(
      'caverno_cli_memory_isolation_',
    );
    addTearDown(() => otherDataDirectory.delete(recursive: true));
    final profile = UserMemoryProfile(
      persona: const <String>['First isolated root'],
      preferences: const <String>[],
      doNot: const <String>['Leak into another root'],
      updatedAt: DateTime.utc(2026, 7, 16, 5, 1),
    );

    final firstStorage = await openCavernoCliPersistence(
      dataDirectory: dataDirectory,
      preferences: preferences,
      conversationBox: null,
      memoryBox: null,
      migrationBox: migrationBox,
    );
    await firstStorage.chatMemoryRepository.saveProfile(profile);
    await firstStorage.close();

    final otherStorage = await openCavernoCliPersistence(
      dataDirectory: otherDataDirectory,
      preferences: preferences,
      conversationBox: null,
      memoryBox: null,
      migrationBox: migrationBox,
    );
    expect(otherStorage.chatMemoryRepository.loadProfile().isEmpty, isTrue);
    await otherStorage.close();

    final reopenedFirstStorage = await openCavernoCliPersistence(
      dataDirectory: dataDirectory,
      preferences: preferences,
      conversationBox: null,
      memoryBox: null,
      migrationBox: migrationBox,
    );
    final restored = reopenedFirstStorage.chatMemoryRepository.loadProfile();
    expect(restored.persona, profile.persona);
    expect(restored.doNot, profile.doNot);
    await reopenedFirstStorage.close();
  });

  test('incomplete conversation migration requires its legacy box', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(cavernoChatMemoryMigrationKey, true);

    await expectLater(
      openCavernoCliPersistence(
        dataDirectory: null,
        preferences: preferences,
        conversationBox: null,
        memoryBox: null,
        migrationBox: null,
        openDatabase: () async => AppDatabase.memory(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Legacy conversations'),
        ),
      ),
    );
  });

  test('incomplete chat-memory migration requires its legacy box', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(cavernoConversationsMigrationKey, true);

    await expectLater(
      openCavernoCliPersistence(
        dataDirectory: null,
        preferences: preferences,
        conversationBox: null,
        memoryBox: null,
        migrationBox: null,
        openDatabase: () async => AppDatabase.memory(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Legacy chat memory'),
        ),
      ),
    );
  });
}

Conversation _conversation(String id, String title) {
  final timestamp = DateTime.utc(2026, 7, 16);
  return Conversation(
    id: id,
    title: title,
    messages: const [],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

MemoryEntry _memory(String id, String text, String conversationId) {
  return MemoryEntry(
    id: id,
    text: text,
    type: MemoryEntryType.fact,
    confidence: 0.9,
    importance: 0.9,
    updatedAt: DateTime.utc(2026, 7, 16, 6),
    sourceConversationId: conversationId,
  );
}

MemorySessionSummary _summary(String conversationId, String summary) {
  return MemorySessionSummary(
    conversationId: conversationId,
    summary: summary,
    openLoops: const <String>[],
    updatedAt: DateTime.utc(2026, 7, 16, 6),
  );
}
