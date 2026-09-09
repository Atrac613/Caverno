import 'package:hive_flutter/hive_flutter.dart';

typedef CavernoHiveBoxOpener = Future<Box<String>> Function(String name);

Future<Box<String>> openStringHiveBox(String name) =>
    Hive.openBox<String>(name);

/// Legacy Hive boxes the GUI still needs during F4 fallback / first migration.
///
/// After both conversation and chat-memory migration markers exist, opening
/// the 10+ MB `conversations.hive` sitting in ~/Documents only stalls launch.
/// Skills remain Hive-backed, so that box still opens every time.
final class CavernoLegacyHiveBoxes {
  const CavernoLegacyHiveBoxes({
    required this.skills,
    this.conversations,
    this.memory,
  });

  final Box<String> skills;
  final Box<String>? conversations;
  final Box<String>? memory;

  static Future<CavernoLegacyHiveBoxes> open({
    required bool conversationsMigrated,
    required bool chatMemoryMigrated,
    CavernoHiveBoxOpener openBox = openStringHiveBox,
  }) async {
    return CavernoLegacyHiveBoxes(
      skills: await openBox('skills'),
      conversations: conversationsMigrated
          ? null
          : await openBox('conversations'),
      memory: chatMemoryMigrated ? null : await openBox('chat_memory'),
    );
  }
}
