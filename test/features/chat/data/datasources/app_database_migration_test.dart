import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';

void main() {
  late Directory tempDir;
  late File databaseFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('caverno_migration_test');
    databaseFile = File('${tempDir.path}/caverno.sqlite');
  });

  tearDown(() async => tempDir.delete(recursive: true));

  AppDatabase open() => AppDatabase(NativeDatabase(databaseFile));

  test('upgrading from v3 creates the model usage table', () async {
    // Simulate a database written by the previous release: the table does not
    // exist yet and the recorded schema version is still 3.
    final before = open();
    await before.customStatement('DROP TABLE IF EXISTS model_usage_daily');
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final after = open();
    addTearDown(after.close);

    // Forces the migration to run.
    final rows = await after.select(after.modelUsageDaily).get();
    expect(rows, isEmpty);

    final version = await after.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 4);
  });

  test('an upgraded database accepts usage rows', () async {
    final before = open();
    await before.customStatement('DROP TABLE IF EXISTS model_usage_daily');
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final after = open();
    addTearDown(after.close);

    await after
        .into(after.modelUsageDaily)
        .insert(
          ModelUsageDailyCompanion.insert(
            dayNumber: modelUsageDayNumber(DateTime(2026, 8, 8)),
            model: 'model-a',
            totalTokens: const Value(120),
          ),
        );

    final rows = await after.select(after.modelUsageDaily).get();
    expect(rows.single.totalTokens, 120);
    expect(rows.single.role, 'unknown', reason: 'the column default applies');
  });

  test('existing conversations survive the upgrade', () async {
    final before = open();
    await before
        .into(before.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: 'c1',
            payload: '{"id":"c1"}',
            title: const Value('Kept'),
          ),
        );
    await before.customStatement('DROP TABLE IF EXISTS model_usage_daily');
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final after = open();
    addTearDown(after.close);

    final conversations = await after.select(after.conversations).get();
    expect(conversations.single.title, 'Kept');
  });
}
