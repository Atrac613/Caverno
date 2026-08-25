import 'code_unit_text_scan.dart';

/// Text tests behind the skipped-`load_skill` recovery.
///
/// A model that answers "I will read the skill" without calling the tool
/// leaves the user with prose instead of the skill; these decide when that
/// shape is worth a recovery call. Nominating only -- the tool call itself
/// still has to succeed for anything to change.
abstract final class SkippedSkillLoadText {
  /// Whether [text] talks about skills at all, in English or Japanese.
  static bool mentionsSkill(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('skill') ||
        CodeUnitTextScan.contains(text, const [0x30b9, 0x30ad, 0x30eb]);
  }

  /// Whether a reply reads as *describing* loading a skill instead of
  /// calling `load_skill` -- the shape the recovery path repairs.
  static bool looksLikeSkippedLoad(String text) {
    final normalized = text.toLowerCase();
    if (!mentionsSkill(text)) {
      return false;
    }
    return normalized.contains('load') ||
        normalized.contains('read') ||
        normalized.contains('use') ||
        normalized.contains('follow') ||
        CodeUnitTextScan.contains(text, const [0x8aad, 0x307f, 0x8fbc]) ||
        CodeUnitTextScan.contains(text, const [0x30ed, 0x30fc, 0x30c9]) ||
        text.contains(String.fromCharCode(0x4f7f));
  }
}
