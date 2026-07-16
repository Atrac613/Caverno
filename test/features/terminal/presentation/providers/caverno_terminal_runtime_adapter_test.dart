import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/terminal/presentation/providers/caverno_terminal_runtime_adapter.dart';

void main() {
  late ProviderContainer container;
  late CavernoTerminalRuntimeAdapter adapter;
  late ChatNotifier notifier;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        chatNotifierProvider.overrideWith(_TerminalTestChatNotifier.new),
      ],
    );
    adapter = CavernoTerminalRuntimeAdapter(
      container: container,
      environment: const <String, String>{},
    );
    notifier = container.read(chatNotifierProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('resolves a production local-command pending action', () async {
    final result = notifier.requestLocalCommand(
      command: 'dart test',
      workingDirectory: '/tmp/project',
    );
    final id = container.read(chatNotifierProvider).pendingLocalCommand!.id;

    await adapter.resolveApproval(id: id, approved: true);

    expect((await result).approved, isTrue);
    expect(container.read(chatNotifierProvider).pendingLocalCommand, isNull);
  });

  test(
    'maps a terminal option index to the production question answer',
    () async {
      final result = notifier.requestAskUserQuestion(
        question: 'Choose a target',
        help: '',
        options: const <AskUserQuestionOption>[
          AskUserQuestionOption(id: 'local', label: 'Local'),
          AskUserQuestionOption(id: 'remote', label: 'Remote'),
        ],
        allowMultiple: false,
        allowOther: false,
        otherPlaceholder: '',
      );
      final id = container
          .read(chatNotifierProvider)
          .pendingAskUserQuestion!
          .id;

      await adapter.resolveQuestion(id: id, answer: '2');

      final answer = await result;
      expect(answer, isNotNull);
      expect(answer!.selectedOptions.single.id, 'remote');
    },
  );

  test('maps a terminal option index to a workflow decision', () async {
    final result = notifier.requestWorkflowDecision(
      decision: const WorkflowPlanningDecision(
        id: 'decision-1',
        question: 'Continue?',
        options: <WorkflowPlanningDecisionOption>[
          WorkflowPlanningDecisionOption(id: 'continue', label: 'Continue'),
          WorkflowPlanningDecisionOption(id: 'stop', label: 'Stop'),
        ],
      ),
    );
    final id = container.read(chatNotifierProvider).pendingWorkflowDecision!.id;

    await adapter.resolveQuestion(id: id, answer: '1');

    final answer = await result;
    expect(answer, isNotNull);
    expect(answer!.optionId, 'continue');
  });

  test('waits for pending persistence before closing the runtime', () async {
    final testNotifier = notifier as _TerminalTestChatNotifier;
    await adapter.resolveApproval(id: 'missing', approved: false);
    final runtimeSubscription = adapter.events.listen((_) {});
    final runtime = container.read(cavernoExecutionRuntimeProvider);

    final closeFuture = adapter.close();
    await Future<void>.delayed(Duration.zero);

    expect(runtime.isClosed, isFalse);
    testNotifier.completePendingPersistence();
    await closeFuture;
    expect(runtime.isClosed, isTrue);
    await runtimeSubscription.cancel();
  });

  test(
    'closing an unused adapter does not initialize the chat runtime',
    () async {
      var buildCount = 0;
      final lazyContainer = ProviderContainer(
        overrides: [
          chatNotifierProvider.overrideWith(
            () => _CountingChatNotifier(() {
              buildCount += 1;
            }),
          ),
        ],
      );
      final lazyAdapter = CavernoTerminalRuntimeAdapter(
        container: lazyContainer,
        environment: const <String, String>{},
      );

      await lazyAdapter.close();

      expect(buildCount, 0);
      lazyContainer.dispose();
    },
  );
}

final class _TerminalTestChatNotifier extends ChatNotifier {
  final _pendingPersistence = Completer<void>();

  @override
  ChatState build() => ChatState.initial();

  @override
  Future<void> flushPendingPersistence() => _pendingPersistence.future;

  void completePendingPersistence() {
    if (!_pendingPersistence.isCompleted) {
      _pendingPersistence.complete();
    }
  }
}

final class _CountingChatNotifier extends ChatNotifier {
  _CountingChatNotifier(this.onBuild);

  final void Function() onBuild;

  @override
  ChatState build() {
    onBuild();
    return ChatState.initial();
  }
}
