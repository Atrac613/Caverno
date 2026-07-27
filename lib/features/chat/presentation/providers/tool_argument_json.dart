import 'dart:convert';

/// Decodes [value] as a JSON object, or returns null when it is not one.
///
/// Tool results are strings by contract, so every consumer that wants a field
/// out of one starts here. Malformed output is expected rather than
/// exceptional — the model writes these — so a failure is a null, not a throw.
Map<String, dynamic>? decodeJsonObject(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Reads [key] from a tool call's arguments as a trimmed string, treating a
/// missing key, a null and a non-string alike as absent.
String trimStringArgument(Map<String, dynamic> arguments, String key) {
  return (arguments[key] as String?)?.trim() ?? '';
}
