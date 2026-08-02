import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Builds a canonical, secret-redacted effective chat tool catalogue.
final class ChatToolCatalogueSnapshotService {
  const ChatToolCatalogueSnapshotService();

  static const schema = 'caverno_chat_tool_catalogue_snapshot';
  static const schemaVersion = 1;
  static const exporterRevision = '1';

  Map<String, Object?> build({
    required List<Map<String, dynamic>> toolDefinitions,
    required DateTime capturedAt,
    required Map<String, dynamic> buildProvenance,
    Iterable<String> secrets = const <String>[],
  }) {
    final build = _validatedBuild(buildProvenance);
    final redactedDefinitions = toolDefinitions
        .map((definition) => _redactJson(definition, secrets))
        .map((definition) => _canonicalizeJson(definition))
        .map((definition) => Map<String, Object?>.from(definition as Map))
        .toList(growable: false);

    redactedDefinitions.sort((left, right) {
      return _toolName(left).compareTo(_toolName(right));
    });
    final seenNames = <String>{};
    for (final definition in redactedDefinitions) {
      final name = _toolName(definition);
      if (!seenNames.add(name)) {
        throw FormatException('Duplicate tool definition name: $name');
      }
    }

    final fingerprintPayload = jsonEncode(<String, Object?>{
      'toolDefinitions': redactedDefinitions,
    });
    final fingerprint = sha256.convert(utf8.encode(fingerprintPayload));

    return <String, Object?>{
      'schema': schema,
      'version': schemaVersion,
      'exporterRevision': exporterRevision,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'build': build,
      'configurationFingerprint': 'sha256:$fingerprint',
      'toolCount': redactedDefinitions.length,
      'toolDefinitions': redactedDefinitions,
    };
  }

  String encode(Map<String, Object?> snapshot) {
    final canonical = _canonicalizeJson(snapshot);
    return '${const JsonEncoder.withIndent('  ').convert(canonical)}\n';
  }

  Map<String, Object?> _validatedBuild(Map<String, dynamic> provenance) {
    final commit = provenance['commit']?.toString().trim() ?? '';
    final dirty = provenance['dirty'];
    if (!RegExp(r'^[0-9a-fA-F]{7,40}$').hasMatch(commit)) {
      throw const FormatException(
        'A canonical build commit is required for catalogue capture',
      );
    }
    if (dirty != false) {
      throw const FormatException(
        'Catalogue capture requires a clean source build',
      );
    }
    final builtAt = provenance['builtAt']?.toString().trim();
    return <String, Object?>{
      'commit': commit.toLowerCase(),
      'dirty': false,
      if (builtAt != null && builtAt.isNotEmpty) 'builtAt': builtAt,
    };
  }

  String _toolName(Map<String, Object?> definition) {
    if (definition['type'] != 'function') {
      throw const FormatException('Tool definitions must use function type');
    }
    final function = definition['function'];
    if (function is! Map) {
      throw const FormatException('Tool definition is missing function data');
    }
    final name = function['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw const FormatException('Tool definition is missing a name');
    }
    return name;
  }

  Object? _redactJson(Object? value, Iterable<String> secrets) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _redactJson(entry.value, secrets),
      };
    }
    if (value is List) {
      return value
          .map((item) => _redactJson(item, secrets))
          .toList(growable: false);
    }
    if (value is String) {
      var redacted = value;
      for (final secret in secrets) {
        final normalized = secret.trim();
        if (normalized.isNotEmpty) {
          redacted = redacted.replaceAll(normalized, '[REDACTED]');
        }
      }
      return redacted;
    }
    if (value == null || value is num || value is bool) {
      return value;
    }
    throw FormatException('Tool definition contains non-JSON value: $value');
  }

  Object? _canonicalizeJson(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList(growable: false)
        ..sort((left, right) {
          return left.key.toString().compareTo(right.key.toString());
        });
      return <String, Object?>{
        for (final entry in entries)
          entry.key.toString(): _canonicalizeJson(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalizeJson).toList(growable: false);
    }
    return value;
  }
}
