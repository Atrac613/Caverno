// Same-library extension on [ChatNotifier]; Riverpod marks `ref` as
// `@protected`, which is not aware of extensions even in the same library.
// ignore_for_file: invalid_use_of_protected_member

part of 'chat_notifier.dart';

extension ChatNotifierPromptContext on ChatNotifier {
  String? _loadAgentsMd(AssistantMode assistantMode, CodingProject? project) {
    if (!_settings.enableAgentsMd || assistantMode == AssistantMode.general) {
      return null;
    }
    return ref.read(agentsMdLoaderProvider).loadForProject(project?.rootPath);
  }

  String? _repoMap(AssistantMode assistantMode, CodingProject? project) {
    if (assistantMode == AssistantMode.general) return null;
    return RepoMapService.buildForProject(
      rootPath: project?.rootPath,
      usableContextTokens:
          _settings.effectiveModelCapabilityProfile?.usableContextTokens,
    );
  }
}
