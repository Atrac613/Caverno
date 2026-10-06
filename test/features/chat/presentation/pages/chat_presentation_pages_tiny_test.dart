// One suite for the 7 tiny pages test files
// this replaces. Each paid a full suite-loading cost to run at most
// 3 tests. Part files keep every case set in its own file without
// adding a suite, which is the split the file-size ratchet asks for.

import 'dart:convert';
import 'dart:io';
import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/widgets/conversation_drawer.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';
import 'package:caverno/features/dashboard/presentation/widgets/dashboard_view.dart';
import 'package:caverno/features/personal_eval/presentation/pages/personal_eval_record_page.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/routines/presentation/widgets/routine_editor_sheet.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/model_catalog_entry.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'chat_page_computer_use_approval_cases.dart';
part 'chat_page_personal_eval_record_cases.dart';
part 'chat_page_plan_review_actions_cases.dart';
part 'chat_page_routines_create_cases.dart';
part 'chat_page_scroll_follow_cases.dart';
part 'chat_page_state_transition_cases.dart';
part 'chat_page_thread_open_scroll_cases.dart';

void main() {
  _runChatPageComputerUseApproval();
  _runChatPagePersonalEvalRecord();
  _runChatPagePlanReviewActions();
  _runChatPageRoutinesCreate();
  _runChatPageScrollFollow();
  _runChatPageStateTransition();
  _runChatPageThreadOpenScroll();
}
