part of 'll37_verifier_fidelity_probe.dart';

Map<String, dynamic> _decodeObject(String contents, String path) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
}

Map<String, dynamic> _decodeResponseObject(String response) {
  var normalized = response.trim();
  if (normalized.startsWith('```')) {
    normalized = normalized
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
  }
  final start = normalized.indexOf('{');
  final end = normalized.lastIndexOf('}');
  if (start < 0 || end < start) {
    throw const FormatException('Verifier response is not a JSON object.');
  }
  return _decodeObject(
    normalized.substring(start, end + 1),
    'verifier response',
  );
}

File _resolveRelativeFile(File source, String reference) {
  final referenced = File(reference);
  if (referenced.isAbsolute) return referenced;
  return File.fromUri(source.parent.uri.resolve(reference));
}

Map<String, dynamic>? _object(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

List<Map<String, dynamic>> _objectList(Object? value) {
  if (value is! List) return const [];
  final result = <Map<String, dynamic>>[];
  for (final item in value) {
    final object = _object(item);
    if (object == null) {
      throw const FormatException('Expected a list of JSON objects.');
    }
    result.add(object);
  }
  return result;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      throw const FormatException('Expected a list of non-empty strings.');
    }
    result.add(item.trim());
  }
  return result;
}

String? _string(Object? value) => value is String ? value : null;

int? _integer(Object? value) => value is num ? value.toInt() : null;

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = _string(json[key])?.trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('Missing `$key` in $path.');
  }
  return value;
}

String _percent(double? value) {
  if (value == null) return '-';
  return '${(value * 100).toStringAsFixed(1)}%';
}

String _cell(String value) => value.replaceAll('|', '\\|');
