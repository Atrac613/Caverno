import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/watch/domain/watch_approval_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = WatchApprovalMapper();

  ChatTurnOwner owner() =>
      ChatTurnOwner(conversationId: 'c-1', interactionGeneration: 1);

  ChatState stateWith({
    PendingFileOperation? file,
    PendingLocalCommand? local,
    PendingGitCommand? git,
    PendingSshConnect? sshConnect,
    PendingSshCommand? sshCommand,
    PendingBleConnect? ble,
    PendingSerialOpen? serial,
    PendingBrowserAction? browser,
    PendingComputerUseAction? computerUse,
    PendingParticipantToolApproval? participant,
    PendingAskUserQuestion? question,
  }) => ChatState(
    messages: const [],
    isLoading: false,
    pendingFileOperation: file,
    pendingLocalCommand: local,
    pendingGitCommand: git,
    pendingSshConnect: sshConnect,
    pendingSshCommand: sshCommand,
    pendingBleConnect: ble,
    pendingSerialOpen: serial,
    pendingBrowserAction: browser,
    pendingComputerUseAction: computerUse,
    pendingParticipantToolApproval: participant,
    pendingAskUserQuestion: question,
  );

  PendingLocalCommand localCommand({String? remoteDeviceId}) =>
      PendingLocalCommand(
        owner: owner(),
        id: 'local-1',
        command: 'rm -rf build',
        workingDirectory: '/repo',
        reason: 'Clean the build directory.',
        warningTitle: 'Destructive',
        warningMessage: 'This deletes files.',
        completer: Completer<LocalCommandApproval>(),
        origin: remoteDeviceId == null
            ? ChatInteractionOrigin.local
            : ChatInteractionOrigin.remote,
        remoteDeviceId: remoteDeviceId,
      );

  group('remote ownership exclusion (SEC4.5g)', () {
    test('surfaces a local-origin approval', () {
      final approval = mapper.map(stateWith(local: localCommand()));

      expect(approval, isNotNull);
      expect(approval!.id, 'local-1');
      expect(approval.kind, WatchApprovalMapper.kindLocalCommand);
      expect(approval.canResolveOnWatch, isTrue);
      // The warning outranks the model's stated reason.
      expect(approval.detail, 'This deletes files.');
    });

    test('hides an approval owned by a paired remote device', () {
      final approval = mapper.map(
        stateWith(local: localCommand(remoteDeviceId: 'device-b')),
      );

      expect(
        approval,
        isNull,
        reason:
            'A Remote Coding device owns this approval; showing it on the '
            'watch would break the SEC4.5g per-device ownership guarantee.',
      );
    });

    test('hides a file operation owned by a remote device', () {
      final approval = mapper.map(
        stateWith(
          file: PendingFileOperation(
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
        ),
      );

      expect(approval, isNull);
    });

    test('hides a git command owned by a remote device', () {
      final approval = mapper.map(
        stateWith(
          git: PendingGitCommand(
            owner: owner(),
            id: 'git-1',
            command: 'git push',
            workingDirectory: '/repo',
            reason: null,
            completer: Completer<bool>(),
            origin: ChatInteractionOrigin.remote,
            remoteDeviceId: 'device-b',
          ),
        ),
      );

      expect(approval, isNull);
    });

    test('hides a remote-origin approval that lost its owner id', () {
      final approval = mapper.map(
        stateWith(
          local: PendingLocalCommand(
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
        ),
      );

      expect(
        approval,
        isNull,
        reason:
            'Inferring "remote" from the presence of an owner id would make a '
            'remote interaction that lost one resolvable from the wrist.',
      );
    });

    test('hides a remote-origin question that lost its owner id', () {
      final question = mapper.mapQuestion(
        stateWith(
          question: PendingAskUserQuestion(
            id: 'q-1',
            conversationId: 'c-1',
            question: 'Which approach?',
            help: '',
            options: const [],
            allowMultiple: false,
            allowOther: false,
            otherPlaceholder: '',
            completer: Completer<AskUserQuestionAnswer?>(),
            origin: ChatInteractionOrigin.remote,
            remoteDeviceId: null,
          ),
        ),
      );

      expect(question, isNull);
    });

    test('hides a remote-owned question', () {
      final question = mapper.mapQuestion(
        stateWith(
          question: PendingAskUserQuestion(
            id: 'q-1',
            conversationId: 'c-1',
            question: 'Which approach?',
            help: '',
            options: const [],
            allowMultiple: false,
            allowOther: false,
            otherPlaceholder: '',
            completer: Completer<AskUserQuestionAnswer?>(),
            origin: ChatInteractionOrigin.remote,
            remoteDeviceId: 'device-b',
          ),
        ),
      );

      expect(question, isNull);
    });
  });

  group('kind coverage', () {
    test('mutating kinds outrank read-only device kinds', () {
      final approval = mapper.map(
        stateWith(
          local: localCommand(),
          ble: PendingBleConnect(
            owner: owner(),
            id: 'ble-1',
            deviceId: 'AA:BB',
            deviceName: 'Sensor',
            completer: Completer<bool>(),
          ),
        ),
      );

      expect(approval!.kind, WatchApprovalMapper.kindLocalCommand);
    });

    test('SSH connect is surfaced but not resolvable on the watch', () {
      final approval = mapper.map(
        stateWith(
          sshConnect: PendingSshConnect(
            owner: owner(),
            id: 'ssh-1',
            host: 'example.internal',
            port: 22,
            username: 'deploy',
            savedCredential: null,
            identityCandidates: const [],
            completer: Completer<SshConnectApproval?>(),
          ),
        ),
      );

      expect(approval, isNotNull);
      expect(approval!.kind, WatchApprovalMapper.kindSshConnect);
      expect(
        approval.canResolveOnWatch,
        isFalse,
        reason: 'Resolving needs credential material the watch cannot supply.',
      );
    });

    test('BLE and serial approvals resolve from the watch', () {
      final ble = mapper.map(
        stateWith(
          ble: PendingBleConnect(
            owner: owner(),
            id: 'ble-1',
            deviceId: 'AA:BB',
            deviceName: 'Sensor',
            completer: Completer<bool>(),
          ),
        ),
      );
      expect(ble!.kind, WatchApprovalMapper.kindBleConnect);
      expect(ble.canResolveOnWatch, isTrue);
      expect(ble.subtitle, 'Sensor');

      final serial = mapper.map(
        stateWith(
          serial: PendingSerialOpen(
            owner: owner(),
            id: 'serial-1',
            portName: '/dev/tty.usb',
            baudRate: 115200,
            completer: Completer<bool>(),
          ),
        ),
      );
      expect(serial!.kind, WatchApprovalMapper.kindSerialOpen);
      expect(serial.canResolveOnWatch, isTrue);
      expect(serial.detail, '115200 baud');
    });

    test('no pending approval maps to null', () {
      expect(mapper.map(stateWith()), isNull);
      expect(mapper.mapQuestion(stateWith()), isNull);
    });
  });

  group('question projection', () {
    test('carries option ids and labels', () {
      final question = mapper.mapQuestion(
        stateWith(
          question: PendingAskUserQuestion(
            id: 'q-1',
            conversationId: 'c-1',
            question: 'Which approach?',
            help: 'Pick one.',
            options: const [
              AskUserQuestionOption(id: 'a', label: 'Rewrite'),
              AskUserQuestionOption(id: 'b', label: 'Patch'),
            ],
            allowMultiple: false,
            allowOther: true,
            otherPlaceholder: 'Something else',
            completer: Completer<AskUserQuestionAnswer?>(),
          ),
        ),
      );

      expect(question, isNotNull);
      expect(question!.options.map((option) => option.id), ['a', 'b']);
      expect(question.allowOther, isTrue);
      expect(question.allowMultiple, isFalse);
    });
  });
}
