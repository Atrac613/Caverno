import 'dart:convert';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/material_contract_assumption_guard.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _guard = MaterialContractAssumptionGuard();

ToolCallInfo _call(String name, {Map<String, dynamic> arguments = const {}}) {
  return ToolCallInfo(id: 'call-$name', name: name, arguments: arguments);
}

ConversationContractItemProvenance _assumption({
  String id = 'constraint:runtime',
  ConversationContractItemKind kind = ConversationContractItemKind.constraint,
  String question = 'Which runtime must be supported?',
}) {
  return ConversationContractItemProvenance(
    itemId: id,
    kind: kind,
    assumption: true,
    material: true,
    clarificationQuestion: question,
  );
}

Map<String, dynamic> _payload(McpToolResult result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}

void main() {
  final cases = <ToolCommandEffect, ToolCallInfo>{
    ToolCommandEffect.inspection: _call(
      'local_execute_command',
      arguments: const {'command': 'ls'},
    ),
    ToolCommandEffect.dependencyResolution: _call(
      'local_execute_command',
      arguments: const {'command': 'flutter pub get'},
    ),
    ToolCommandEffect.build: _call(
      'local_execute_command',
      arguments: const {'command': 'flutter build apk'},
    ),
    ToolCommandEffect.verification: _call(
      'local_execute_command',
      arguments: const {'command': 'flutter test'},
    ),
    ToolCommandEffect.formatting: _call(
      'local_execute_command',
      arguments: const {'command': 'dart format .'},
    ),
    ToolCommandEffect.codeGeneration: _call(
      'local_execute_command',
      arguments: const {'command': 'dart run build_runner build'},
    ),
    ToolCommandEffect.workspaceMutation: _call(
      'write_file',
      arguments: const {'path': 'lib/main.dart', 'content': 'void main() {}'},
    ),
    ToolCommandEffect.processLifecycle: _call(
      'process_start',
      arguments: const {'command': 'dart run server.dart'},
    ),
    ToolCommandEffect.deploymentOrRelease: _call(
      'local_execute_command',
      arguments: const {'command': './deploy.sh'},
    ),
    ToolCommandEffect.externalSideEffect: _call(
      'ssh_execute_command',
      arguments: const {'command': 'hostname'},
    ),
    ToolCommandEffect.unknown: _call('unknown_tool'),
  };
  final assumption = _assumption();

  test('returns null outside coding mode and without assumptions', () {
    for (final entry in cases.entries) {
      expect(
        _guard.evaluate(
          entry.value,
          workspaceMode: WorkspaceMode.chat,
          blockingAssumptions: [assumption],
        ),
        isNull,
        reason: 'chat:${entry.key.name}',
      );
      expect(
        _guard.evaluate(
          entry.value,
          workspaceMode: WorkspaceMode.routines,
          blockingAssumptions: [assumption],
        ),
        isNull,
        reason: 'routines:${entry.key.name}',
      );
      expect(
        _guard.evaluate(
          entry.value,
          workspaceMode: WorkspaceMode.coding,
          blockingAssumptions: const [],
        ),
        isNull,
        reason: 'empty:${entry.key.name}',
      );
    }
  });

  test('inactive gates return before classifying malformed arguments', () {
    final malformedCommand = _call(
      'local_execute_command',
      arguments: const {'command': 7},
    );

    expect(
      _guard.evaluate(
        malformedCommand,
        workspaceMode: WorkspaceMode.chat,
        blockingAssumptions: [assumption],
      ),
      isNull,
    );
    expect(
      _guard.evaluate(
        malformedCommand,
        workspaceMode: WorkspaceMode.coding,
        blockingAssumptions: const [],
      ),
      isNull,
    );
  });

  test('classifies every command effect and blocks only mutations', () {
    for (final entry in cases.entries) {
      final isMutation = switch (entry.key) {
        ToolCommandEffect.inspection ||
        ToolCommandEffect.verification ||
        ToolCommandEffect.unknown => false,
        _ => true,
      };

      expect(
        _guard.isContractMutation(entry.value),
        isMutation,
        reason: entry.key.name,
      );
      final result = _guard.evaluate(
        entry.value,
        workspaceMode: WorkspaceMode.coding,
        blockingAssumptions: [assumption],
      );
      expect(result, isMutation ? isNotNull : isNull, reason: entry.key.name);
    }
  });

  test('returns the exact blocked payload and failure flags', () {
    final toolCall = cases[ToolCommandEffect.workspaceMutation]!;
    final result = _guard.evaluate(
      toolCall,
      workspaceMode: WorkspaceMode.coding,
      blockingAssumptions: [assumption],
    )!;

    expect(result.toolName, toolCall.name);
    expect(result.isSuccess, isFalse);
    expect(
      result.errorMessage,
      'Confirm the material contract assumption first.',
    );
    expect(_payload(result), {
      'ok': false,
      'code': MaterialContractAssumptionGuard.blockedCode,
      'error':
          'State mutation is blocked until the user confirms a material contract assumption.',
      'clarification_question': 'Which runtime must be supported?',
      'required_action':
          'Ask the user this one focused clarification question and wait for confirmation before mutating state.',
    });
  });

  test('normalizes a custom clarification question', () {
    final result = _guard.evaluate(
      cases[ToolCommandEffect.build]!,
      workspaceMode: WorkspaceMode.coding,
      blockingAssumptions: [
        _assumption(question: '  Which deployment target is required?  '),
      ],
    )!;

    expect(
      _payload(result)['clarification_question'],
      'Which deployment target is required?',
    );
  });

  test('builds the fallback question from the assumption kind', () {
    final result = _guard.evaluate(
      cases[ToolCommandEffect.externalSideEffect]!,
      workspaceMode: WorkspaceMode.coding,
      blockingAssumptions: [
        _assumption(
          kind: ConversationContractItemKind.acceptanceCriterion,
          question: '   ',
        ),
      ],
    )!;

    expect(
      _payload(result)['clarification_question'],
      'Please confirm the material acceptanceCriterion assumption.',
    );
  });

  test('preserves first-assumption order', () {
    final result = _guard.evaluate(
      cases[ToolCommandEffect.formatting]!,
      workspaceMode: WorkspaceMode.coding,
      blockingAssumptions: [
        _assumption(
          id: 'open-question:first',
          kind: ConversationContractItemKind.openQuestion,
          question: 'Confirm the first assumption?',
        ),
        _assumption(
          id: 'constraint:second',
          question: 'Confirm the second assumption?',
        ),
      ],
    )!;

    expect(
      _payload(result)['clarification_question'],
      'Confirm the first assumption?',
    );
  });

  test(
    'uses the owner assumption snapshot instead of visible workflow data',
    () {
      final ownerAssumptions = [
        _assumption(
          id: 'owner:constraint',
          question: 'Confirm the owner assumption?',
        ),
      ];
      final visibleAssumptions = [
        _assumption(
          id: 'visible:constraint',
          question: 'Confirm the visible assumption?',
        ),
      ];

      final result = _guard.evaluate(
        cases[ToolCommandEffect.codeGeneration]!,
        workspaceMode: WorkspaceMode.coding,
        blockingAssumptions: List.unmodifiable(ownerAssumptions),
      )!;
      final visibleResult = _guard.evaluate(
        cases[ToolCommandEffect.codeGeneration]!,
        workspaceMode: WorkspaceMode.coding,
        blockingAssumptions: List.unmodifiable(visibleAssumptions),
      )!;
      ownerAssumptions[0] = _assumption(
        id: 'owner:mutated',
        question: 'A later owner assumption?',
      );
      visibleAssumptions[0] = _assumption(
        id: 'visible:mutated',
        question: 'A later visible assumption?',
      );

      expect(
        _payload(result)['clarification_question'],
        'Confirm the owner assumption?',
      );
      expect(result.result, isNot(contains('visible')));
      expect(
        _payload(visibleResult)['clarification_question'],
        'Confirm the visible assumption?',
      );
      expect(visibleResult.result, isNot(contains('owner')));
    },
  );
}
