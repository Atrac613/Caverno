import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

import '../../integration_test/test_support/plan_mode_heartbeat.dart';
import '../../integration_test/test_support/plan_mode_live_harness_execution.dart';

void main() {
  test('reads the latest assistant message after a previous id', () {
    final conversation = _conversation(<Message>[
      _message(id: 'user-1', role: MessageRole.user, content: 'Build it'),
      _message(id: 'assistant-1', content: 'Old answer'),
      _message(id: 'assistant-2', content: '  New answer  '),
    ]);

    expect(
      latestPlanModeHarnessAssistantMessageId(conversation),
      'assistant-2',
    );
    expect(
      latestPlanModeHarnessAssistantResponseAfter(conversation, 'assistant-1'),
      'New answer',
    );
    expect(
      latestPlanModeHarnessAssistantResponseAfter(conversation, 'assistant-2'),
      '',
    );
    expect(latestPlanModeHarnessAssistantMessageId(null), isNull);
  });

  test('builds fallback assistant response from hidden text or tool names', () {
    expect(
      buildPlanModeHarnessFallbackAssistantResponse(
        toolResults: const <ToolResultInfo>[],
        hiddenAssistantResponse: '  Hidden completion  ',
      ),
      'Hidden completion',
    );
    expect(
      buildPlanModeHarnessFallbackAssistantResponse(
        toolResults: <ToolResultInfo>[
          _toolResult(name: 'write_file'),
          _toolResult(name: ' local_execute_command '),
          _toolResult(name: 'write_file'),
        ],
        hiddenAssistantResponse: null,
      ),
      'The saved task completed with tool execution evidence from: write_file, local_execute_command.',
    );
    expect(
      buildPlanModeHarnessFallbackAssistantResponse(
        toolResults: <ToolResultInfo>[_toolResult(name: ' ')],
        hiddenAssistantResponse: null,
      ),
      'The saved task completed with tool execution evidence.',
    );
    expect(
      buildPlanModeHarnessFallbackAssistantResponse(
        toolResults: const <ToolResultInfo>[],
        hiddenAssistantResponse: null,
      ),
      '',
    );
  });

  test('resolves cleanup timeout for fake and live runs', () {
    final shortBudgets = _budgets(
      executionTimeout: const Duration(seconds: 20),
    );
    final longBudgets = _budgets(
      executionTimeout: const Duration(seconds: 120),
    );

    expect(
      resolvePlanModeHarnessCleanupTimeout(
        usesLiveLlm: false,
        budgets: shortBudgets,
      ),
      const Duration(seconds: 30),
    );
    expect(
      resolvePlanModeHarnessCleanupTimeout(
        usesLiveLlm: true,
        budgets: shortBudgets,
      ),
      const Duration(seconds: 90),
    );
    expect(
      resolvePlanModeHarnessCleanupTimeout(
        usesLiveLlm: true,
        budgets: longBudgets,
      ),
      const Duration(seconds: 120),
    );
  });

  test('cleanup timeout is swallowed for background harness futures', () async {
    final completer = Completer<void>();
    final handle = PlanModeHarnessExecutionHandle(completer.future);

    await awaitPlanModeHarnessExecutionCleanup(
      handle,
      scenarioName: 'timeout_case',
      timeout: const Duration(milliseconds: 1),
    );

    expect(completer.isCompleted, isFalse);
    expect(handle.cleanupCancellationRequested, isTrue);
  });

  test('recognizes provider container disposal after cleanup cancellation', () {
    expect(
      isPlanModeHarnessProviderContainerDisposedError(
        StateError(
          'Tried to read a provider from a ProviderContainer that was already disposed',
        ),
      ),
      isTrue,
    );
    expect(
      isPlanModeHarnessProviderContainerDisposedError(
        StateError('Some other harness failure'),
      ),
      isFalse,
    );
  });

  test('detects missing target files before harness auto-continues', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_targets_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    File('${tempDir.path}/README.md').writeAsStringSync('# Ready\n');

    const task = ConversationWorkflowTask(
      id: 'task-implementation',
      title: 'Implement ping_cli.py',
      targetFiles: <String>['README.md', 'ping_cli.py'],
      validationCommand: 'python3 ping_cli.py --help',
    );

    expect(missingPlanModeHarnessTargetFiles(tempDir, task), <String>[
      'ping_cli.py',
    ]);
  });
}

Conversation _conversation(List<Message> messages) {
  final now = DateTime(2026, 5, 12, 12);
  return Conversation(
    id: 'conversation-1',
    title: 'Harness',
    messages: messages,
    createdAt: now,
    updatedAt: now,
  );
}

Message _message({
  required String id,
  MessageRole role = MessageRole.assistant,
  required String content,
}) {
  return Message(
    id: id,
    role: role,
    content: content,
    timestamp: DateTime(2026, 5, 12, 12),
  );
}

ToolResultInfo _toolResult({required String name}) {
  return ToolResultInfo(
    id: name,
    name: name,
    arguments: const <String, dynamic>{},
    result: 'ok',
  );
}

PlanModeTimeoutBudgets _budgets({required Duration executionTimeout}) {
  return PlanModeTimeoutBudgets(
    planningTimeout: const Duration(seconds: 5),
    executionTimeout: executionTimeout,
    executionStallTimeout: const Duration(seconds: 45),
    overallTimeout: const Duration(seconds: 120),
  );
}
