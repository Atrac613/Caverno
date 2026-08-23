/// Recursively removes common credentials and secret-bearing strings from
/// structured values before they cross a logging or diagnostic boundary.
final class SensitiveDataRedactor {
  const SensitiveDataRedactor._();

  static const String redactedValue = '[redacted]';

  static const Set<String> _sensitiveKeys = {
    'imagebase64',
    'screenshotbase64',
    'audiobase64',
    'accesstoken',
    'password',
    'passwd',
    'pwd',
    'token',
    'secret',
    'clientsecret',
    'credential',
    'credentials',
    'cookie',
    'setcookie',
    'privatekey',
    'sshkey',
    'xapikey',
    'apikey',
    'authorization',
  };

  static final RegExp _privateKeyPattern = RegExp(
    r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
    caseSensitive: false,
  );
  static final RegExp _authorizationHeaderPattern = RegExp(
    r'\b(authorization\s*[:=]\s*)(?:bearer|basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _bearerTokenPattern = RegExp(
    r'\bbearer\s+[A-Za-z0-9._~+/=-]{8,}',
    caseSensitive: false,
  );
  static final RegExp _openAiStyleKeyPattern = RegExp(
    r'\bsk-[A-Za-z0-9_-]{16,}\b',
  );
  static final RegExp _githubTokenPattern = RegExp(
    r'\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,})\b',
  );
  static final RegExp _jwtPattern = RegExp(
    r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
  );
  static final RegExp _urlCredentialPattern = RegExp(
    r'\b(https?://)[^:\s/@]+:[^@\s]+@',
    caseSensitive: false,
  );
  static final RegExp _sensitiveQueryParamPattern = RegExp(
    r'([?&](?:access_token|refresh_token|id_token|api_key|apikey|token|secret|password|auth|authorization|key)=)[^&#\s]+',
    caseSensitive: false,
  );
  static final RegExp _envSecretLinePattern = RegExp(
    r'^(\s*(?:[A-Z][A-Z0-9_]*(?:TOKEN|SECRET|KEY|PASSWORD|PASS|PWD|AUTH)[A-Z0-9_]*|(?:TOKEN|SECRET|KEY|PASSWORD|PASS|PWD|AUTH))\s*=\s*)(.+)$',
    multiLine: true,
  );

  static dynamic redact(
    dynamic value, {
    Iterable<String> additionalSensitiveKeys = const <String>[],
  }) {
    final normalizedAdditionalKeys = additionalSensitiveKeys
        .map(_normalizeKey)
        .toSet();
    return _redactValue(
      value,
      normalizedAdditionalKeys: normalizedAdditionalKeys,
    );
  }

  static dynamic _redactValue(
    dynamic value, {
    String? parentKey,
    required Set<String> normalizedAdditionalKeys,
  }) {
    final normalizedKey = parentKey == null ? null : _normalizeKey(parentKey);
    if (normalizedKey != null &&
        (_sensitiveKeys.contains(normalizedKey) ||
            normalizedAdditionalKeys.contains(normalizedKey))) {
      return redactedValue;
    }
    if (value is String) {
      return redactText(value);
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _redactValue(
            entry.value,
            parentKey: entry.key.toString(),
            normalizedAdditionalKeys: normalizedAdditionalKeys,
          ),
      };
    }
    if (value is Iterable) {
      return value
          .map(
            (item) => _redactValue(
              item,
              normalizedAdditionalKeys: normalizedAdditionalKeys,
            ),
          )
          .toList(growable: false);
    }
    return value;
  }

  static String redactText(String value) {
    var redacted = value.replaceAll(
      _privateKeyPattern,
      '[redacted-private-key]',
    );
    redacted = redacted.replaceAllMapped(
      _authorizationHeaderPattern,
      (match) => '${match.group(1)}[redacted]',
    );
    redacted = redacted.replaceAllMapped(
      _bearerTokenPattern,
      (match) => '${match.group(0)!.split(RegExp(r'\s+')).first} [redacted]',
    );
    redacted = redacted.replaceAll(_openAiStyleKeyPattern, 'sk-[redacted]');
    redacted = redacted.replaceAll(
      _githubTokenPattern,
      '[redacted-github-token]',
    );
    redacted = redacted.replaceAll(_jwtPattern, '[redacted-jwt]');
    redacted = redacted.replaceAllMapped(
      _urlCredentialPattern,
      (match) => '${match.group(1)}[redacted]@',
    );
    redacted = redacted.replaceAllMapped(
      _sensitiveQueryParamPattern,
      (match) => '${match.group(1)}[redacted]',
    );
    redacted = redacted.replaceAllMapped(
      _envSecretLinePattern,
      (match) => '${match.group(1)}[redacted]',
    );
    return redacted;
  }

  static String _normalizeKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
