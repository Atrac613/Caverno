import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_execution_evidence_recorder.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('captures final content for a typed changed mutation', () async {
    final worktree = await Directory.systemTemp.createTemp(
      'caverno_worktree_evidence_',
    );
    addTearDown(() => worktree.delete(recursive: true));
    final file = File('${worktree.path}/lib/example.dart');
    await file.parent.create(recursive: true);
    await file.writeAsString('updated');
    final recorder = WorktreeAgentExecutionEvidenceRecorder(
      worktreePath: worktree.path,
    );

    recorder.record(_mutationResult(path: file.path, changed: true));
    final snapshot = await recorder.capture();

    expect(snapshot.truncated, isFalse);
    expect(snapshot.changedFiles, hasLength(1));
    final evidence = snapshot.changedFiles.single;
    expect(evidence.path, 'lib/example.dart');
    expect(evidence.content, 'updated');
    expect(evidence.byteSize, 7);
    expect(
      evidence.contentHash,
      sha256.convert(utf8.encode('updated')).toString(),
    );
    expect(evidence.deleted, isFalse);
    expect(evidence.truncated, isFalse);
  });

  test('ignores failed, no-op, and outside-worktree mutations', () async {
    final worktree = await Directory.systemTemp.createTemp(
      'caverno_worktree_evidence_',
    );
    addTearDown(() => worktree.delete(recursive: true));
    final recorder = WorktreeAgentExecutionEvidenceRecorder(
      worktreePath: worktree.path,
    );

    recorder
      ..record(_mutationResult(path: 'unchanged.txt', changed: false))
      ..record(
        _mutationResult(
          path: '${worktree.parent.path}/outside.txt',
          changed: true,
        ),
      )
      ..record(
        _mutationResult(path: 'failed.txt', changed: true, success: false),
      );

    expect((await recorder.capture()).changedFiles, isEmpty);
  });

  test(
    'records deletions and bounded content without weakening hashes',
    () async {
      final worktree = await Directory.systemTemp.createTemp(
        'caverno_worktree_evidence_',
      );
      addTearDown(() => worktree.delete(recursive: true));
      final large = File('${worktree.path}/a-large.txt');
      await large.writeAsString('abcdefgh');
      final recorder = WorktreeAgentExecutionEvidenceRecorder(
        worktreePath: worktree.path,
        maxFiles: 2,
        maxContentBytes: 4,
      );

      recorder
        ..record(_mutationResult(path: large.path, changed: true))
        ..record(_mutationResult(path: 'b-deleted.txt', changed: true))
        ..record(_mutationResult(path: 'c-omitted.txt', changed: true));
      final snapshot = await recorder.capture();

      expect(snapshot.truncated, isTrue);
      expect(snapshot.changedFiles, hasLength(2));
      final largeEvidence = snapshot.changedFiles.first;
      expect(largeEvidence.content, 'abcd');
      expect(largeEvidence.byteSize, 8);
      expect(largeEvidence.truncated, isTrue);
      expect(
        largeEvidence.contentHash,
        sha256.convert(utf8.encode('abcdefgh')).toString(),
      );
      final deletedEvidence = snapshot.changedFiles.last;
      expect(deletedEvidence.path, 'b-deleted.txt');
      expect(deletedEvidence.deleted, isTrue);
      expect(deletedEvidence.contentHash, isNull);
    },
  );

  test('caps aggregate persisted content across changed files', () async {
    final worktree = await Directory.systemTemp.createTemp(
      'caverno_worktree_evidence_',
    );
    addTearDown(() => worktree.delete(recursive: true));
    final first = File('${worktree.path}/a.txt');
    final second = File('${worktree.path}/b.txt');
    await first.writeAsString('abcd');
    await second.writeAsString('efgh');
    final recorder = WorktreeAgentExecutionEvidenceRecorder(
      worktreePath: worktree.path,
      maxContentBytes: 4,
      maxTotalContentBytes: 5,
    );

    recorder
      ..record(_mutationResult(path: first.path, changed: true))
      ..record(_mutationResult(path: second.path, changed: true));
    final snapshot = await recorder.capture();

    expect(snapshot.truncated, isTrue);
    expect(snapshot.changedFiles.first.content, 'abcd');
    expect(snapshot.changedFiles.first.truncated, isFalse);
    expect(snapshot.changedFiles.last.content, 'e');
    expect(snapshot.changedFiles.last.truncated, isTrue);
  });
}

McpToolResult _mutationResult({
  required String path,
  required bool changed,
  bool success = true,
}) {
  return McpToolResult(
    toolName: 'write_file',
    result: success ? 'ok' : 'failed',
    isSuccess: success,
    outcome: ToolOutcome(
      fileMutations: [ToolFileMutation(path: path, changed: changed)],
    ),
  );
}
