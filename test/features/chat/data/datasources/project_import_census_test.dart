import 'dart:io';

import 'package:caverno/features/chat/data/datasources/project_import_census.dart';
import 'package:flutter_test/flutter_test.dart';

/// Import breadth: how many of the project's own files import each package.
/// It decides which dependencies KC2's block names, so it has to count what
/// the author wrote, not what a generator emitted, and follow edits cheaply.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('import_census_test_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  File write(String path, String text) => File('${root.path}/lib/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  test('counts files, not directives, and skips generated files', () {
    write(
      'a.dart',
      "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
          "import 'package:flutter_riverpod/legacy.dart';\n"
          "export 'package:uuid/uuid.dart';\n",
    );
    write('b.dart', 'import "package:flutter_riverpod/misc.dart";\n');
    write(
      'a.g.dart',
      "import 'package:json_annotation/json_annotation.dart';\n",
    );
    write('a.freezed.dart', "import 'package:collection/collection.dart';\n");
    write('notes.txt', "import 'package:ignored/ignored.dart';\n");

    expect(ProjectImportCensus().count(root.path), {
      'flutter_riverpod': 2,
      'uuid': 1,
    });
  });

  test('follows an edit and a deletion', () async {
    final census = ProjectImportCensus();
    final a = write('a.dart', "import 'package:http/http.dart';\n");
    write('b.dart', "import 'package:http/http.dart';\n");
    expect(census.count(root.path), {'http': 2});

    // A longer body, so the size changes as well as the mtime.
    a.writeAsStringSync("import 'package:dio/dio.dart';\n// switched client\n");
    File('${root.path}/lib/b.dart').deleteSync();
    expect(census.count(root.path), {'dio': 1});
  });

  test('a project without lib/ imports nothing', () {
    expect(ProjectImportCensus().count(root.path), isEmpty);
  });
}
