// One suite for the 11 tiny widgets test files
// this replaces. Each paid a full suite-loading cost to run at most
// 3 tests. Part files keep every case set in its own file without
// adding a suite, which is the split the file-size ratchet asks for.

import 'dart:convert';
import 'dart:io';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/domain/services/html_preview_session_controller.dart';
import 'package:caverno/features/chat/domain/services/html_preview_static_server.dart';
import 'package:caverno/features/chat/domain/services/html_project_detector.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_models.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/flutter_run_provider.dart';
import 'package:caverno/features/chat/presentation/providers/html_preview_provider.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';
import 'package:caverno/features/chat/presentation/widgets/anabasis_speaker_header.dart';
import 'package:caverno/features/chat/presentation/widgets/chat_page_scaffold.dart';
import 'package:caverno/features/chat/presentation/widgets/composer_attachment_button.dart';
import 'package:caverno/features/chat/presentation/widgets/composer_dropped_attachment_intake.dart';
import 'package:caverno/features/chat/presentation/widgets/flutter_run_control_section.dart';
import 'package:caverno/features/chat/presentation/widgets/html_preview_control_section.dart';
import 'package:caverno/features/chat/presentation/widgets/local_llm_health_section.dart';
import 'package:caverno/features/chat/presentation/widgets/pro_reasoning_progress_card.dart';
import 'package:caverno/features/chat/presentation/widgets/project_run_control_section.dart';
import 'package:caverno/features/chat/presentation/widgets/queued_messages_strip.dart';
import 'package:caverno/features/chat/presentation/widgets/slash_command_help_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/workflow_status_presentation.dart';
import 'package:caverno/features/settings/domain/entities/local_llm_health.dart';
import 'package:caverno/features/settings/presentation/providers/local_llm_health_provider.dart';
import 'package:caverno/features/settings/presentation/providers/local_model_lifecycle_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'anabasis_speaker_header_cases.dart';
part 'chat_page_scaffold_cases.dart';
part 'composer_attachment_button_cases.dart';
part 'composer_dropped_attachment_intake_cases.dart';
part 'html_preview_control_section_cases.dart';
part 'local_llm_health_section_cases.dart';
part 'pro_reasoning_progress_card_cases.dart';
part 'project_run_control_section_cases.dart';
part 'queued_messages_strip_cases.dart';
part 'slash_command_help_sheet_cases.dart';
part 'workflow_status_presentation_cases.dart';

void main() {
  _runAnabasisSpeakerHeader();
  _runChatPageScaffold();
  _runComposerAttachmentButton();
  _runComposerDroppedAttachmentIntake();
  _runHtmlPreviewControlSection();
  _runLocalLlmHealthSection();
  _runProReasoningProgressCard();
  _runProjectRunControlSection();
  _runQueuedMessagesStrip();
  _runSlashCommandHelpSheet();
  _runWorkflowStatusPresentation();
}
