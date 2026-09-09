import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/features/chat/application/persistence/caverno_legacy_hive_boxes.dart';

class _MockBox extends Mock implements Box<String> {}

void main() {
  test('opens only the skills box after both F4 migrations', () async {
    final opened = <String>[];
    final boxes = await CavernoLegacyHiveBoxes.open(
      conversationsMigrated: true,
      chatMemoryMigrated: true,
      openBox: (name) async {
        opened.add(name);
        return _MockBox();
      },
    );

    expect(opened, ['skills']);
    expect(boxes.conversations, isNull);
    expect(boxes.memory, isNull);
    expect(boxes.skills, isA<Box<String>>());
  });

  test('opens legacy conversation and memory boxes before migration', () async {
    final opened = <String>[];
    final boxes = await CavernoLegacyHiveBoxes.open(
      conversationsMigrated: false,
      chatMemoryMigrated: false,
      openBox: (name) async {
        opened.add(name);
        return _MockBox();
      },
    );

    expect(opened, ['skills', 'conversations', 'chat_memory']);
    expect(boxes.conversations, isNotNull);
    expect(boxes.memory, isNotNull);
  });
}
