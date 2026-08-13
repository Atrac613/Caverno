import '../../data/datasources/chat_datasource.dart';
import '../../domain/entities/model_usage_role.dart';

/// Optional owner and inference route for an internal prompt that produces a
/// normal visible assistant response.
final class HiddenPromptLaunchOptions {
  const HiddenPromptLaunchOptions({
    this.visibleUserContent,
    this.targetConversationId,
    this.dataSource,
    this.model,
    this.usageRole = ModelUsageRole.chat,
  });

  final String? visibleUserContent;
  final String? targetConversationId;
  final ChatDataSource? dataSource;
  final String? model;
  final ModelUsageRole usageRole;
}
