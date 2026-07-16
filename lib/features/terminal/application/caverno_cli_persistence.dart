import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../chat/application/persistence/caverno_persistence_bootstrap.dart';
import '../../chat/data/datasources/app_database.dart';
import '../../chat/data/repositories/conversation_repository.dart';

const cavernoCliMigrationBoxName = 'persistence_migrations';

Future<CavernoPersistenceStorage> openCavernoCliPersistence({
  required Directory? dataDirectory,
  required SharedPreferences preferences,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required Box<bool>? migrationBox,
  CavernoPersistenceBootstrap bootstrap = const CavernoPersistenceBootstrap(),
  CavernoAppDatabaseOpener? openDatabase,
}) {
  final resolvedDataDirectory = dataDirectory?.absolute;
  final scopedToDataDirectory = resolvedDataDirectory != null;
  if (scopedToDataDirectory && migrationBox == null) {
    throw ArgumentError.notNull('migrationBox');
  }

  bool migrationCompleted(String key) {
    if (scopedToDataDirectory) {
      return migrationBox!.get(key) ?? false;
    }
    return preferences.getBool(key) ?? false;
  }

  Future<void> markMigrationCompleted(String key) async {
    if (scopedToDataDirectory) {
      await migrationBox!.put(key, true);
      return;
    }
    await preferences.setBool(key, true);
  }

  final databaseOpener =
      openDatabase ??
      (scopedToDataDirectory
          ? () => openAppDatabase(
              databaseFile: File(
                '${resolvedDataDirectory.path}/caverno.sqlite',
              ),
            )
          : openAppDatabase);

  return bootstrap.open(
    openDatabase: databaseOpener,
    conversationsMigrated: migrationCompleted(cavernoConversationsMigrationKey),
    chatMemoryMigrated: migrationCompleted(cavernoChatMemoryMigrationKey),
    readLegacyConversations: () async =>
        ConversationRepository(conversationBox).getAll(),
    readLegacyChatMemory: () async => {
      for (final key in memoryBox.keys) key.toString(): ?memoryBox.get(key),
    },
    markConversationsMigrated: () =>
        markMigrationCompleted(cavernoConversationsMigrationKey),
    markChatMemoryMigrated: () =>
        markMigrationCompleted(cavernoChatMemoryMigrationKey),
  );
}
