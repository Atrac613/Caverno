final class ProReasoningGroundedClaimsVerifier {
  const ProReasoningGroundedClaimsVerifier();

  static final _memoryQuantityPattern = RegExp(
    r'\b(\d[\d,]*)(?:\.(\d+))?\s*(GiB|GB|TiB|TB)\b',
    caseSensitive: false,
  );

  List<String> unsupportedMemoryClaims({
    required String evidence,
    required String answer,
  }) {
    final supportedBytes = _extract(
      evidence,
    ).map((quantity) => quantity.bytes).toSet();
    return _extract(answer)
        .where((quantity) => !supportedBytes.contains(quantity.bytes))
        .map((quantity) => quantity.source)
        .toSet()
        .toList(growable: false);
  }

  List<String> memoryClaims(String text) => _extract(
    text,
  ).map((quantity) => quantity.source).toSet().toList(growable: false);

  List<_MemoryQuantity> _extract(String text) => _memoryQuantityPattern
      .allMatches(text)
      .map((match) {
        final whole = match.group(1)!.replaceAll(',', '');
        final fraction = match.group(2) ?? '';
        final unit = match.group(3)!.toLowerCase();
        final scale = _pow10(fraction.length);
        final scaledValue = BigInt.parse('$whole$fraction');
        final bytes = scaledValue * _bytesPerUnit(unit) ~/ scale;
        return _MemoryQuantity(source: match.group(0)!, bytes: bytes);
      })
      .toList(growable: false);

  BigInt _bytesPerUnit(String unit) => switch (unit) {
    'gb' => BigInt.from(1000000000),
    'gib' => BigInt.from(1073741824),
    'tb' => BigInt.from(1000000000000),
    'tib' => BigInt.from(1099511627776),
    _ => throw ArgumentError.value(unit, 'unit', 'Unsupported memory unit'),
  };

  BigInt _pow10(int exponent) {
    var result = BigInt.one;
    for (var index = 0; index < exponent; index++) {
      result *= BigInt.from(10);
    }
    return result;
  }
}

final class _MemoryQuantity {
  const _MemoryQuantity({required this.source, required this.bytes});

  final String source;
  final BigInt bytes;
}
