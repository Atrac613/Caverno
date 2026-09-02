import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/pending_approval_summary.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatTurnOwner owner() =>
      ChatTurnOwner(conversationId: 'c-1', interactionGeneration: 1);

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
