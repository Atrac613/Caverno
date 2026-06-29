// Same-library extension on [ChatNotifier]; Riverpod marks `ref` as
// `@protected`, which is not aware of extensions even in the same library.
// ignore_for_file: invalid_use_of_protected_member

part of 'chat_notifier.dart';

extension ChatNotifierPromptContext on ChatNotifier {
  CodingProject? _getEffectiveCodingProject() {
    final project = _getActiveCodingProject();
    if (project == null) {
      return null;
    }
    final worktreePath = ref
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.normalizedWorktreePath;
    if (worktreePath == null || worktreePath.isEmpty) {
      return project;
    }
    return project.copyWith(rootPath: worktreePath);
  }

  String? _loadAgentsMd(AssistantMode assistantMode, CodingProject? project) {
    if (!_settings.enableAgentsMd || assistantMode == AssistantMode.general) {
      return null;
    }
    return ref.read(agentsMdLoaderProvider).loadForProject(project?.rootPath);
  }

  String? _repoMap(AssistantMode assistantMode, CodingProject? project) {
    if (assistantMode == AssistantMode.general) return null;
    final lspSymbolEntries = ref
        .read(repoMapLspSymbolCacheProvider)
        .entriesForRoot(project?.rootPath);
    // LL22: serve from the precompute cache when the project signature is
    // unchanged; otherwise this rebuilds and stores it (a cold first turn).
    return ref
        .read(repoMapPrecomputeCacheProvider)
        .getOrBuild(
          rootPath: project?.rootPath,
          usableContextTokens:
              _settings.effectiveModelCapabilityProfile?.usableContextTokens,
          lspSymbolEntries: lspSymbolEntries,
        );
  }
}
