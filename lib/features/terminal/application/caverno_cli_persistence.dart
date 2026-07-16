import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../chat/application/persistence/caverno_persistence_bootstrap.dart';
import '../../chat/data/datasources/app_database.dart';
import '../../chat/data/repositories/chat_memory_mutation_coordinator.dart';
import '../../chat/data/repositories/conversation_repository.dart';

const cavernoCliMigrationBoxName = 'persistence_migrations';

final class CavernoCliMigrationStatus {
  const CavernoCliMigrationStatus({
    required this.conversationsMigrated,
    required this.chatMemoryMigrated,
  });

  final bool conversationsMigrated;
  final bool chatMemoryMigrated;
}

CavernoCliMigrationStatus resolveCavernoCliMigrationStatus({
  required Directory? dataDirectory,
  required SharedPreferences preferences,
  required Box<bool>? migrationBox,
}) {
  final scopedToDataDirectory = dataDirectory != null;
  if (scopedToDataDirectory && migrationBox == null) {
    throw ArgumentError.notNull('migrationBox');
  }

  bool migrationCompleted(String key) {
    if (scopedToDataDirectory) {
      return migrationBox!.get(key) ?? false;
    }
    return preferences.getBool(key) ?? false;
  }

  return CavernoCliMigrationStatus(
    conversationsMigrated: migrationCompleted(cavernoConversationsMigrationKey),
    chatMemoryMigrated: migrationCompleted(cavernoChatMemoryMigrationKey),
  );
}

Future<CavernoPersistenceStorage> openCavernoCliPersistence({
  required Directory? dataDirectory,
  required SharedPreferences preferences,
  required Box<String>? conversationBox,
  required Box<String>? memoryBox,
  required Box<bool>? migrationBox,
  CavernoPersistenceBootstrap bootstrap = const CavernoPersistenceBootstrap(),
  CavernoAppDatabaseOpener? openDatabase,
  ChatMemoryMutationCoordinator mutationCoordinator =
      const DirectChatMemoryMutationCoordinator(),
}) {
  final resolvedDataDirectory = dataDirectory?.absolute;
  final scopedToDataDirectory = resolvedDataDirectory != null;
  if (scopedToDataDirectory && migrationBox == null) {
    throw ArgumentError.notNull('migrationBox');
  }
  final migrationStatus = resolveCavernoCliMigrationStatus(
    dataDirectory: resolvedDataDirectory,
    preferences: preferences,
    migrationBox: migrationBox,
  );

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
    conversationsMigrated: migrationStatus.conversationsMigrated,
    chatMemoryMigrated: migrationStatus.chatMemoryMigrated,
    readLegacyConversations: () async {
      final box = conversationBox;
      if (box == null) {
        throw StateError(
          'Legacy conversations are required for an incomplete migration.',
        );
      }
      return ConversationRepository(box).getAll();
    },
    readLegacyChatMemory: () async {
      final box = memoryBox;
      if (box == null) {
        throw StateError(
          'Legacy chat memory is required for an incomplete migration.',
        );
      }
      return {for (final key in box.keys) key.toString(): ?box.get(key)};
    },
    markConversationsMigrated: () =>
        markMigrationCompleted(cavernoConversationsMigrationKey),
    markChatMemoryMigrated: () =>
        markMigrationCompleted(cavernoChatMemoryMigrationKey),
    mutationCoordinator: mutationCoordinator,
  );
}
