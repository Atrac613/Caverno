import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/pending_approval_summary.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatTurnOwner owner() =>
      ChatTurnOwner(conversationId: 'c-1', interactionGeneration: 1);

  PendingComputerUseAction computerUseAction() => PendingComputerUseAction(
    owner: owner(),
    id: 'cu-1',
    toolName: 'computer_click',
    title: 'Click Send',
    riskCategory: 'input',
    riskLabel: 'High',
    warningMessage: 'This clicks a button in another app.',
    approveLabel: 'Click',
    requiresUserApproval: true,
    requiresSmokeArming: true,
    emergencyStop: false,
    summary: 'Click at (10, 20)',
    details: const [],
    targetSummary: 'Mail',
    targetDetails: const [],
    exactTextPreview: null,
    exactTextLength: null,
    approvalBoundaries: const [],
    approvalBlockerCodes: const [],
    actionProposalNextAction: null,
    visionObservationSummary: null,
    visionObservationDetails: const [],
    reason: null,
    completer: Completer<ComputerUseActionApprovalDecision>(),
  );

  group('describePendingApproval', () {
    test('a shell command leads with its warning, not its reason', () {
      final summary = describePendingApproval(
        PendingLocalCommand(
          owner: owner(),
          id: 'local-1',
          command: 'rm -rf build',
          workingDirectory: '/repo',
          reason: 'Clean the build directory.',
          warningTitle: 'Destructive',
          warningMessage: 'This deletes files.',
          completer: Completer<LocalCommandApproval>(),
        ),
      );

      expect(summary.kind, PendingApprovalKinds.localCommand);
      expect(summary.title, 'rm -rf build');
      expect(summary.subtitle, '/repo');
      expect(summary.detail, 'This deletes files.');
      expect(summary.isSimpleDecision, isTrue);
      expect(summary.conversationId, 'c-1');
      expect(summary.isOwnedByRemoteDevice, isFalse);
    });

    test('a remote-owned request is flagged as such', () {
      final summary = describePendingApproval(
        PendingFileOperation(
          owner: owner(),
          id: 'file-1',
          operation: 'write_file',
          path: '/repo/main.dart',
          preview: 'void main() {}',
          reason: null,
          completer: Completer<bool>(),
          origin: ChatInteractionOrigin.remote,
          remoteDeviceId: 'device-b',
        ),
      );

      expect(summary.isOwnedByRemoteDevice, isTrue);
    });

    test('a remote origin is excluded even without an owner id', () {
      // The reference gate (RemoteCodingServerNotifier._canResolveInteraction)
      // checks origin first and treats a remote interaction with a missing
      // owner as not resolvable. Reading only remoteDeviceId inverts that.
      final summary = describePendingApproval(
        PendingLocalCommand(
          owner: owner(),
          id: 'local-1',
          command: 'rm -rf build',
          workingDirectory: '/repo',
          reason: null,
          warningTitle: null,
          warningMessage: null,
          completer: Completer<LocalCommandApproval>(),
          origin: ChatInteractionOrigin.remote,
          remoteDeviceId: null,
        ),
      );

      expect(summary.isOwnedByRemoteDevice, isTrue);
    });

    test('an empty remoteDeviceId does not count as remote ownership', () {
      final summary = describePendingApproval(
        PendingGitCommand(
          owner: owner(),
          id: 'git-1',
          command: 'git push',
          workingDirectory: '/repo',
          reason: null,
          completer: Completer<bool>(),
          remoteDeviceId: '   ',
        ),
      );

      expect(summary.isOwnedByRemoteDevice, isFalse);
      expect(summary.origin, ChatInteractionOrigin.local);
    });

    test('kinds needing structured input are not simple decisions', () {
      final sshConnect = describePendingApproval(
        PendingSshConnect(
          owner: owner(),
          id: 'ssh-1',
          host: 'example.internal',
          port: 22,
          username: 'deploy',
          savedCredential: null,
          identityCandidates: const [],
          completer: Completer<SshConnectApproval?>(),
        ),
      );
      expect(sshConnect.kind, PendingApprovalKinds.sshConnect);
      expect(
        sshConnect.isSimpleDecision,
        isFalse,
        reason: 'Resolving needs credential material.',
      );

      final computerUse = describePendingApproval(
        PendingComputerUseAction(
          owner: owner(),
          id: 'cu-1',
          toolName: 'computer_click',
          title: 'Click Send',
          riskCategory: 'input',
          riskLabel: 'High',
          warningMessage: 'This clicks a button in another app.',
          approveLabel: 'Click',
          requiresUserApproval: true,
          requiresSmokeArming: true,
          emergencyStop: false,
          summary: 'Click at (10, 20)',
          details: const [],
          targetSummary: 'Mail',
          targetDetails: const [],
          exactTextPreview: null,
          exactTextLength: null,
          approvalBoundaries: const [],
          approvalBlockerCodes: const [],
          actionProposalNextAction: null,
          visionObservationSummary: null,
          visionObservationDetails: const [],
          reason: null,
          completer: Completer<ComputerUseActionApprovalDecision>(),
        ),
      );
      expect(computerUse.kind, PendingApprovalKinds.computerUse);
      expect(
        computerUse.isSimpleDecision,
        isFalse,
        reason: 'Smoke arming is a second, deliberate gesture.',
      );
    });

    test('device kinds describe the device rather than a command', () {
      final ble = describePendingApproval(
        PendingBleConnect(
          owner: owner(),
          id: 'ble-1',
          deviceId: 'AA:BB',
          deviceName: 'Sensor',
          completer: Completer<bool>(),
        ),
      );
      expect(ble.subtitle, 'Sensor');
      expect(ble.isSimpleDecision, isTrue);

      final serial = describePendingApproval(
        PendingSerialOpen(
          owner: owner(),
          id: 'serial-1',
          portName: '/dev/tty.usb',
          baudRate: 115200,
          completer: Completer<bool>(),
        ),
      );
      expect(serial.subtitle, '/dev/tty.usb');
      expect(serial.detail, '115200 baud');
    });

    test('an assumption confirmation asks the model\'s own question', () {
      final summary = describePendingApproval(
        PendingAssumptionConfirmation(
          owner: owner(),
          id: 'assume-1',
          itemId: 'constraint:stable-entity-ids',
          kind: ConversationContractItemKind.constraint,
          itemText: 'Existing entities have stable UUIDs',
          clarificationQuestion: 'Do existing entities have stable UUIDs?',
          toolName: 'write_file',
          completer: Completer<bool>(),
        ),
      );

      expect(summary.kind, PendingApprovalKinds.assumptionConfirmation);
      expect(summary.subtitle, 'Existing entities have stable UUIDs');
      expect(summary.detail, 'Do existing entities have stable UUIDs?');
      expect(
        summary.isSimpleDecision,
        isTrue,
        reason:
            'Confirm or decline resolves it, so a compact surface can '
            'carry it honestly.',
      );
    });

    test('an assumption with no question says what is blocked instead', () {
      final summary = describePendingApproval(
        PendingAssumptionConfirmation(
          owner: owner(),
          id: 'assume-2',
          itemId: 'constraint:stable-entity-ids',
          kind: ConversationContractItemKind.constraint,
          itemText: 'Existing entities have stable UUIDs',
          clarificationQuestion: null,
          toolName: 'write_file',
          completer: Completer<bool>(),
        ),
      );

      expect(
        summary.detail,
        'Blocked: write_file',
        reason:
            'The model marks materiality without always writing a '
            'question, and an empty detail leaves the interruption '
            'unexplained.',
      );
    });

    test('every kind is ranked, and ranked once', () {
      // `pendingApprovalsByPriority` is a list, so it cannot be exhaustive the
      // way the sealed switch above is. It was not: `assumptionConfirmation`
      // was added later, reported `isSimpleDecision: true`, and appeared in no
      // priority list and no resolution chain — so it could be shown on a
      // compact surface and never answered from one.
      final state = ChatState(
        messages: const [],
        isLoading: false,
        pendingFileOperation: PendingFileOperation(
          owner: owner(),
          id: 'file-1',
          operation: 'write',
          path: 'a.dart',
          preview: '',
          reason: null,
          completer: Completer<bool>(),
        ),
        pendingLocalCommand: PendingLocalCommand(
          owner: owner(),
          id: 'local-1',
          command: 'ls',
          workingDirectory: '/repo',
          reason: null,
          warningTitle: null,
          warningMessage: null,
          completer: Completer<LocalCommandApproval>(),
        ),
        pendingGitCommand: PendingGitCommand(
          owner: owner(),
          id: 'git-1',
          command: 'status',
          workingDirectory: '/repo',
          reason: null,
          completer: Completer<bool>(),
        ),
        pendingSshCommand: PendingSshCommand(
          owner: owner(),
          id: 'sshcmd-1',
          command: 'uptime',
          reason: null,
          host: 'h',
          username: 'u',
          completer: Completer<bool>(),
        ),
        pendingBrowserAction: PendingBrowserAction(
          owner: owner(),
          id: 'browser-1',
          toolName: 'browser_click',
          title: 'Click',
          riskLabel: 'low',
          warningMessage: '',
          approveLabel: 'Allow',
          summary: 'click',
          details: const [],
          targetSummary: null,
          sensitiveValuePreview: null,
          reason: null,
          completer: Completer<bool>(),
        ),
        pendingAssumptionConfirmation: PendingAssumptionConfirmation(
          owner: owner(),
          id: 'assume-1',
          itemId: 'i-1',
          kind: ConversationContractItemKind.constraint,
          itemText: 'The port is free.',
          clarificationQuestion: null,
          toolName: 'write_file',
          completer: Completer<bool>(),
        ),
        pendingBleConnect: PendingBleConnect(
          owner: owner(),
          id: 'ble-1',
          deviceId: 'AA:BB',
          deviceName: null,
          completer: Completer<bool>(),
        ),
        pendingSerialOpen: PendingSerialOpen(
          owner: owner(),
          id: 'serial-1',
          portName: '/dev/tty',
          baudRate: 9600,
          completer: Completer<bool>(),
        ),
        pendingParticipantToolApproval: PendingParticipantToolApproval(
          owner: owner(),
          id: 'participant-1',
          participantId: 'p-1',
          participantName: 'Reviewer',
          participantRoleLabel: 'reviewer',
          toolName: 'read_file',
          arguments: const {},
          reason: null,
          completer: Completer<bool>(),
        ),
        pendingComputerUseAction: computerUseAction(),
        pendingSshConnect: PendingSshConnect(
          owner: owner(),
          id: 'sshconnect-1',
          host: 'h',
          port: 22,
          username: 'u',
          savedCredential: null,
          identityCandidates: const [],
          completer: Completer<SshConnectApproval?>(),
        ),
      );

      final ranked = pendingApprovalsByPriority(
        state,
      ).map((request) => describePendingApproval(request).kind).toList();

      expect(ranked, hasLength(PendingApprovalKinds.all.length));
      expect(ranked.toSet(), PendingApprovalKinds.all.toSet());
      expect(
        ranked.first,
        PendingApprovalKinds.file,
        reason: 'the kinds that change the machine come first',
      );
      expect(
        ranked.sublist(ranked.length - 2).toSet(),
        {PendingApprovalKinds.computerUse, PendingApprovalKinds.sshConnect},
        reason:
            'the two that need input a compact surface cannot collect '
            'must not displace one that can actually be answered',
      );
    });

    test('an unnamed BLE device falls back to its identifier', () {
      final summary = describePendingApproval(
        PendingBleConnect(
          owner: owner(),
          id: 'ble-1',
          deviceId: 'AA:BB',
          deviceName: null,
          completer: Completer<bool>(),
        ),
      );

      expect(summary.subtitle, 'AA:BB');
    });
  });
}
