// Same-library extension on [ChatNotifier]; `ref`/`state` are reached through
// the part-of bridge. Riverpod marks them `@protected`/`@visibleForTesting`,
// which are not aware of extensions even in the same library.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// In-chat skill authoring (SKILL1): the write-side inverse of `load_skill`.
///
/// `save_skill` distills the current conversation into a reusable skill and
/// persists it through the same path as the settings UI
/// ([SkillsNotifier.upsertMarkdown]). The write is always gated by an explicit,
/// non-cacheable approval: it never consults or populates [ToolApprovalCache],
/// so a skill is never written silently and a repeated call can never resolve
/// from a prior decision.
extension ChatNotifierSkillHandlers on ChatNotifier {
  Future<McpToolResult> _handleSaveSkill(ToolCallInfo toolCall) async {
    final arguments = toolCall.arguments;
    final name = (arguments['name'] as String?)?.trim() ?? '';
    final description = (arguments['description'] as String?)?.trim() ?? '';
    final whenToUse = (arguments['when_to_use'] as String?)?.trim() ?? '';
    final body = (arguments['content'] as String?)?.trim() ?? '';
    final reason = (arguments['reason'] as String?)?.trim();

    if (name.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'name is required',
      );
    }
    if (body.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'content (the skill body) is required',
      );
    }

    final markdown = SkillMarkdownParser.composeMarkdown(
      name: name,
      description: description,
      whenToUse: whenToUse,
      body: body,
    );

    // Resolve an existing skill by name so a repeat save updates it instead of
    // creating a duplicate.
    final existing = _findSkillByName(name);

    // SKILL2: an update (edit/merge) previews a diff against the stored skill so
    // the user sees exactly what changes; a brand-new skill previews its full
    // body. Duplicating is just a save under a new name (no existing match).
    final preview = existing == null
        ? markdown
        : FilesystemTools.buildUnifiedDiff(
            path: 'skill: $name',
            oldContent: SkillMarkdownParser.toMarkdown(existing),
            newContent: markdown,
          );

    // SKILL1: the write is non-cacheable. Go straight to a manual approval that
    // previews the resolved skill; never auto-review and never remember the
    // decision, so every save_skill requires fresh confirmation.
    final approved = await requestFileOperation(
      operation: existing == null ? 'Save Skill' : 'Update Skill',
      path: name,
      preview: preview,
      reason: reason,
    );
    if (!approved) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'User denied saving the skill',
      );
    }

    try {
      final saved = await ref
          .read(skillsNotifierProvider.notifier)
          .upsertMarkdown(existingId: existing?.id, markdown: markdown);
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'ok': true,
          'action': existing == null ? 'created' : 'updated',
          'id': saved.id,
          'name': saved.normalizedName,
          'enabled': saved.enabled,
        }),
        isSuccess: true,
      );
    } catch (error) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'Failed to save skill: $error',
      );
    }
  }

  Skill? _findSkillByName(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final skill in ref.read(skillsNotifierProvider).skills) {
      if (skill.normalizedName.toLowerCase() == normalized) {
        return skill;
      }
    }
    return null;
  }
}
