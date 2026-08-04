import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _executionRuntimePath =
    'lib/features/chat/presentation/providers/'
    'chat_notifier_execution_runtime.dart';
const _notifierPath =
    'lib/features/chat/presentation/providers/chat_notifier.dart';

const Map<String, String> _ownerReleaseContract = {
  'pythonScriptRuntime':
      '()=>unawaited(_pythonScriptRuntime.retireOwner(owner))',
  'fileMutationRuntime': '()=>_fileMutationRuntime.retireOwner(owner)',
  'backgroundProcesses':
      '()=>unawaited(_mcpToolService?.clearBackgroundProcessOwner(owner)??'
      'Future<void>.sync(()=>_backgroundProcessMonitorService.clearOwner(owner)))',
  'sshOwner': '()=>unawaited(_clearSshOwner(owner))',
  'conversationTaintState':
      '()=>_conversationTaintState.clearOwner(owner:owner)',
  'pendingToolApprovals': '()=>_cancelPendingToolApprovalsForOwner(owner)',
  'toolApprovalCache': '()=>_toolApprovalCache.clear(owner)',
  'hiddenAssistantEvidence': '()=>_hiddenAssistantEvidence.publish(owner)',
  'contentToolTurns': '()=>_contentToolTurns.dispose(owner)',
  'turnEnd': '()=>_turnEnd.dispose(owner)',
  'goalCompletionEvidence': '()=>_goalCompletionEvidence.dispose(owner)',
};

const List<String> _terminalizationContract = [
  '_runtimeTurns.remove(generation)',
  '_turnOwnerForGeneration(generation)',
  'ChatTurnOwner(conversationId:conversationId,interactionGeneration:generation)',
  '_runtimeEvents.clearAssistantContent(generation)',
  'publishTurnEvidence(_turnToolResults,generation,handle.conversationId)',
  '_releaseTurnScope(owner)',
  'terminalize(handle)',
  '_clearActiveResponseForGeneration(generation)',
];

const List<String> _generationCleanupContract = [
  '_activeResponseRegistry.ownerForGeneration(generation)',
  '_participantTurnControls.contains(owner)',
  '_participantTurnControls.isPaused(owner)',
  '_participantTurnControls.dispose(owner)',
  '_askUserQuestionRuntime.retireOwner(owner)',
  '_activeResponseRegistry.clearGeneration(generation)',
  '_lastStreamedToolResultFinalAnswersByGeneration.remove(generation)',
  '_pendingActionLengthRecoveryGenerations.remove(generation)',
  '_explicitTerminalSuccessSummariesByGeneration.remove(generation)',
  '_releaseApprovalSnapshots.remove(generation)',
  '_responseMetadata.dispose(owner)',
  '_contextSurgeryObservations.removeOwner(owner)',
  '_modelEditTelemetry?.retireOwner(owner)',
  '_turnFinalizationRecoveryGenerations.remove(generation)',
  '_modelSwitchHandoffs.discardPromptCompaction(owner)',
  '_syncBusyConversationIds()',
];

void main() {
  group('ChatNotifier turn teardown contract', () {
    test('registers the exact owner-scoped releases and callbacks', () {
      final method = _method(_executionRuntimePath, '_registerTurnReleases');
      final visitor = _ReleaseRegistrationVisitor();
      method.body.accept(visitor);

      expect(
        visitor.callbacks,
        orderedEquals(
          _ownerReleaseContract.entries.map(
            (entry) => '${entry.key}=${entry.value}',
          ),
        ),
        reason:
            'Every owner-scoped resource must keep an explicit release name and '
            'callback. Update this contract only after classifying its lifetime.',
      );
    });

    test('keeps the terminalization chain ordered and complete', () {
      final method = _method(_executionRuntimePath, '_terminalizeRuntimeTurn');

      expect(
        _invocations(method),
        orderedEquals(_terminalizationContract),
        reason:
            'Terminalization ordering is load-bearing: publish retained '
            'evidence, release owner state, settle the runtime, then clear '
            'generation state.',
      );
    });

    test('keeps every generation-scoped cleanup operation', () {
      final method = _method(
        _notifierPath,
        '_clearActiveResponseForGeneration',
      );

      expect(
        _invocations(method),
        orderedEquals(_generationCleanupContract),
        reason:
            'Removing or replacing one cleanup must fail this gate instead of '
            'silently leaking state into a later turn.',
      );
    });
  });
}

MethodDeclaration _method(String path, String name) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path does not exist.');
  final result = parseString(content: file.readAsStringSync(), path: path);
  final visitor = _MethodVisitor(name);
  result.unit.accept(visitor);
  expect(
    visitor.matches,
    hasLength(1),
    reason: 'Expected exactly one $name declaration in $path.',
  );
  return visitor.matches.single;
}

List<String> _invocations(MethodDeclaration method) {
  final visitor = _InvocationVisitor();
  method.body.accept(visitor);
  return visitor.invocations;
}

String _normalized(AstNode node) =>
    node.toSource().replaceAll(RegExp(r'\s+'), '');

final class _MethodVisitor extends RecursiveAstVisitor<void> {
  _MethodVisitor(this.name);

  final String name;
  final List<MethodDeclaration> matches = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) matches.add(node);
    super.visitMethodDeclaration(node);
  }
}

final class _ReleaseRegistrationVisitor extends RecursiveAstVisitor<void> {
  final List<String> callbacks = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'register' &&
        node.argumentList.arguments.length == 2) {
      final nameNode = node.argumentList.arguments.first;
      if (nameNode is SimpleStringLiteral) {
        callbacks.add(
          '${nameNode.value}=${_normalized(node.argumentList.arguments.last)}',
        );
      }
    }
    super.visitMethodInvocation(node);
  }
}

final class _InvocationVisitor extends RecursiveAstVisitor<void> {
  final List<String> invocations = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    invocations.add(_normalized(node));
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    invocations.add(_normalized(node));
    super.visitFunctionExpressionInvocation(node);
  }
}
