final class CavernoCliRedactor {
  CavernoCliRedactor({Iterable<String> secrets = const <String>[]})
    : _secrets = secrets
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();

  static const redacted = '[REDACTED]';

  final Set<String> _secrets;

  String redact(String value) {
    var result = value;
    for (final secret in _secrets) {
      result = result.replaceAll(secret, redacted);
    }
    result = result.replaceAllMapped(
      RegExp(r'\bbearer\s+[^\s,;]+', caseSensitive: false),
      (_) => 'Bearer $redacted',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'''(--api-key|CAVERNO_(?:LLM_)?API_KEY)\s*(?:=|\s)\s*([^\s]+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=$redacted',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'''(["']?(?:api[_-]?key|token|password|secret|authorization)["']?\s*[:=]\s*["']?)([^\s,"'}]+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}$redacted',
    );
    result = result.replaceAllMapped(
      RegExp(r'(https?://[^\s:/@]+:)([^\s/@]+)(@)', caseSensitive: false),
      (match) => '${match.group(1)}$redacted${match.group(3)}',
    );
    return result;
  }

  Object? redactJson(Object? value, {String? key}) {
    if (key != null && _isSensitiveKey(key)) {
      return redacted;
    }
    return switch (value) {
      String string => redact(string),
      List<Object?> values =>
        values.map((item) => redactJson(item)).toList(growable: false),
      Map<Object?, Object?> values => <String, Object?>{
        for (final entry in values.entries)
          entry.key.toString(): redactJson(
            entry.value,
            key: entry.key.toString(),
          ),
      },
      _ => value,
    };
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
    return const {
      'apikey',
      'authorization',
      'credential',
      'password',
      'secret',
      'token',
    }.contains(normalized);
  }
}
