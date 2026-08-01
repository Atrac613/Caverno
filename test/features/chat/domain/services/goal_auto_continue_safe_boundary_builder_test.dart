import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_safe_boundary_builder.dart';
import 'package:test/test.dart';

void main() {
  const builder = GoalAutoContinueSafeBoundaryBuilder();

  test('maps the all-clear owner snapshot to a safe boundary', () {
    final state = _state();

    final boundary = builder.build(state);

    expect(state.owner, _owner());
    expect(boundary.isSafe, isTrue);
    expect(boundary.firstVetoReason, isNull);
  });

  test('maps every pending field to its exact veto reason', () {
    final cases = <String, GoalAutoContinuePendingState>{
      'response still loading': _state(isLoading: true),
      'queued user input is waiting': _state(queuedUserInputCount: 1),
      'SSH connection approval is pending': _state(hasPendingSshConnect: true),
      'SSH command approval is pending': _state(hasPendingSshCommand: true),
      'git command approval is pending': _state(hasPendingGitCommand: true),
      'local command approval is pending': _state(hasPendingLocalCommand: true),
      'computer-use approval is pending': _state(
        hasPendingComputerUseAction: true,
      ),
      'browser action approval is pending': _state(
        hasPendingBrowserAction: true,
      ),
      'file operation approval is pending': _state(
        hasPendingFileOperation: true,
      ),
      'BLE connection approval is pending': _state(hasPendingBleConnect: true),
      'serial port approval is pending': _state(hasPendingSerialOpen: true),
      'participant tool approval is pending': _state(
        hasPendingParticipantToolApproval: true,
      ),
      'assistant question is pending': _state(hasPendingAskUserQuestion: true),
      'workflow decision is pending': _state(hasPendingWorkflowDecision: true),
      'participant turn is active': _state(hasParticipantTurnRuntime: true),
      'chat state has an error': _state(error: 'failed'),
    };

    for (final entry in cases.entries) {
      final boundary = builder.build(entry.value);
      expect(boundary.isSafe, isFalse, reason: entry.key);
      expect(boundary.firstVetoReason, entry.key);
    }
  });

  test('projects every boundary field without changing its meaning', () {
    final boundary = builder.build(
      _state(
        isLoading: true,
        queuedUserInputCount: 2,
        hasPendingSshConnect: false,
        hasPendingSshCommand: true,
        hasPendingGitCommand: false,
        hasPendingLocalCommand: true,
        hasPendingComputerUseAction: false,
        hasPendingBrowserAction: true,
        hasPendingFileOperation: false,
        hasPendingBleConnect: true,
        hasPendingSerialOpen: false,
        hasPendingParticipantToolApproval: true,
        hasPendingAskUserQuestion: false,
        hasPendingWorkflowDecision: true,
        hasParticipantTurnRuntime: false,
        error: ' failed ',
      ),
    );

    expect(boundary.isLoading, isTrue);
    expect(boundary.hasQueuedUserInput, isTrue);
    expect(boundary.hasPendingSshConnect, isFalse);
    expect(boundary.hasPendingSshCommand, isTrue);
    expect(boundary.hasPendingGitCommand, isFalse);
    expect(boundary.hasPendingLocalCommand, isTrue);
    expect(boundary.hasPendingComputerUseAction, isFalse);
    expect(boundary.hasPendingBrowserAction, isTrue);
    expect(boundary.hasPendingFileOperation, isFalse);
    expect(boundary.hasPendingBleConnect, isTrue);
    expect(boundary.hasPendingSerialOpen, isFalse);
    expect(boundary.hasPendingParticipantToolApproval, isTrue);
    expect(boundary.hasPendingAskUserQuestion, isFalse);
    expect(boundary.hasPendingWorkflowDecision, isTrue);
    expect(boundary.hasParticipantTurnRuntime, isFalse);
    expect(boundary.hasError, isTrue);
  });

  test('preserves the full first-veto ordering for combined state', () {
    const expectedReasons = <String>[
      'response still loading',
      'queued user input is waiting',
      'SSH connection approval is pending',
      'SSH command approval is pending',
      'git command approval is pending',
      'local command approval is pending',
      'computer-use approval is pending',
      'browser action approval is pending',
      'file operation approval is pending',
      'BLE connection approval is pending',
      'serial port approval is pending',
      'participant tool approval is pending',
      'assistant question is pending',
      'workflow decision is pending',
      'participant turn is active',
      'chat state has an error',
    ];

    for (var index = 0; index < expectedReasons.length; index += 1) {
      final boundary = builder.build(_stateWithVetoesFrom(index));
      expect(
        boundary.firstVetoReason,
        expectedReasons[index],
        reason: 'first active veto index $index',
      );
    }
  });

  test('treats zero and negative queue counts as no queued input', () {
    expect(builder.build(_state()).hasQueuedUserInput, isFalse);
    expect(
      builder.build(_state(queuedUserInputCount: -1)).hasQueuedUserInput,
      isFalse,
    );
    expect(
      builder.build(_state(queuedUserInputCount: 3)).hasQueuedUserInput,
      isTrue,
    );
  });

  test('ignores an empty or whitespace-only error', () {
    expect(builder.build(_state(error: null)).hasError, isFalse);
    expect(builder.build(_state(error: '')).hasError, isFalse);
    expect(builder.build(_state(error: ' \n\t ')).hasError, isFalse);
    expect(builder.build(_state(error: ' failure ')).hasError, isTrue);
  });

  test('captures scalar inputs in an immutable owner snapshot', () {
    var sourceOwner = _owner(conversationId: 'owner', generation: 4);
    var sourceQueueCount = 2;
    var sourceError = ' failed ';
    final capturedOwner = sourceOwner;
    final state = _state(
      owner: sourceOwner,
      queuedUserInputCount: sourceQueueCount,
      error: sourceError,
    );

    sourceOwner = _owner(conversationId: 'other', generation: 5);
    sourceQueueCount = 0;
    sourceError = ' ';

    expect(state.owner, same(capturedOwner));
    expect(state.owner, isNot(sourceOwner));
    expect(state.queuedUserInputCount, isNot(sourceQueueCount));
    expect(state.error, isNot(sourceError));
    expect(builder.build(state).hasQueuedUserInput, isTrue);
    expect(builder.build(state).hasError, isTrue);
  });

  test('scopes queue, question, approvals, and runtime to exact owner', () {
    final poisonedOwner = _owner(conversationId: 'owner', generation: 4);
    final otherConversation = _owner(conversationId: 'visible', generation: 4);
    final laterGeneration = _owner(conversationId: 'owner', generation: 5);
    final poisonCases = <String, GoalAutoContinuePendingState>{
      'queued user input is waiting': _state(
        owner: poisonedOwner,
        queuedUserInputCount: 1,
      ),
      'assistant question is pending': _state(
        owner: poisonedOwner,
        hasPendingAskUserQuestion: true,
      ),
      'SSH connection approval is pending': _state(
        owner: poisonedOwner,
        hasPendingSshConnect: true,
        hasPendingSshCommand: true,
        hasPendingGitCommand: true,
        hasPendingLocalCommand: true,
        hasPendingComputerUseAction: true,
        hasPendingBrowserAction: true,
        hasPendingFileOperation: true,
        hasPendingBleConnect: true,
        hasPendingSerialOpen: true,
        hasPendingParticipantToolApproval: true,
      ),
      'participant turn is active': _state(
        owner: poisonedOwner,
        hasParticipantTurnRuntime: true,
      ),
    };

    for (final entry in poisonCases.entries) {
      final poisonedBoundary = builder.build(entry.value);
      final otherConversationBoundary = builder.build(
        _state(owner: otherConversation),
      );
      final laterGenerationBoundary = builder.build(
        _state(owner: laterGeneration),
      );

      expect(entry.value.owner, poisonedOwner, reason: entry.key);
      expect(poisonedBoundary.firstVetoReason, entry.key);
      expect(otherConversationBoundary.isSafe, isTrue, reason: entry.key);
      expect(laterGenerationBoundary.isSafe, isTrue, reason: entry.key);
    }
  });
}

ChatTurnOwner _owner({
  String conversationId = 'conversation-a',
  int generation = 1,
}) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

GoalAutoContinuePendingState _state({
  ChatTurnOwner? owner,
  bool isLoading = false,
  int queuedUserInputCount = 0,
  bool hasPendingSshConnect = false,
  bool hasPendingSshCommand = false,
  bool hasPendingGitCommand = false,
  bool hasPendingLocalCommand = false,
  bool hasPendingComputerUseAction = false,
  bool hasPendingBrowserAction = false,
  bool hasPendingFileOperation = false,
  bool hasPendingBleConnect = false,
  bool hasPendingSerialOpen = false,
  bool hasPendingParticipantToolApproval = false,
  bool hasPendingAskUserQuestion = false,
  bool hasPendingWorkflowDecision = false,
  bool hasParticipantTurnRuntime = false,
  String? error,
}) {
  return GoalAutoContinuePendingState(
    owner: owner ?? _owner(),
    isLoading: isLoading,
    queuedUserInputCount: queuedUserInputCount,
    hasPendingSshConnect: hasPendingSshConnect,
    hasPendingSshCommand: hasPendingSshCommand,
    hasPendingGitCommand: hasPendingGitCommand,
    hasPendingLocalCommand: hasPendingLocalCommand,
    hasPendingComputerUseAction: hasPendingComputerUseAction,
    hasPendingBrowserAction: hasPendingBrowserAction,
    hasPendingFileOperation: hasPendingFileOperation,
    hasPendingBleConnect: hasPendingBleConnect,
    hasPendingSerialOpen: hasPendingSerialOpen,
    hasPendingParticipantToolApproval: hasPendingParticipantToolApproval,
    hasPendingAskUserQuestion: hasPendingAskUserQuestion,
    hasPendingWorkflowDecision: hasPendingWorkflowDecision,
    hasParticipantTurnRuntime: hasParticipantTurnRuntime,
    error: error,
  );
}

GoalAutoContinuePendingState _stateWithVetoesFrom(int firstVetoIndex) {
  return _state(
    isLoading: firstVetoIndex <= 0,
    queuedUserInputCount: firstVetoIndex <= 1 ? 1 : 0,
    hasPendingSshConnect: firstVetoIndex <= 2,
    hasPendingSshCommand: firstVetoIndex <= 3,
    hasPendingGitCommand: firstVetoIndex <= 4,
    hasPendingLocalCommand: firstVetoIndex <= 5,
    hasPendingComputerUseAction: firstVetoIndex <= 6,
    hasPendingBrowserAction: firstVetoIndex <= 7,
    hasPendingFileOperation: firstVetoIndex <= 8,
    hasPendingBleConnect: firstVetoIndex <= 9,
    hasPendingSerialOpen: firstVetoIndex <= 10,
    hasPendingParticipantToolApproval: firstVetoIndex <= 11,
    hasPendingAskUserQuestion: firstVetoIndex <= 12,
    hasPendingWorkflowDecision: firstVetoIndex <= 13,
    hasParticipantTurnRuntime: firstVetoIndex <= 14,
    error: firstVetoIndex <= 15 ? 'failed' : null,
  );
}
