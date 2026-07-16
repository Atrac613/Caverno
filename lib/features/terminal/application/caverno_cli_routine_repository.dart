import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../routines/data/routine_repository.dart';
import '../../routines/domain/entities/routine.dart';

const cavernoCliRoutinesFileName = 'routines.json';

RoutineRepositoryApi createCavernoCliRoutineRepository({
  required Directory? dataDirectory,
  required SharedPreferences preferences,
}) {
  if (dataDirectory == null) {
    return RoutineRepository(preferences);
  }
  return CavernoCliFileRoutineRepository(
    File('${dataDirectory.path}/$cavernoCliRoutinesFileName'),
  );
}

final class CavernoCliFileRoutineRepository implements RoutineRepositoryApi {
  CavernoCliFileRoutineRepository(this._file);

  final File _file;

  @override
  List<Routine> loadAll() {
    if (!_file.existsSync()) {
      return const <Routine>[];
    }
    try {
      final raw = _file.readAsStringSync();
      if (raw.trim().isEmpty) {
        return const <Routine>[];
      }
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Routine.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on Object {
      return const <Routine>[];
    }
  }

  @override
  Future<void> saveAll(List<Routine> routines) async {
    await _file.parent.create(recursive: true);
    final encoded = jsonEncode(
      routines.map((routine) => routine.toJson()).toList(growable: false),
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
