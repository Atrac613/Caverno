import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_generation_dao.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_schema.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late Rag2DriftGenerationDao dao;

  setUp(() {
    database = AppDatabase.memory();
    dao = Rag2DriftGenerationDao(database);
  });

  tearDown(() async => database.close());

  test('upserts every envelope column on replacement', () async {
    await dao.ensureHostedSchema();
    await dao.upsertGeneration(
      Rag2GenerationsCompanion.insert(
        projectIdentity: 'project-a',
        declarationIdentity: 'declaration-a',
        schemaName: rag2DriftStoreSchema,
        schemaVersion: rag2DriftStoreSchemaVersion,
        contract: rag2DriftAdditiveSchemaContract,
        projectId: 'project-id',
        generation: 1,
        snapshotHash: 'hash-1',
        payload: '{"generation":1}',
      ),
    );
    await dao.upsertGeneration(
      Rag2GenerationsCompanion.insert(
        projectIdentity: 'project-a',
        declarationIdentity: 'declaration-a',
        schemaName: rag2DriftStoreSchema,
        schemaVersion: rag2DriftStoreSchemaVersion,
        contract: rag2DriftAdditiveSchemaContract,
        projectId: 'project-id',
        generation: 2,
        snapshotHash: 'hash-2',
        payload: '{"generation":2}',
      ),
    );

    final row = await dao.readGeneration(
      projectIdentity: 'project-a',
      declarationIdentity: 'declaration-a',
    );
    expect(row?.schemaName, rag2DriftStoreSchema);
    expect(row?.schemaVersion, rag2DriftStoreSchemaVersion);
    expect(row?.contract, rag2DriftAdditiveSchemaContract);
    expect(row?.projectId, 'project-id');
    expect(row?.generation, 2);
    expect(row?.snapshotHash, 'hash-2');
    expect(row?.payload, '{"generation":2}');
  });

  test('refuses metadata that is not the hosted v1 envelope', () async {
    await dao.ensureHostedSchema();
    await (database.update(database.rag2StoreMeta)
          ..where((table) => table.key.equals('schema_version')))
        .write(const Rag2StoreMetaCompanion(value: Value('2')));

    await expectLater(
      dao.ensureHostedSchema(),
      throwsA(
        isA<Rag2DriftSchemaException>().having(
          (error) => error.reason,
          'reason',
          'unsupported_schema',
        ),
      ),
    );
  });
}
