import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../../settings/domain/entities/app_settings.dart';

String messageInputAssistantModeLabel(AssistantMode mode) => switch (mode) {
  AssistantMode.general => 'settings.assistant_general'.tr(),
  AssistantMode.coding => 'settings.assistant_coding'.tr(),
  AssistantMode.plan => 'settings.assistant_plan'.tr(),
};

String messageInputReasoningEffortLabel(ReasoningEffortPreference value) =>
    switch (value) {
      ReasoningEffortPreference.automatic =>
        'settings.reasoning_effort_automatic'.tr(),
      ReasoningEffortPreference.low => 'settings.reasoning_effort_low'.tr(),
      ReasoningEffortPreference.medium =>
        'settings.reasoning_effort_medium'.tr(),
      ReasoningEffortPreference.high => 'settings.reasoning_effort_high'.tr(),
    };

String messageInputCodingApprovalLabel(ToolApprovalMode mode) => switch (mode) {
  ToolApprovalMode.defaultPermissions =>
    'settings.coding_approval_default'.tr(),
  ToolApprovalMode.autoReview => 'settings.coding_approval_auto_review'.tr(),
  ToolApprovalMode.fullAccess => 'settings.coding_approval_full_access'.tr(),
};

String messageInputCodingApprovalDescription(ToolApprovalMode mode) =>
    switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.coding_approval_default_desc'.tr(),
      ToolApprovalMode.autoReview =>
        'settings.coding_approval_auto_review_desc'.tr(),
      ToolApprovalMode.fullAccess =>
        'settings.coding_approval_full_access_desc'.tr(),
    };

String messageInputChatApprovalLabel(ToolApprovalMode mode) => switch (mode) {
  ToolApprovalMode.defaultPermissions => 'settings.chat_approval_default'.tr(),
  ToolApprovalMode.autoReview => 'settings.chat_approval_auto_review'.tr(),
  ToolApprovalMode.fullAccess => 'settings.chat_approval_full_access'.tr(),
};

String messageInputChatApprovalDescription(
  ToolApprovalMode mode,
) => switch (mode) {
  ToolApprovalMode.defaultPermissions =>
    'settings.chat_approval_default_desc'.tr(),
  ToolApprovalMode.autoReview => 'settings.chat_approval_auto_review_desc'.tr(),
  ToolApprovalMode.fullAccess => 'settings.chat_approval_full_access_desc'.tr(),
};
