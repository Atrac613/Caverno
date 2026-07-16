import 'dart:io';

import 'package:caverno/features/chat/application/persistence/caverno_persistence_bootstrap.dart';
import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
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
