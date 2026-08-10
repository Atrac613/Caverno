final class RemoteCodingRelayLogRedactor {
  const RemoteCodingRelayLogRedactor._();

  static const String redactedValue = '<redacted>';

  static dynamic redact(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _isSensitiveKey(entry.key.toString())
              ? redactedValue
              : redact(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(redact).toList(growable: false);
    }
    return value;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('signature') ||
        normalized.endsWith('keyid') ||
        normalized.endsWith('nonce') ||
        normalized == 'authorization' ||
        normalized == 'xfirebaseappcheck') {
      return true;
    }
    return const <String>{
      'eventid',
      'turnid',
      'conversationid',
      'deliveryhandle',
      'installationid',
      'managementkeyid',
      'deliverykeyid',
      'delegationid',
      'challengeid',
      'challengedigest',
      'targetdeviceid',
      'idempotencykey',
      'nonce',
    }.contains(normalized);
  }
}
