import 'literal_environment_inspection_policy.dart';

/// Recognizes environment inspection whose optional lookup may be absent.
/// Unknown commands retain the masked-status failure diagnostic.
abstract final class MaskedInspectionCommandPolicy {
  static bool applies(String command) {
    final match = RegExp(r'^(.+)\s*\|\|\s*true\s*$').firstMatch(command.trim());
    if (match == null) return false;
    return LiteralEnvironmentInspectionPolicy.applies(match[1]!);
  }
}
