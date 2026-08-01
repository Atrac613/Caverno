/// Builds recursively immutable snapshots of JSON-compatible tool arguments.
abstract final class ImmutableJsonSnapshot {
  static Map<String, dynamic> freezeMap(
    Map<String, dynamic> source, {
    String argumentName = 'arguments',
  }) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in source.entries)
        entry.key: freezeValue(entry.value, argumentName: argumentName),
    });
  }

  static Object? freezeValue(
    Object? source, {
    String argumentName = 'arguments',
  }) {
    if (source is Map) {
      final frozen = <String, dynamic>{};
      for (final entry in source.entries) {
        final key = entry.key;
        if (key is! String) {
          throw ArgumentError.value(
            key,
            argumentName,
            'Nested map keys must be strings.',
          );
        }
        frozen[key] = freezeValue(entry.value, argumentName: argumentName);
      }
      return Map<String, dynamic>.unmodifiable(frozen);
    }
    if (source is List) {
      return List<Object?>.unmodifiable(
        source.map((value) => freezeValue(value, argumentName: argumentName)),
      );
    }
    if (source is double && !source.isFinite) {
      throw ArgumentError.value(
        source,
        argumentName,
        'Numeric leaves must be finite JSON values.',
      );
    }
    if (source == null || source is String || source is num || source is bool) {
      return source;
    }
    throw ArgumentError.value(
      source,
      argumentName,
      'Leaves must be JSON-compatible immutable values.',
    );
  }
}
