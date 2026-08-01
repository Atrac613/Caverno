import '../../domain/entities/routine.dart';

bool sameExactRoutineCatalog(List<Routine> left, List<Routine> right) {
  if (left.length != right.length ||
      !hasUniqueRoutineIds(left) ||
      !hasUniqueRoutineIds(right)) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool hasUniqueRoutineIds(Iterable<Routine> routines) {
  final ids = <String>{};
  return routines.every((routine) => ids.add(routine.id));
}

/// Collapses only byte-for-byte equivalent duplicate IDs.
///
/// A changed value under an existing ID is ambiguous and therefore rejected.
List<Routine>? collapseExactRoutineDuplicates(Iterable<Routine> routines) {
  final byId = <String, Routine>{};
  final collapsed = <Routine>[];
  for (final routine in routines) {
    final existing = byId[routine.id];
    if (existing == null) {
      byId[routine.id] = routine;
      collapsed.add(routine);
    } else if (existing != routine) {
      return null;
    }
  }
  return collapsed;
}

bool containsUniqueExactRoutine(Iterable<Routine> routines, Routine expected) {
  var matches = 0;
  for (final routine in routines) {
    if (routine.id != expected.id) continue;
    if (routine != expected) return false;
    matches += 1;
  }
  return matches == 1;
}

bool hasOnlyExactTargetMatches(Iterable<Routine> routines, Routine expected) {
  for (final routine in routines) {
    if (routine.id == expected.id && routine != expected) return false;
  }
  return true;
}

/// Allows a retry only when readback contains exact values from the intended
/// catalog. Missing or duplicated entries can result from a partial save, but
/// unknown or changed entries may belong to a concurrent writer.
bool isCompatibleCatalogProjection(
  Iterable<Routine> readback,
  Iterable<Routine> intended,
) {
  final intendedList = intended.toList(growable: false);
  if (!hasUniqueRoutineIds(intendedList)) return false;
  final intendedById = {
    for (final routine in intendedList) routine.id: routine,
  };
  return readback.every((routine) => intendedById[routine.id] == routine);
}

bool isCompatibleCompensationReadback(
  Iterable<Routine> readback,
  Iterable<Routine> stateCatalog,
  Routine createdRoutine,
) {
  final stateList = stateCatalog.toList(growable: false);
  if (!hasUniqueRoutineIds(stateList)) return false;
  final stateById = {for (final routine in stateList) routine.id: routine};
  return readback.every((routine) {
    final stateRoutine = stateById[routine.id];
    if (stateRoutine != null) return stateRoutine == routine;
    return routine.id == createdRoutine.id && routine == createdRoutine;
  });
}

Set<String> reconciledRunningRoutineIds(
  Set<String> runningBefore,
  Iterable<Routine> readback,
) {
  final persistedIds = readback.map((routine) => routine.id).toSet();
  return {...runningBefore.where(persistedIds.contains)};
}
