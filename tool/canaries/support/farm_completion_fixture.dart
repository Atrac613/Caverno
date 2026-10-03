import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import 'farm_step_live_fixture.dart';

const farmCompletionVerify = '.venv/bin/python tool/verify.py';
const farmCompletionGoodCode =
    'def clamp(value):\n    return max(0, min(value, 10))\n';
const farmCompletionBadCode = 'def clamp(value):\n    return min(value, 10)\n';
const farmCompletionRoadmap =
    '# Fixture roadmap\n\n- [ ] FARM-CANARY: Clamp numbers to [0, 10].\n';

enum FarmCompletionScenario { normal, reviewRepair, failedVerification }

/// Disposable repository with no remotes, hooks, or developer Git identity.
final class FarmCompletionFixture {
  FarmCompletionFixture(this.root, this.scenario);
  final Directory root;
  final FarmCompletionScenario scenario;
  final initialFiles = <String, String>{};
  late String initialHead;
  late CodingProject project;

  Future<String> git(List<String> args) async {
    final result = await Process.run(
      '/usr/bin/git',
      args,
      workingDirectory: root.path,
      environment: {
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': '/dev/null',
      },
    );
    if (result.exitCode != 0) {
      throw StateError('Fixture git failed: ${result.stderr}');
    }
    return (result.stdout as String).trimRight();
  }

  Future<void> initialize() async {
    final python = [
      '/opt/homebrew/bin/python3',
      '/usr/local/bin/python3',
      '/Library/Developer/CommandLineTools/usr/bin/python3',
    ].firstWhere((path) => File(path).existsSync());
    Directory('${root.path}/.venv/bin').createSync(recursive: true);
    Link(
      '${root.path}/.venv/bin/python',
    ).createSync(File(python).resolveSymbolicLinksSync());
    initialFiles.addAll({
      '.gitignore': '.venv/\n__pycache__/\n',
      'fixture.py': 'def clamp(value):\n    return value\n',
      'roadmap.md': farmCompletionRoadmap,
      'unrelated.txt': 'Existing unrelated content.\n',
      'tool/verify.py':
          '''
import pathlib
import sys
sys.dont_write_bytecode = True
root = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root))
from fixture import clamp
assert clamp(20) == 10
assert clamp(5) == 5
${scenario == FarmCompletionScenario.reviewRepair ? '' : 'assert clamp(-2) == 0'}
${scenario == FarmCompletionScenario.failedVerification ? "assert (root / 'required.flag').exists(), 'External prerequisite required.flag is missing'" : ''}
print('FARM_COMPLETION_VERIFIED: checks passed')
''',
      'tool/oracle.py': '''
import pathlib
import sys
sys.dont_write_bytecode = True
root = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root))
from fixture import clamp
for value in [-100, -2, 0, 5, 10, 20, 100]:
    assert clamp(value) == max(0, min(value, 10)), value
print('FARM_COMPLETION_ORACLE: 7 checks passed')
''',
    });
    for (final entry in initialFiles.entries) {
      final file = File('${root.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    await git(['init', '--initial-branch=main']);
    for (final entry in {
      'user.name': 'Farm Canary',
      'user.email': 'farm-canary@example.invalid',
      'commit.gpgsign': 'false',
      'core.hooksPath': '/dev/null',
    }.entries) {
      await git(['config', '--local', entry.key, entry.value]);
    }
    await git(['add', '--', ...initialFiles.keys]);
    await git(['commit', '-m', 'test: initialize synthetic farm fixture']);
    initialHead = await git(['rev-parse', 'HEAD']);
    File(
      '${root.path}/unrelated.txt',
    ).writeAsStringSync('Unrelated pre-existing change.\n');
    final now = DateTime.now();
    project = CodingProject(
      id: 'farm-completion-${scenario.name}',
      name: 'Synthetic Farm completion',
      rootPath: root.path,
      createdAt: now,
      updatedAt: now,
    );
  }

  String get objective =>
      '''Implement FARM-CANARY in roadmap.md: fixture.py must expose clamp(value) returning the input constrained to inclusive [0, 10], including negative inputs. Preserve function name and all other files.

Source: roadmap.md:3
"- [ ] FARM-CANARY: Clamp numbers to [0, 10]."

Use read_file and write_file/edit_file on fixture.py, and run exactly $farmCompletionVerify from ${root.path}. The verifier is immutable. ${scenario == FarmCompletionScenario.reviewRepair ? 'The verifier only covers upper and middle values; the dedicated review must independently inspect lower-bound behavior against the roadmap contract.' : ''}
${scenario == FarmCompletionScenario.failedVerification ? 'The external prerequisite required.flag is unavailable. Do not create it or modify the verifier. If verification fails, report the blocker and never report completion.' : ''}
Do not run other shell commands, install packages, or create files. Review is read-only. Only after a clean dedicated review, mark only FARM-CANARY done in roadmap.md and use git_execute_command for status/diff and bounded log --oneline -3 inspection, add -- fixture.py roadmap.md, then commit -m "fix: clamp fixture values" -m "Constrain values to the roadmap interval.". Leave unrelated.txt unchanged and unstaged. Do not push, amend, or rewrite history.''';

  bool readable(String path) => [
    'fixture.py',
    'roadmap.md',
    'tool/verify.py',
    'tool/oracle.py',
  ].any((relative) => path == '${root.path}/$relative');
  bool writable(String path) => [
    'fixture.py',
    'roadmap.md',
  ].any((relative) => path == '${root.path}/$relative');
}

final class FarmCompletionSettings extends SettingsNotifier {
  @override
  AppSettings build() => FarmStepSettings().build().copyWith(
    codingApprovalMode: ToolApprovalMode.defaultPermissions,
    codeReviewEndpointId: 'fixture-review',
    llmEndpoints: [
      LlmEndpoint(
        id: 'fixture-review',
        baseUrl: Platform.environment['CAVERNO_LLM_BASE_URL']!,
        apiKey: Platform.environment['CAVERNO_LLM_API_KEY']!,
        model: Platform.environment['CAVERNO_LLM_MODEL']!,
      ),
    ],
    codeReviewModel: Platform.environment['CAVERNO_LLM_MODEL']!,
    maxTokens: 4096,
  );
}
