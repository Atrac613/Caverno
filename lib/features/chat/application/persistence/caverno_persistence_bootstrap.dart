import '../../data/datasources/app_database.dart';
import '../../data/repositories/cached_drift_conversation_repository.dart';
import '../../data/repositories/chat_memory_migration_service.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/conversation_migration_service.dart';
import '../../data/repositories/drift_chat_memory_store.dart';
import '../../data/repositories/drift_conversation_repository.dart';
import '../../data/repositories/key_value_store.dart';
import '../../domain/entities/conversation.dart';

typedef CavernoAppDatabaseOpener = Future<AppDatabase> Function();
typedef CavernoAppDatabaseCloser = Future<void> Function(AppDatabase database);
typedef LegacyConversationReader = Future<List<Conversation>> Function();
typedef LegacyChatMemoryReader = Future<Map<String, String>> Function();
typedef MigrationMarkerWriter = Future<void> Function();

/// Drift-backed repositories and database owned by one application frontend.
final class CavernoPersistenceStorage {
  CavernoPersistenceStorage({
    required this.database,
    required this.conversationRepository,
    required this.chatMemoryRepository,
    CavernoAppDatabaseCloser closeDatabase = _closeAppDatabase,
  }) : _closeDatabase = closeDatabase;

  final AppDatabase database;
  final CachedDriftConversationRepository conversationRepository;
  final ChatMemoryRepository chatMemoryRepository;
  final CavernoAppDatabaseCloser _closeDatabase;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _closeDatabase(database);
  }
}

/// Opens drift, applies the one-time F4 migrations, and hydrates repositories.
///
/// Frontends own fallback policy. GUI startup may catch a failure and retain
/// its legacy Hive repositories, while the CLI can fail closed instead of
/// writing to a stale post-migration Hive store.
final class CavernoPersistenceBootstrap {
  const CavernoPersistenceBootstrap();

  Future<CavernoPersistenceStorage> open({
    required CavernoAppDatabaseOpener openDatabase,
    required bool conversationsMigrated,
    required bool chatMemoryMigrated,
    required LegacyConversationReader readLegacyConversations,
    required LegacyChatMemoryReader readLegacyChatMemory,
    required MigrationMarkerWriter markConversationsMigrated,
    required MigrationMarkerWriter markChatMemoryMigrated,
    CavernoAppDatabaseCloser closeDatabase = _closeAppDatabase,
  }) async {
    final database = await openDatabase();
    try {
      final conversationStore = DriftConversationRepository(database);
      await const ConversationMigrationService().migrateIfNeeded(
        alreadyMigrated: conversationsMigrated,
        readLegacyConversations: readLegacyConversations,
        target: conversationStore,
        markMigrated: markConversationsMigrated,
      );

      final chatMemoryStore = DriftChatMemoryStore(database);
      await const ChatMemoryMigrationService().migrateIfNeeded(
        alreadyMigrated: chatMemoryMigrated,
        readLegacyEntries: readLegacyChatMemory,
        target: chatMemoryStore,
        markMigrated: markChatMemoryMigrated,
      );

      final conversationRepository =
          await CachedDriftConversationRepository.hydrate(conversationStore);
      final chatMemoryKeyValueStore = await CachedDriftKeyValueStore.hydrate(
        chatMemoryStore,
      );
      return CavernoPersistenceStorage(
        database: database,
        conversationRepository: conversationRepository,
        chatMemoryRepository: ChatMemoryRepository(chatMemoryKeyValueStore),
        closeDatabase: closeDatabase,
      );
    } catch (_) {
      await closeDatabase(database);
      rethrow;
    }
  }
}

Future<void> _closeAppDatabase(AppDatabase database) => database.close();
