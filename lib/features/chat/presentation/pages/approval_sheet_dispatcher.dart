import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/macos_computer_use_service.dart';
import '../providers/chat_notifier.dart';
import '../providers/chat_state.dart';
import '../widgets/approval/assumption_confirmation_sheet.dart';
import '../widgets/approval/ble_connect_approval_sheet.dart';
import '../widgets/approval/computer_use_action_approval_sheet.dart';
import '../widgets/approval/file_operation_approval_sheet.dart';
import '../widgets/approval/git_command_approval_sheet.dart';
import '../widgets/approval/local_command_approval_sheet.dart';
import '../widgets/approval/participant_tool_approval_sheet.dart';
import '../widgets/approval/serial_open_approval_sheet.dart';
import '../widgets/approval/ssh_command_approval_sheet.dart';
import '../widgets/approval/ssh_connect_approval_sheet.dart';

/// Shows one approval sheet and hands its answer back to [ChatNotifier].
///
/// Every one of these is the same four steps — show the sheet, check the page
/// is still mounted, read the notifier, resolve by id — and each new approval
/// type used to add another copy inside the chat page's own library. That
/// library is at its ratchet ceiling, so the eleventh kind (ANA0's material
/// assumption confirmation) had nowhere to go. Here the page pays only for the
/// listener that routes to a method.
///
/// The workflow-decision and ask-user-question sheets stay behind: their sheet
/// widgets are private to the chat page library, so they cannot be named from
/// outside it until they move too.
///
/// [isMounted] is the page's own `mounted`, read after each await. An answer
/// that arrives after the page is gone must not reach the notifier through a
/// disposed `ref`.
class ApprovalSheetDispatcher {
  const ApprovalSheetDispatcher({required this.ref, required this.isMounted});

  final WidgetRef ref;
  final bool Function() isMounted;

  ChatNotifier get _notifier => ref.read(chatNotifierProvider.notifier);

  Future<void> showAssumptionConfirmation(
    BuildContext context,
    PendingAssumptionConfirmation pending,
  ) async {
    final confirmed = await AssumptionConfirmationSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveAssumptionConfirmation(
      id: pending.id,
      confirmed: confirmed ?? false,
    );
  }

  Future<void> showSshConnect(
    BuildContext context,
    PendingSshConnect pending,
  ) async {
    final approval = await SshConnectApprovalSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveSshConnect(id: pending.id, approval: approval);
  }

  Future<void> showSshCommand(
    BuildContext context,
    PendingSshCommand pending,
  ) async {
    final approved = await SshCommandApprovalSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveSshCommand(id: pending.id, approved: approved ?? false);
  }

  Future<void> showGitCommand(
    BuildContext context,
    PendingGitCommand pending,
  ) async {
    final approved = await GitCommandApprovalSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveGitCommand(id: pending.id, approved: approved ?? false);
  }

  Future<void> showLocalCommand(
    BuildContext context,
    PendingLocalCommand pending,
  ) async {
    final approval = await LocalCommandApprovalSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveLocalCommand(
      id: pending.id,
      approval: approval ?? const LocalCommandApproval(approved: false),
    );
  }

  Future<void> showComputerUseAction(
    BuildContext context,
    PendingComputerUseAction pending,
  ) async {
    final decision = await ComputerUseActionApprovalSheet.show(
      context,
      pending,
      stopHelperWork: () =>
          ref.read(macosComputerUseServiceProvider).stopHelperWork(),
    );

    if (!isMounted()) return;
    _notifier.resolveComputerUseAction(
      id: pending.id,
      approved: decision?.approved ?? false,
      armed: decision?.armed ?? !pending.requiresSmokeArming,
    );
  }

  Future<void> showFileOperation(
    BuildContext context,
    PendingFileOperation pending,
  ) async {
    final approved = await FileOperationApprovalSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveFileOperation(id: pending.id, approved: approved ?? false);
  }

  Future<void> showParticipantToolApproval(
    BuildContext context,
    PendingParticipantToolApproval pending,
  ) async {
    final approved = await ParticipantToolApprovalSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveParticipantToolApproval(
      id: pending.id,
      approved: approved ?? false,
    );
  }

  Future<void> showBleConnect(
    BuildContext context,
    PendingBleConnect pending,
  ) async {
    final approved = await BleConnectApprovalSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveBleConnect(id: pending.id, approved: approved ?? false);
  }

  Future<void> showSerialOpen(
    BuildContext context,
    PendingSerialOpen pending,
  ) async {
    final approved = await SerialOpenApprovalSheet.show(context, pending);

    if (!isMounted()) return;
    _notifier.resolveSerialOpen(id: pending.id, approved: approved ?? false);
  }
}
