import '../../../settings/domain/entities/app_settings.dart';

/// The user's answer to a local command approval prompt.
class LocalCommandApproval {
  const LocalCommandApproval({
    required this.approved,
    this.rememberedRuleAction,
    this.rememberedRuleMatch,
  });

  final bool approved;
  final LocalCommandPermissionAction? rememberedRuleAction;
  final LocalCommandPermissionMatch? rememberedRuleMatch;

  bool get shouldRemember =>
      rememberedRuleAction != null && rememberedRuleMatch != null;
}
