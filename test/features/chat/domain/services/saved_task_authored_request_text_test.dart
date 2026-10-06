import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/final_answer_claim_detector.dart';
import 'package:caverno/features/chat/domain/services/saved_task_authored_request_text.dart';
import 'package:caverno/features/chat/domain/services/short_prompt_contract_builder.dart';
import 'package:test/test.dart';

/// The executor template as `ConversationPlanExecutionCoordinator` writes it,
/// taken verbatim from the sessions each case names.
String _executorPrompt({
  required String taskId,
  required String title,
  required String validationCommand,
  required String notes,
  String targetFiles = '',
}) {
  return <String>[
    'このコーディングスレッドに保存されたタスク「$title」を使って進めてください。',
    'Saved task ID: $taskId',
    if (targetFiles.isNotEmpty) '対象ファイル: $targetFiles',
    '確認コマンド: $validationCommand',
    'メモ: $notes',
    'Work only on this saved task. Do not implement future saved tasks.',
    'After the saved validation step succeeds, report the result and end this '
        'turn without calling another tool or starting another saved task.',
    'The workflow executor will start the next pending saved task in a '
        'separate turn.',
    'Do not run the saved validation command until the current task target '
        'files exist and you have created or updated the relevant target file '
        'for this task.',
    '保存済み workflow を守りながらこの task を前に進め、実装前に次の具体的な変更を説明してください。',
  ].join('\n');
}

ToolResultInfo _gitResult() => ToolResultInfo(
  id: 'git-1',
  name: 'git_execute_command',
  arguments: const {'command': 'tag --list --sort=-v:refname'},
  result: jsonEncode({
    'command': 'git tag --list --sort=-v:refname',
    'exit_code': 0,
    'stdout': '1.3.39+52\n1.3.38+51\n',
  }),
);

void main() {
  const resolver = SavedTaskAuthoredRequestText();
  const detector = FinalAnswerClaimDetector();

  group('executor template is not a file-side-effect request', () {
    test('the template alone arms the gate on every executor-driven turn', () {
      // The disarmed safety catch this fix is about: nine `save` / 保存
      // matches, none of them written by the user.
      expect(
        detector.looksLikeFileSideEffectRequest(
          _executorPrompt(
            taskId: '07b7f2c9-8892-439d-abd8-1a405a8cf04d',
            title: '現在のバージョン番号・ビルドナンバーと直近リリースタグを確認し、次に設定する値を決定する',
            validationCommand: 'git tag --list --sort=-v:refname | head -n 20',
            notes: 'pubspec.yamlのversionフィールドと、gitのタグ履歴から直近リリースを特定する。',
          ),
        ),
        isTrue,
      );
    });

    test('an inspection-only task disarms it (session 16e9d5a3)', () {
      const task = ConversationWorkflowTask(
        id: '07b7f2c9-8892-439d-abd8-1a405a8cf04d',
        title: '現在のバージョン番号・ビルドナンバーと直近リリースタグを確認し、次に設定する値を決定する',
        validationCommand: 'git tag --list --sort=-v:refname | head -n 20',
        notes: 'pubspec.yamlのversionフィールドと、gitのタグ履歴から直近リリースを特定する。',
      );
      expect(
        detector.looksLikeFileSideEffectRequest(
          resolver.resolve(
            latestUserContent: _executorPrompt(
              taskId: task.id,
              title: task.title,
              validationCommand: task.validationCommand,
              notes: task.notes,
            ),
            savedTask: task,
          ),
        ),
        isFalse,
      );
    });

    test('a task that asks for a file still arms it (session 727c85d3)', () {
      const task = ConversationWorkflowTask(
        id: '4e1a5f54-66ca-46ed-8e9f-bf30ccf42b7b',
        title: 'Sample.jsonl に代表データ（3行以上、共通フィールドを持つ JSON 行）を作成する',
        targetFiles: ['sample.jsonl'],
        validationCommand: 'test -f sample.jsonl',
        notes: 'サンプルは可視ファイルとして sample.jsonl に置く。',
      );
      expect(
        detector.looksLikeFileSideEffectRequest(
          resolver.resolve(
            latestUserContent: _executorPrompt(
              taskId: task.id,
              title: task.title,
              validationCommand: task.validationCommand,
              notes: task.notes,
              targetFiles: 'sample.jsonl',
            ),
            savedTask: task,
          ),
        ),
        isTrue,
      );
    });
  });

  group('resolve', () {
    test('a typed user message is returned unchanged', () {
      expect(
        resolver.resolve(
          latestUserContent: 'レポートを report.md に保存して',
          savedTask: null,
        ),
        'レポートを report.md に保存して',
      );
    });

    test('a synthetic request wrapper falls back (session 132829af)', () {
      // ShortPromptContractBuilder's placeholder carries none of the request;
      // reading it as authored text would disarm the guard on a turn whose
      // user text was never examined.
      expect(
        resolver.resolve(
          latestUserContent: 'pubspec.yaml のバージョンを更新して保存して',
          savedTask: const ConversationWorkflowTask(
            id: 'request-ce52baeb',
            title: ShortPromptContractBuilder.syntheticRequestTaskTitle,
          ),
        ),
        'pubspec.yaml のバージョンを更新して保存して',
      );
    });

    test('a task with no authored text falls back to the user content', () {
      expect(
        resolver.resolve(
          latestUserContent: 'save the notes',
          savedTask: const ConversationWorkflowTask(id: 'empty', title: '   '),
        ),
        'save the notes',
      );
    });
  });

  test('no fabricated write_file for an inspection-only completion report', () {
    // Session 16e9d5a3: the report the harness convicted, and the executed
    // result that already satisfied the task's validation step.
    const completionReport =
        'タスク「現在のバージョン番号・ビルドナンバーと直近リリースタグを確認し、次に設定する値を決定する」が完了しました。\n'
        '\n'
        '## 完了根拠\n'
        '\n'
        '**確認コマンド実行結果**（`git tag --list --sort=-v:refname | head -n 20`）:\n'
        '- 直近リリースタグ: `1.3.39+52`\n'
        '- 系列: `1.3.38+51` → `1.3.37+50` → …（v プレフィックスなしが標準形式）\n'
        '- 例外: `v1.3.14+26`（古い形式）、`rag2-investigation-pre-squash`（リリースタグではない）\n'
        '\n'
        '**pubspec.yaml の確認**（`pubspec.yaml:19`）:\n'
        '- 現在: `version: 1.3.39+52`（直近タグと一致）\n'
        '\n'
        '## 決定した値\n'
        '\n'
        '| 項目 | 値 |\n'
        '|------|-----|\n'
        '| バージョン番号 | `1.3.40`（直近 `1.3.39` の patch +1） |\n'
        '| ビルドナンバー | `53`（直近 `52` +1） |\n'
        '| **次バージョン** | **`1.3.40+53`** |\n'
        '| タグ名 | `1.3.40+53`（v プレフィックスなし） |\n'
        '\n'
        'タグ形式は直近のリリース系列（`1.3.39+52` 等）およびユーザーの好み（v プレフィックスなし）に従います。\n'
        '\n'
        'このタスクは値の確認・決定のみでファイル変更を伴わないため、ここで turn を終了します。次の pending task（pubspec.yaml の更新）は workflow executor が別の turn で開始します。\n';
    const task = ConversationWorkflowTask(
      id: '07b7f2c9-8892-439d-abd8-1a405a8cf04d',
      title: '現在のバージョン番号・ビルドナンバーと直近リリースタグを確認し、次に設定する値を決定する',
      validationCommand: 'git tag --list --sort=-v:refname | head -n 20',
      notes: 'pubspec.yamlのversionフィールドと、gitのタグ履歴から直近リリースを特定する。',
    );
    final executorPrompt = _executorPrompt(
      taskId: task.id,
      title: task.title,
      validationCommand: task.validationCommand,
      notes: task.notes,
    );

    expect(
      detector.buildUnexecutedFileSideEffectToolResult(
        candidateResponse: completionReport,
        toolResults: [_gitResult()],
        latestUserContent: executorPrompt,
      ),
      isNotNull,
      reason: 'the unresolved template is what convicted session 16e9d5a3',
    );
    expect(
      detector.buildUnexecutedFileSideEffectToolResult(
        candidateResponse: completionReport,
        toolResults: [_gitResult()],
        latestUserContent: resolver.resolve(
          latestUserContent: executorPrompt,
          savedTask: task,
        ),
      ),
      isNull,
    );
  });
}
