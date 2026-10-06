import '../entities/skill.dart';
import '../entities/tool_call_info.dart';
import 'enabled_skill_named_in_text.dart';
import 'skipped_skill_load_text.dart';

/// Decides whether a turn that named a skill and then answered without loading
/// it should be handed one `load_skill` call.
///
/// Extracted from `_ChatNotifier` because it is a pure function of its inputs:
/// the page's copy read four pieces of state — the disabled-tool set, the
/// turn's latest user content, the enabled skills and the clock — and decided
/// entirely from them. Nothing here needs the notifier, and the library it sat
/// in had three lines left against its ratchet, which is what made the skill
/// carry in [SkillPromptIndexBuilder] unlandable.
///
/// The order of the checks is the cheap-first order the original had, and it
/// matters: [EnabledSkillNamedInText] scans every enabled skill, so the two
/// text predicates in front of it keep that off the common path.
final class SkippedSkillLoadRecovery {
  const SkippedSkillLoadRecovery();

  /// The recovery call to issue, or null to leave the turn alone.
  ///
  /// [responseContent] is what the assistant actually said, already resolved
  /// from the streamed text or the completion. An empty one is treated as a
  /// skipped load: a turn that named a skill and produced nothing has not
  /// declined to use it, it simply has not used it yet.
  ToolCallInfo? resolve({
    required bool hasToolCalls,
    required Set<String> availableToolNames,
    required Set<String> disabledToolNames,
    required String latestUserContent,
    required String responseContent,
    required Iterable<Skill> enabledSkills,
    required DateTime now,
  }) {
    if (hasToolCalls ||
        disabledToolNames.contains('load_skill') ||
        !availableToolNames.contains('load_skill')) {
      return null;
    }
    if (!SkippedSkillLoadText.mentionsSkill(latestUserContent)) {
      return null;
    }

    final skill = EnabledSkillNamedInText.find(
      latestUserContent,
      enabledSkills,
    );
    if (skill == null) {
      return null;
    }

    final trimmedResponse = responseContent.trim();
    if (trimmedResponse.isNotEmpty &&
        !SkippedSkillLoadText.looksLikeSkippedLoad(trimmedResponse)) {
      return null;
    }

    return ToolCallInfo(
      id: 'recovered_load_skill_${now.microsecondsSinceEpoch}',
      name: 'load_skill',
      arguments: {'id': skill.id, 'name': skill.normalizedName},
    );
  }
}
