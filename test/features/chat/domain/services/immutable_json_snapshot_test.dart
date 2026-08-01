import 'package:caverno/features/chat/domain/services/immutable_json_snapshot.dart';
import 'package:test/test.dart';

void main() {
  test('recursively freezes JSON maps and lists with stable types', () {
    final nested = <String, dynamic>{
      'paths': <Object?>[
        'lib/main.dart',
        <String, dynamic>{'owner': 'owner-a'},
      ],
    };

    final frozen = ImmutableJsonSnapshot.freezeMap(nested);
    (nested['paths'] as List<Object?>).add('lib/visible.dart');
    ((nested['paths'] as List<Object?>)[1] as Map<String, dynamic>)['owner'] =
        'owner-b';

    final paths = frozen['paths'] as List<Object?>;
    expect(paths, [
      'lib/main.dart',
      {'owner': 'owner-a'},
    ]);
    expect(paths[1], isA<Map<String, dynamic>>());
    expect(() => paths.add('late'), throwsUnsupportedError);
    expect(
      () => (paths[1] as Map<String, dynamic>)['owner'] = 'late',
      throwsUnsupportedError,
    );
  });

  test('rejects non-string keys and non-JSON mutable leaves', () {
    expect(
      () => ImmutableJsonSnapshot.freezeMap({
        'nested': <Object?, Object?>{7: 'invalid'},
      }),
      throwsArgumentError,
    );
    expect(
      () => ImmutableJsonSnapshot.freezeMap({'mutable': _MutableValue()}),
      throwsArgumentError,
    );
    expect(
      () => ImmutableJsonSnapshot.freezeMap({
        'set': <Object?>{'not-json'},
      }),
      throwsArgumentError,
    );
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => ImmutableJsonSnapshot.freezeMap({'number': value}),
        throwsArgumentError,
        reason: value.toString(),
      );
    }
  });
}

final class _MutableValue {
  var value = 0;
}
