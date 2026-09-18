// One suite for the 7 tiny approval test files
// this replaces. Each paid a full suite-loading cost to run at most
// 3 tests. Part files keep every case set in its own file without
// adding a suite, which is the split the file-size ratchet asks for.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:caverno/core/services/ssh_host_key.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/ble_connect_approval_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/file_operation_approval_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/git_command_approval_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/local_command_approval_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/participant_tool_approval_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/serial_open_approval_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/ssh_host_key_approval_sheet.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

part 'ble_connect_approval_sheet_cases.dart';
part 'file_operation_approval_sheet_cases.dart';
part 'git_command_approval_sheet_cases.dart';
part 'local_command_approval_sheet_cases.dart';
part 'participant_tool_approval_sheet_cases.dart';
part 'serial_open_approval_sheet_cases.dart';
part 'ssh_host_key_approval_sheet_cases.dart';

void main() {
  _runBleConnectApprovalSheet();
  _runFileOperationApprovalSheet();
  _runGitCommandApprovalSheet();
  _runLocalCommandApprovalSheet();
  _runParticipantToolApprovalSheet();
  _runSerialOpenApprovalSheet();
  _runSshHostKeyApprovalSheet();
}
