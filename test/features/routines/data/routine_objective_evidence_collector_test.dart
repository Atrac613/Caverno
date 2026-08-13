import 'dart:io';

import 'package:caverno/features/routines/data/routine_objective_evidence_collector.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('captures verified content-hashed workspace evidence', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'routine-evidence-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final file = File('${workspace.path}/lib/result.txt');
    await file.parent.create(recursive: true);
    await file.writeAsString('green\n');
    final commands = <String>[];
    final collector = RoutineObjectiveEvidenceCollector(
      commandRunner: (executable, arguments, workingDirectory) async {
        commands.add('$executable ${arguments.join(' ')}@$workingDirectory');
        return ProcessResult(1, 0, 'passed', '');
      },
    );

    final evidence = await collector.collect(
      routine: _routine(workspace.path),
      toolCalls: [
        RoutineRunToolCall(
          id: 'write-1',
          name: 'write_file',
          arguments: '{"path":"${file.path}"}',
        ),
      ],
      implementationOutput: 'Implemented the result.',
    );

    expect(commands, ['dart test@${workspace.path}']);
    expect(evidence!.verification.passed, isTrue);
    expect(evidence.changedFileEvidenceTruncated, isFalse);
    expect(evidence.changedFiles.single.path, 'lib/result.txt');
    expect(evidence.changedFiles.single.content, 'green\n');
    expect(evidence.changedFiles.single.byteSize, 6);
    expect(evidence.changedFiles.single.contentHash, hasLength(64));
    expect(evidence.implementationEvidence.first, 'Implemented the result.');
  });

  test('fails closed for control operators and escaped paths', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'routine-evidence-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    var commandCount = 0;
    final collector = RoutineObjectiveEvidenceCollector(
      commandRunner: (_, _, _) async {
        commandCount += 1;
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(
      await collector.collect(
        routine: _routine(workspace.path, command: 'dart test && touch marker'),
        toolCalls: const [],
        implementationOutput: 'done',
      ),
      isNull,
    );
    final escaped = await collector.collect(
      routine: _routine(workspace.path),
      toolCalls: const [
        RoutineRunToolCall(
          id: 'write-1',
          name: 'write_file',
          arguments: '{"path":"../secret"}',
        ),
      ],
      implementationOutput: 'done',
    );
    expect(commandCount, 1);
    expect(escaped!.changedFiles, isEmpty);
    expect(escaped.changedFileEvidenceTruncated, isTrue);
  });

  test('does nothing without an explicit complete contract', () async {
    final collector = RoutineObjectiveEvidenceCollector(
      commandRunner: (_, _, _) => throw StateError('must not run'),
    );
    final routine = _routine('/tmp').copyWith(objectiveEvidenceContract: null);

    expect(
      await collector.collect(
        routine: routine,
        toolCalls: const [],
        implementationOutput: 'done',
      ),
      isNull,
    );
  });
}

Routine _routine(String workspace, {String command = 'dart test'}) {
  final now = DateTime.utc(2026, 8, 13);
  return Routine(
    id: 'routine-1',
    name: 'Evidence Routine',
    prompt: 'Implement the result.',
    createdAt: now,
    updatedAt: now,
    toolsEnabled: true,
    allowWorkspaceWrites: true,
    workspaceDirectory: workspace,
    objectiveEvidenceContract: RoutineObjectiveEvidenceContract(
      objective: 'Implement the result.',
      acceptanceCriteria: const ['The result is green.'],
      verificationCommand: command,
    ),
  );
}
