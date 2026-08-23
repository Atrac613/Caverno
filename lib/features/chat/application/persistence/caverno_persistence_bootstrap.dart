import '../../data/datasources/app_database.dart';
import '../../data/repositories/cached_drift_conversation_repository.dart';
import '../../data/repositories/chat_memory_migration_service.dart';
import '../../data/repositories/chat_memory_mutation_coordinator.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/conversation_migration_service.dart';
import '../../data/repositories/drift_chat_memory_store.dart';
import '../../data/repositories/drift_conversation_repository.dart';
import '../../data/repositories/key_value_store.dart';
import '../../domain/entities/conversation.dart';

const cavernoConversationsMigrationKey = 'f4_conversations_migrated_v1';
const cavernoChatMemoryMigrationKey = 'f4_chat_memory_migrated_v1';

typedef CavernoAppDatabaseOpener = Future<AppDatabase> Function();
typedef CavernoAppDatabaseCloser = Future<void> Function(AppDatabase database);
typedef LegacyConversationReader = Future<List<Conversation>> Function();
typedef LegacyChatMemoryReader = Future<Map<String, String>> Function();
typedef MigrationMarkerWriter = Future<void> Function();

/// Signals that at least one drift migration marker is authoritative, so a
/// caller must not fall back to mutable legacy Hive repositories.
final class CavernoAuthoritativePersistenceException extends StateError
    implements Exception {
  CavernoAuthoritativePersistenceException(this.cause, this.causeStackTrace)
    : super(cause.toString());

  final Object cause;
  final StackTrace causeStackTrace;

  @override
  String toString() {
    return 'Authoritative drift persistence failed: $cause';
  }
}

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
/// Frontends own fallback policy before migration. Once either migration has
/// completed, failures are wrapped in
/// [CavernoAuthoritativePersistenceException] so no frontend can silently
/// resume writes against stale legacy Hive data.
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
    ChatMemoryMutationCoordinator mutationCoordinator =
        const DirectChatMemoryMutationCoordinator(),
  }) async {
    AppDatabase? database;
    var driftIsAuthoritative = conversationsMigrated || chatMemoryMigrated;
    try {
      database = await openDatabase();
      final conversationStore = DriftConversationRepository(database);
      final conversationMigration = await const ConversationMigrationService()
          .migrateIfNeeded(
            alreadyMigrated: conversationsMigrated,
            readLegacyConversations: readLegacyConversations,
            target: conversationStore,
            markMigrated: markConversationsMigrated,
          );
      if (!conversationMigration.skippedAlreadyMigrated) {
        driftIsAuthoritative = true;
      }

      final chatMemoryStore = DriftChatMemoryStore(database);
      final chatMemoryMigration = await const ChatMemoryMigrationService()
          .migrateIfNeeded(
            alreadyMigrated: chatMemoryMigrated,
            readLegacyEntries: readLegacyChatMemory,
            target: chatMemoryStore,
            markMigrated: markChatMemoryMigrated,
          );
      if (!chatMemoryMigration.skippedAlreadyMigrated) {
        driftIsAuthoritative = true;
      }

      final conversationRepository =
          await CachedDriftConversationRepository.hydrate(conversationStore);
      final chatMemoryKeyValueStore = await CachedDriftKeyValueStore.hydrate(
        chatMemoryStore,
      );
      return CavernoPersistenceStorage(
        database: database,
        conversationRepository: conversationRepository,
        chatMemoryRepository: ChatMemoryRepository(
          chatMemoryKeyValueStore,
          mutationCoordinator: mutationCoordinator,
        ),
        closeDatabase: closeDatabase,
      );
    } catch (error, stackTrace) {
      if (database != null) {
        await closeDatabase(database);
      }
      if (driftIsAuthoritative) {
        throw CavernoAuthoritativePersistenceException(error, stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

Future<void> _closeAppDatabase(AppDatabase database) => database.close();
