import 'drift_chat_memory_store.dart';

/// Outcome of the one-time chat-memory migration.
class ChatMemoryMigrationResult {
  const ChatMemoryMigrationResult({
    required this.migratedCount,
    required this.skippedAlreadyMigrated,
  });

  const ChatMemoryMigrationResult.alreadyMigrated()
    : migratedCount = 0,
      skippedAlreadyMigrated = true;

  final int migratedCount;
  final bool skippedAlreadyMigrated;
}

/// F4: one-time import of the chat-memory key/value blobs from the legacy Hive
/// store into the drift [DriftChatMemoryStore].
///
/// Like the conversation migration, idempotency is enforced by a persistent
/// marker supplied by the caller: once migration runs, Hive is never re-read
/// and newer drift values are never clobbered on later launches. The marker is
/// set only after a successful import, and the target's upsert-by-key keeps a
/// retried import from duplicating values.
class ChatMemoryMigrationService {
  const ChatMemoryMigrationService();

  Future<ChatMemoryMigrationResult> migrateIfNeeded({
    required bool alreadyMigrated,
    required Future<Map<String, String>> Function() readLegacyEntries,
    required DriftChatMemoryStore target,
    required Future<void> Function() markMigrated,
  }) async {
    if (alreadyMigrated) {
      return const ChatMemoryMigrationResult.alreadyMigrated();
    }

    final entries = await readLegacyEntries();
    var migratedCount = 0;
    for (final entry in entries.entries) {
      await target.setValue(entry.key, entry.value);
      migratedCount += 1;
    }

    await markMigrated();
    return ChatMemoryMigrationResult(
      migratedCount: migratedCount,
      skippedAlreadyMigrated: false,
    );
  }
}
