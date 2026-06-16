import '../../domain/entities/conversation.dart';
import 'conversation_store.dart';

/// Outcome of a one-time conversation migration.
class ConversationMigrationResult {
  const ConversationMigrationResult({
    required this.migratedCount,
    required this.skippedAlreadyMigrated,
  });

  const ConversationMigrationResult.alreadyMigrated()
    : migratedCount = 0,
      skippedAlreadyMigrated = true;

  final int migratedCount;
  final bool skippedAlreadyMigrated;
}

/// F4: one-time import of conversations from the legacy Hive store into the
/// drift [ConversationStore].
///
/// Idempotency is enforced by a persistent marker supplied by the caller
/// (SharedPreferences in production): once migration has run, Hive is never
/// read again and newer drift data is never clobbered by a stale Hive copy on
/// later launches. Within a single run the target's upsert-by-id keeps a
/// retried import from duplicating rows.
class ConversationMigrationService {
  const ConversationMigrationService();

  Future<ConversationMigrationResult> migrateIfNeeded({
    required bool alreadyMigrated,
    required Future<List<Conversation>> Function() readLegacyConversations,
    required ConversationStore target,
    required Future<void> Function() markMigrated,
  }) async {
    if (alreadyMigrated) {
      return const ConversationMigrationResult.alreadyMigrated();
    }

    final conversations = await readLegacyConversations();
    var migratedCount = 0;
    for (final conversation in conversations) {
      await target.save(conversation);
      migratedCount += 1;
    }

    // Mark only after a successful import so an interrupted migration retries
    // next launch instead of silently dropping conversations.
    await markMigrated();
    return ConversationMigrationResult(
      migratedCount: migratedCount,
      skippedAlreadyMigrated: false,
    );
  }
}
