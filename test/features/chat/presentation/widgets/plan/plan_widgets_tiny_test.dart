// One suite for the 4 tiny plan test files
// this replaces. Each paid a full suite-loading cost to run at most
// 3 tests. Part files keep every case set in its own file without
// adding a suite, which is the split the file-size ratchet asks for.

import 'dart:convert';
import 'dart:io';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/compact_plan_footer_card.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/plan_review_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/task_precondition_notice.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/timeline_plan_card.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

part 'compact_plan_footer_card_cases.dart';
part 'plan_review_sheet_cases.dart';
part 'task_precondition_notice_cases.dart';
part 'timeline_plan_card_cases.dart';

void main() {
  _runCompactPlanFooterCard();
  _runPlanReviewSheet();
  _runTaskPreconditionNotice();
  _runTimelinePlanCard();
}
