import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fences the eight thread-scoped draft fields against unrouted writes.
///
/// These fields have no home but `ChatState` and the `ThreadScopedChatState`
/// stash, so which thread a write belongs to is carried by the *call*, not by
/// the type. A bare `state = state.copyWith(…)` therefore lands on whichever
/// thread is visible, which is how `generateWorkflowProposal` and
/// `generateTaskProposal` put a plan on the thread the user switched to while
/// leaving the drafting thread spinning.
///
/// Routed writes go through `_routeThreadState` / `_routeApproval`. Direct
/// writes are allowed only where the visible thread *is* the subject: the user
/// dismissing a draft, answering a decision, or stopping the visible turn.
/// Adding a name here asserts that claim about a new call site.
const Set<String> _visibleThreadWriters = {
  'dismissWorkflowProposal',
  'dismissTaskProposal',
  'resolveWorkflowDecision',
  '_cancelStreaming',
};

const Set<String> _threadScopedDraftFields = {
  'pendingWorkflowDecision',
  'isGeneratingWorkflowProposal',
  'workflowProposalDraft',
  'workflowProposalError',
  'isGeneratingTaskProposal',
  'taskProposalDraft',
  'taskProposalError',
  'participantTurnRuntime',
};

const String _notifierPath =
    'lib/features/chat/presentation/providers/chat_notifier.dart';

void main() {
  group('thread-scoped draft writes', () {
    test('every direct state write is a visible-thread action', () {
      final offenders = <String>[];

      for (final path in _libraryFiles(_notifierPath)) {
        final file = File(path);
        final unit = parseString(
          content: file.readAsStringSync(),
          path: path,
        ).unit;
        final visitor = _DirectStateWriteVisitor();
        unit.accept(visitor);

        for (final write in visitor.writes) {
          if (_visibleThreadWriters.contains(write.method)) continue;
          offenders.add(
            '${path.split('/').last}: ${write.method} writes '
            '${write.fields.join(', ')}',
          );
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These writes assign ChatState directly, so they land on the '
            'visible thread rather than the one they belong to. Route them '
            'through _routeThreadState with the conversation the work started '
            'on, or add the method to _visibleThreadWriters if the visible '
            'thread really is the subject.',
      );
    });

    // The allow-list is the whole gate; an entry for a method that no longer
    // writes these fields would silently widen it for a future one.
    test('every allowed writer still writes these fields directly', () {
      final found = <String>{};
      for (final path in _libraryFiles(_notifierPath)) {
        final unit = parseString(
          content: File(path).readAsStringSync(),
          path: path,
        ).unit;
        final visitor = _DirectStateWriteVisitor();
        unit.accept(visitor);
        found.addAll(visitor.writes.map((write) => write.method));
      }

      expect(
        _visibleThreadWriters.difference(found),
        isEmpty,
        reason:
            'A name in _visibleThreadWriters no longer writes a thread-scoped '
            'draft field. Remove it rather than leaving the exemption open.',
      );
    });
  });
}

List<String> _libraryFiles(String libraryPath) {
  final file = File(libraryPath);
  expect(file.existsSync(), isTrue, reason: '$libraryPath does not exist.');
  final directory = file.parent.path;
  final parts = RegExp(
    r"^part\s+'([^']+)';",
    multiLine: true,
  ).allMatches(file.readAsStringSync()).map((match) => match.group(1)!);
  return [libraryPath, for (final part in parts) '$directory/$part'];
}

final class _DirectStateWrite {
  _DirectStateWrite(this.method, this.fields);

  final String method;
  final List<String> fields;
}

/// Finds `state = <something>.copyWith(…)` naming a thread-scoped draft field.
///
/// The receiver is not required to be `state`: the cancellation path assigns
/// through `_cancellationState`, which is a getter returning `state`, and that
/// has the same effect.
final class _DirectStateWriteVisitor extends RecursiveAstVisitor<void> {
  final List<_DirectStateWrite> writes = [];
  final List<String> _methodStack = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _methodStack.add(node.name.lexeme);
    super.visitMethodDeclaration(node);
    _methodStack.removeLast();
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    super.visitAssignmentExpression(node);
    final target = node.leftHandSide;
    if (target is! SimpleIdentifier || target.name != 'state') return;
    _record(node.rightHandSide);
  }

  /// `_setCancellationState(x.copyWith(…))` assigns `state` one call away.
  ///
  /// Without this the cancellation path reads as routed when it is not, which
  /// is exactly the confusion this gate exists to prevent.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.methodName.name != '_setCancellationState') return;
    for (final argument in node.argumentList.arguments) {
      _record(argument);
    }
  }

  void _record(AstNode expression) {
    if (_methodStack.isEmpty) return;
    final fields = <String>[];
    expression.accept(_CopyWithFieldVisitor(fields));
    if (fields.isEmpty) return;
    writes.add(_DirectStateWrite(_methodStack.last, fields));
  }
}

final class _CopyWithFieldVisitor extends RecursiveAstVisitor<void> {
  _CopyWithFieldVisitor(this.fields);

  final List<String> fields;

  @override
  void visitNamedExpression(NamedExpression node) {
    final name = node.name.label.name;
    if (_threadScopedDraftFields.contains(name)) fields.add(name);
    super.visitNamedExpression(node);
  }
}
