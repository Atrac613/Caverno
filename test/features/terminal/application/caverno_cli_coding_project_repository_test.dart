import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/chat/data/repositories/coding_project_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/terminal/application/caverno_cli_coding_project_repository.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  test(
    'application-default storage remains shared-preferences compatible',
    () async {
      final repository = createCavernoCliCodingProjectRepository(
        dataDirectory: null,
        preferences: preferences,
      );
      final project = _project(id: 'default-project', rootPath: '/tmp/default');

      await repository.saveAll(<CodingProject>[project]);

      expect(CodingProjectRepository(preferences).loadAll(), <CodingProject>[
        project,
      ]);
    },
  );

  test(
    'explicit data root isolates project storage from preferences',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'caverno_cli_projects_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = createCavernoCliCodingProjectRepository(
        dataDirectory: directory,
        preferences: preferences,
      );
      final older = _project(
        id: 'older-project',
        rootPath: '/tmp/older',
        updatedAt: DateTime(2026, 7, 15),
      );
      final newer = _project(
        id: 'newer-project',
        rootPath: '/tmp/newer',
        updatedAt: DateTime(2026, 7, 16),
      );

      await repository.saveAll(<CodingProject>[older, newer]);

      expect(CodingProjectRepository(preferences).loadAll(), isEmpty);
      expect(
        File(
          '${directory.path}/$cavernoCliCodingProjectsFileName',
        ).existsSync(),
        isTrue,
      );
      expect(
        createCavernoCliCodingProjectRepository(
          dataDirectory: directory,
          preferences: preferences,
        ).loadAll(),
        <CodingProject>[newer, older],
      );
    },
  );

  test(
    'explicit data root replaces the registry without partial files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'caverno_cli_projects_replace_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = createCavernoCliCodingProjectRepository(
        dataDirectory: directory,
        preferences: preferences,
      );
      final first = _project(id: 'first', rootPath: '/tmp/first');
      final second = _project(id: 'second', rootPath: '/tmp/second');

      await repository.saveAll(<CodingProject>[first]);
      await repository.saveAll(<CodingProject>[second]);

      expect(repository.loadAll(), <CodingProject>[second]);
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
      'caverno_cli_projects_malformed_',
    );
    addTearDown(() => directory.delete(recursive: true));
    File(
      '${directory.path}/$cavernoCliCodingProjectsFileName',
    ).writeAsStringSync('{not-json');

    final repository = createCavernoCliCodingProjectRepository(
      dataDirectory: directory,
      preferences: preferences,
    );

    expect(repository.loadAll(), isEmpty);
  });
}

CodingProject _project({
  required String id,
  required String rootPath,
  DateTime? updatedAt,
}) {
  final timestamp = updatedAt ?? DateTime(2026, 7, 16, 12);
  return CodingProject(
    id: id,
    name: id,
    rootPath: rootPath,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
