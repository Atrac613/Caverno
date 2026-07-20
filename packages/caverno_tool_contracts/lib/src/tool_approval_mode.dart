/// Approval policy levels shared by coding and chat tool execution.
///
/// - [defaultPermissions]: prompt the user before each high-risk action.
/// - [autoReview]: let the configured LLM endpoint allow or deny each action.
/// - [fullAccess]: run high-risk actions without an approval prompt.
enum ToolApprovalMode { defaultPermissions, autoReview, fullAccess }
