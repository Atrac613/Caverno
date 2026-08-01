import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/providers/routine_catalog_reconciliation.dart';
import 'package:test/test.dart';

void main() {
  group('routine catalog reconciliation', () {
    test('rejects duplicate IDs instead of collapsing them by map key', () {
      final first = _routine('routine-a');
      final second = _routine('routine-b');

      expect(sameExactRoutineCatalog([first, first], [first, second]), isFalse);
      expect(hasUniqueRoutineIds([first, first]), isFalse);
    });

    test('permits only exact known values as a recoverable projection', () {
      final first = _routine('routine-a');
      final second = _routine('routine-b');
      final changed = second.copyWith(name: 'Changed');
      final unknown = _routine('routine-c');

      expect(
        isCompatibleCatalogProjection([first, first], [first, second]),
        isTrue,
      );
      expect(
        isCompatibleCatalogProjection([first, changed], [first, second]),
        isFalse,
      );
      expect(
        isCompatibleCatalogProjection([first, unknown], [first, second]),
        isFalse,
      );
    });

    test('rejects changed and unknown compensation readback values', () {
      final first = _routine('routine-a');
      final created = _routine('routine-created');

      expect(
        isCompatibleCompensationReadback(
          [first, created, created],
          [first, created],
          created,
        ),
        isTrue,
      );
      expect(
        isCompatibleCompensationReadback(
          [first, created.copyWith(prompt: 'Changed')],
          [first, created],
          created,
        ),
        isFalse,
      );
      expect(
        isCompatibleCompensationReadback(
          [first, _routine('routine-unknown')],
          [first, created],
          created,
        ),
        isFalse,
      );
    });
  });
}

Routine _routine(String id) {
  final createdAt = DateTime.utc(2026, 7, 31);
  return Routine(
    id: id,
    name: 'Routine $id',
    prompt: 'Run $id',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
