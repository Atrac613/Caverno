import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/routines/data/routine_repository.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/terminal/application/caverno_cli_routine_repository.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  test('application-default storage remains GUI-compatible', () async {
    final repository = createCavernoCliRoutineRepository(
      dataDirectory: null,
      preferences: preferences,
    );
    final routine = _routine(id: 'default-routine');

    await repository.saveAll(<Routine>[routine]);

    expect(RoutineRepository(preferences).loadAll(), <Routine>[routine]);
  });

  test('explicit data root isolates routines from preferences', () async {
    final directory = await Directory.systemTemp.createTemp(
      'caverno_cli_routines_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = createCavernoCliRoutineRepository(
      dataDirectory: directory,
      preferences: preferences,
    );
    final routine = _routine(id: 'isolated-routine');

    await repository.saveAll(<Routine>[routine]);

    expect(RoutineRepository(preferences).loadAll(), isEmpty);
    expect(
      File('${directory.path}/$cavernoCliRoutinesFileName').existsSync(),
      isTrue,
    );
    expect(
      createCavernoCliRoutineRepository(
        dataDirectory: directory,
        preferences: preferences,
      ).loadAll(),
      <Routine>[routine],
    );
  });

  test(
    'explicit data root replaces the registry without partial files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'caverno_cli_routines_replace_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = createCavernoCliRoutineRepository(
        dataDirectory: directory,
        preferences: preferences,
      );
      final first = _routine(id: 'first');
      final second = _routine(id: 'second');

      await repository.saveAll(<Routine>[first]);
      await repository.saveAll(<Routine>[second]);

      expect(repository.loadAll(), <Routine>[second]);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .map((file) => file.path)
            .where((path) => path.endsWith('.tmp')),
        isEmpty,
      );
    },
  );

  test('malformed explicit registry loads as empty', () async {
    final directory = await Directory.systemTemp.createTemp(
      'caverno_cli_routines_malformed_',
    );
    addTearDown(() => directory.delete(recursive: true));
    File(
      '${directory.path}/$cavernoCliRoutinesFileName',
    ).writeAsStringSync('{not-json');

    final repository = createCavernoCliRoutineRepository(
      dataDirectory: directory,
      preferences: preferences,
    );

    expect(repository.loadAll(), isEmpty);
  });
}

Routine _routine({required String id}) {
  final timestamp = DateTime.utc(2026, 7, 16, 5);
  return Routine(
    id: id,
    name: id,
    prompt: 'Run $id',
    createdAt: timestamp,
    updatedAt: timestamp,
    enabled: false,
  );
}
