import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../chat/data/repositories/coding_project_repository.dart';
import '../../chat/domain/entities/coding_project.dart';

const cavernoCliCodingProjectsFileName = 'coding_projects.json';

CodingProjectRepositoryApi createCavernoCliCodingProjectRepository({
  required Directory? dataDirectory,
  required SharedPreferences preferences,
}) {
  if (dataDirectory == null) {
    return CodingProjectRepository(preferences);
  }
  return CavernoCliFileCodingProjectRepository(
    File('${dataDirectory.path}/$cavernoCliCodingProjectsFileName'),
  );
}

final class CavernoCliFileCodingProjectRepository
    implements CodingProjectRepositoryApi {
  CavernoCliFileCodingProjectRepository(this._file);

  final File _file;

  @override
  List<CodingProject> loadAll() {
    if (!_file.existsSync()) {
      return const <CodingProject>[];
    }
    try {
      final raw = _file.readAsStringSync();
      if (raw.trim().isEmpty) {
        return const <CodingProject>[];
      }
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => CodingProject.fromJson(item as Map<String, dynamic>))
          .toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } on Object {
      return const <CodingProject>[];
    }
  }

  @override
  Future<void> saveAll(List<CodingProject> projects) async {
    await _file.parent.create(recursive: true);
    final encoded = jsonEncode(
      projects.map((project) => project.toJson()).toList(growable: false),
    );
    final temporaryFile = File(
      '${_file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporaryFile.writeAsString(encoded, flush: true);
      await temporaryFile.rename(_file.path);
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }
}
