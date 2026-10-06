import '../entities/conversation.dart';

/// Default title for new conversations (used as a sentinel for auto-title).
const defaultConversationTitle = '__new_conversation__';

/// Whether [conversation] is an untouched empty thread that opening a new one
/// may reuse instead of creating another.
bool isReusableEmptyConversation(Conversation conversation) =>
    conversation.title == defaultConversationTitle &&
    conversation.messages.isEmpty &&
    !conversation.usesWorktree &&
    !conversation.hasWorkflowContext &&
    !conversation.hasGoal &&
    !conversation.hasPlanArtifact &&
    !conversation.hasCompactionArtifact &&
    conversation.executionProgress.isEmpty &&
    conversation.openQuestionProgress.isEmpty;
