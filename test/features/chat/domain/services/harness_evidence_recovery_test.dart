import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding/coding_continuation_recovery_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';
import 'package:caverno/features/chat/domain/services/project_task_review_verdict.dart';
import 'package:caverno/features/chat/domain/services/session_memory_update_tracker.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/recent_read_result_carry.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/tool_loop_recovery_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

ToolResultInfo command(
  String id,
  String command,
  int exit, {
  String directory = '/project',
  int passed = 0,
  int failed = 0,
}) => ToolResultInfo(
  id: id,
  name: 'local_execute_command',
  arguments: {'command': command, 'working_directory': directory},
  result: jsonEncode({
    'command': command,
    'working_directory': directory,
    'exit_code': exit,
    'stdout': '$failed failed, $passed passed in 0.1s',
  }),
  outcome: ToolOutcome(
    exitCode: exit,
    testOutcome: ToolTestOutcome(
      passedCount: passed,
      failedCount: failed,
      skippedCount: 0,
      command: command,
    ),
  ),
);
ToolResultInfo read(
  String id,
  String content, {
  String path = 'source.py',
  int offset = 1,
  bool truncated = false,
}) => ToolResultInfo(
  id: id,
  name: 'read_file',
  arguments: {'path': path, 'offset': offset},
  result: jsonEncode({
    'path': path,
    'content': content,
    'offset': offset,
    'truncated': truncated,
  }),
);
ToolResultInfo failedEdit(
  String content, {
  String path = 'source.py',
  bool changed = false,
}) => ToolResultInfo(
  id: 'edit',
  name: 'edit_file',
  arguments: {'path': path},
  result: jsonEncode({
    'error': 'old_text was not found in the target file',
    'path': path,
    'content_sha256': sha256.convert(utf8.encode(content)).toString(),
  }),
  outcome: changed
      ? ToolOutcome(
          fileMutations: [ToolFileMutation(path: path, changed: true)],
        )
      : null,
);
void main() {
  group('settled recovery failures', () {
    final failed = command('failed', 'python3 -m pytest -q', 1, failed: 5);
    final passed = command(
      'passed',
      '.venv/bin/python -m pytest -q',
      0,
      passed: 61,
    );
    test('both recovery consumers settle the matching scope', () {
      final results = [failed, passed];
      expect(
        const ToolLoopRecoveryPolicy()
            .toolResultsContainFailedCommandValidation(results),
        isFalse,
      );
      expect(
        const CodingContinuationRecoveryPromptBuilder().partialProgressNotice(
          results,
        ),
        isNull,
      );
    });
    for (final mismatch in [
      command(
        'other',
        '.venv/bin/python -m pytest -q test_other.py',
        0,
        passed: 1,
      ),
      command(
        'other',
        '.venv/bin/python -m pytest -q',
        0,
        passed: 61,
        directory: '/other',
      ),
    ]) {
      test('a different scope retains the failure: ${mismatch.arguments}', () {
        expect(
          const ToolLoopRecoveryPolicy()
              .toolResultsContainFailedCommandValidation([failed, mismatch]),
          isTrue,
        );
      });
    }
    test('a later failure remains open', () {
      expect(
        const CodingContinuationRecoveryPromptBuilder().partialProgressNotice([
          passed,
          failed,
        ]),
        isNotNull,
      );
    });
    test('typed failure takes precedence over a zero payload exit', () {
      final result = ToolResultInfo(
        id: 'typed',
        name: 'local_execute_command',
        arguments: const {},
        result: '{"exit_code":0}',
        outcome: const ToolOutcome(exitCode: 2),
      );
      expect(
        const ToolLoopRecoveryPolicy()
            .toolResultsContainFailedCommandValidation([result]),
        isTrue,
      );
    });
    test('zero exit does not hide typed failed tests', () {
      expect(
        const ToolLoopRecoveryPolicy()
            .toolResultsContainFailedCommandValidation([
              command('masked', 'python -m pytest -q', 0, passed: 1, failed: 1),
            ]),
        isTrue,
      );
    });
  });
  group('native review memory', () {
    for (final disposition in ProjectTaskReviewDisposition.values) {
      test('guards ${disposition.name} even without a usable model draft', () {
        final verdict = ProjectTaskReviewVerdict(
          disposition: disposition,
          report: 'Positive summary. ' * 50,
          findings: const ['source.py:1: conversion can overflow.'],
        );
        final restored = ProjectTaskReviewVerdict.fromToolResults([
          verdict.toMemoryToolResult('review'),
        ])!;
        for (final raw in [
          '',
          'invalid',
          '{"summary":"Everything committed.","open_loops":[],"profile":{"preferences":["Concise replies"]},"memories":[{"text":"All work completed","type":"fact"}]}',
        ]) {
          final draft = MemoryExtractionDraftService.parseDraft(
            raw,
            projectReviewStatus: restored,
          )!;
          expect(draft.summary, verdict.memorySummary);
          expect(draft.openLoops, [verdict.memoryNextStep]);
          expect(draft.entries, isEmpty);
        }
        final input = MemoryExtractionDraftService.buildInput(
          [
            Message(
              id: 'review',
              role: MessageRole.assistant,
              content: verdict.response,
              timestamp: DateTime(2026),
            ),
          ],
          UserMemoryProfile.empty(),
          toolResults: [verdict.toMemoryToolResult('review')],
        );
        expect(input, contains('conversion can overflow'));
        expect(input, contains('Recorded project review status:'));
      });
    }
    test('latest native verdict supersedes earlier findings', () {
      final bad = ProjectTaskReviewVerdict(
        disposition: ProjectTaskReviewDisposition.findings,
        report: 'Defect.',
      );
      final clean = ProjectTaskReviewVerdict(
        disposition: ProjectTaskReviewDisposition.clean,
        report: 'Rechecked.',
      );
      expect(
        ProjectTaskReviewVerdict.fromToolResults([
          bad.toMemoryToolResult('a'),
          clean.toMemoryToolResult('b'),
        ])!.disposition,
        ProjectTaskReviewDisposition.clean,
      );
    });
    test('ordinary model text cannot supply native review status', () {
      expect(
        ProjectTaskReviewVerdict.fromToolResults([
          ToolResultInfo(
            id: 'bad',
            name: ProjectTaskReviewVerdict.memoryToolName,
            arguments: const {},
            result: '{"status":"clean","report":"Done"}',
          ),
        ]),
        isNull,
      );
    });
    test(
      'delayed update tokens cannot overwrite a newer turn or other chat',
      () {
        final tracker = SessionMemoryUpdateTracker();
        final first = tracker.begin('a');
        final other = tracker.begin('b');
        final latest = tracker.begin('a');
        tracker.finish('a', first);
        expect(tracker.isCurrent('a', first), isFalse);
        expect(tracker.isCurrent('a', latest), isTrue);
        expect(tracker.isCurrent('b', other), isTrue);
        tracker.finish('a', latest);
        expect(tracker.isCurrent('a', first), isFalse);
      },
    );
  });
  group('bounded source carry', () {
    const carry = RecentReadResultCarry(
      budgetBytes: 3000,
      maxResultBytes: 5000,
    );
    final source = read(
      'source',
      List.generate(150, (i) => 'line $i exact source').join('\n'),
    );
    final recent = read('recent', 'auxiliary\n' * 100, path: 'other.py');
    test('retains an exact source prefix within the UTF-8 budget', () {
      final retained = carry.resolve(
        batchToolResults: [recent],
        executedToolResults: [source, recent],
      );
      final result = retained.firstWhere((r) => r.id == source.id);
      final payload = jsonDecode(result.result) as Map;
      expect(payload['truncated'], isTrue);
      expect(payload['content_truncated'], isTrue);
      expect(
        jsonDecode(
          source.result,
        )['content'].toString().startsWith(payload['content'] as String),
        isTrue,
      );
      expect(payload['read_more_hint']['offset'], 1 + payload['line_count']);
      expect(result.fromEarlierLoop, isTrue);
      expect(
        retained
            .where((r) => r.fromEarlierLoop)
            .fold<int>(0, (sum, r) => sum + utf8.encode(r.result).length),
        lessThanOrEqualTo(3000),
      );
    });
    test('matching unchanged full snapshot survives a failed edit', () {
      final before = read('before', 'exact source');
      final failed = failedEdit('exact source');
      final retained = carry.resolve(
        batchToolResults: [failed],
        executedToolResults: [before, failed],
      );
      expect(retained.map((r) => r.id), ['before', 'edit']);
      expect(retained.first.changesSinceCapture, isEmpty);
    });
    for (final before in [
      read('before', 'old source'),
      read('before', 'exact source', offset: 10),
      read('before', 'exact source', truncated: true),
    ]) {
      test(
        'changed or partial snapshots stay invalidated: ${before.arguments} ${before.result}',
        () {
          final failed = failedEdit('exact source');
          expect(
            carry
                .resolve(
                  batchToolResults: [failed],
                  executedToolResults: [before, failed],
                )
                .map((r) => r.id),
            ['edit'],
          );
        },
      );
    }
    test('unknown commands prevent unchanged snapshot reuse', () {
      final before = read('before', 'exact source');
      final execution = command('unknown', 'python mutate.py', 0);
      final failed = failedEdit('exact source');
      expect(
        carry
            .resolve(
              batchToolResults: [failed],
              executedToolResults: [before, execution, failed],
            )
            .any((r) => r.id == 'before'),
        isFalse,
      );
    });
    test('a reported successful mutation wins over a matching digest', () {
      final before = read('before', 'exact source');
      final failed = failedEdit('exact source', changed: true);
      expect(
        carry
            .resolve(
              batchToolResults: [failed],
              executedToolResults: [before, failed],
            )
            .map((r) => r.id),
        ['edit'],
      );
    });
  });
}
