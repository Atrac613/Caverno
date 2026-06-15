import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/entities/personal_eval_case.dart';

/// LL19 data layer: local-only persistence for recorded personal eval cases.
///
/// Cases are stored as a single JSON file under a provided root directory,
/// mirroring how [LlmSessionLogStore] persists session logs on disk. The store
/// is local-only and excluded from export by design, matching the case
/// privacy policy. The file-based design keeps this unit-testable with a temp
/// directory and decoupled from app bootstrapping.
class PersonalEvalCaseRepository {
  PersonalEvalCaseRepository({
    Future<Directory> Function()? rootDirectoryProvider,
  }) : _rootDirectoryProvider =
           rootDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _rootDirectoryProvider;

  static const storeSchemaName = 'caverno_personal_eval_case_store';
  static const storeSchemaVersion = 1;
  static const _fileName = 'personal_eval_cases.json';

  Future<File> _storeFile() async {
    final root = await _rootDirectoryProvider();
    final directory = Directory('${root.path}/personal_eval');
    await directory.create(recursive: true);
    return File('${directory.path}/$_fileName');
  }

  /// Loads all stored cases. Returns an empty list when the store is missing
  /// or unreadable, so a corrupt file never crashes recording or replay.
  Future<List<PersonalEvalCase>> loadAll() async {
    final file = await _storeFile();
    if (!file.existsSync()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      final rawCases = decoded is Map<String, dynamic>
          ? decoded['cases']
          : decoded;
      if (rawCases is! List) {
        return const [];
      }
      return rawCases
          .whereType<Map>()
          .map(
            (item) =>
                PersonalEvalCase.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Returns the stored cases on the given held-in / held-out split.
  Future<List<PersonalEvalCase>> casesForSplit(
    PersonalEvalCaseSplit split,
  ) async {
    final all = await loadAll();
    return all.where((item) => item.split == split).toList(growable: false);
  }

  /// Upserts a case by [PersonalEvalCase.caseId].
  Future<PersonalEvalCase> save(PersonalEvalCase evalCase) async {
    final id = evalCase.caseId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Personal eval case id is required');
    }
    final cases = List<PersonalEvalCase>.from(await loadAll());
    final index = cases.indexWhere((item) => item.caseId == id);
    if (index == -1) {
      cases.add(evalCase);
    } else {
      cases[index] = evalCase;
    }
    await _write(cases);
    return evalCase;
  }

  /// Reassigns a stored case to a different held-in / held-out split.
  Future<void> setSplit(String caseId, PersonalEvalCaseSplit split) async {
    final id = caseId.trim();
    if (id.isEmpty) {
      return;
    }
    final cases = await loadAll();
    final index = cases.indexWhere((item) => item.caseId == id);
    if (index == -1) {
      return;
    }
    final updated = List<PersonalEvalCase>.from(cases);
    updated[index] = updated[index].copyWith(split: split);
    await _write(updated);
  }

  Future<void> delete(String caseId) async {
    final id = caseId.trim();
    if (id.isEmpty) {
      return;
    }
    final cases = (await loadAll())
        .where((item) => item.caseId != id)
        .toList(growable: false);
    await _write(cases);
  }

  Future<void> _write(List<PersonalEvalCase> cases) async {
    final file = await _storeFile();
    final payload = <String, dynamic>{
      'schemaName': storeSchemaName,
      'schemaVersion': storeSchemaVersion,
      'cases': cases.map((item) => item.toJson()).toList(growable: false),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }
}
