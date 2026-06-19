import 'dart:io';

import 'package:caverno/features/chat/data/repositories/coding_project_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/presentation/providers/coding_environment_snapshot_provider.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_launcher.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = _container(prefs, runProcess: _gitRunner());
  });

  tearDown(() {
    container.dispose();
  });

  WorktreeAgentTaskLauncher launcher() =>
      container.read(worktreeAgentTaskLauncherProvider);

  test('enqueues a planned task for the selected coding project', () async {
    container.dispose();
    await _saveProjects(prefs, [
      _project(
        id: 'project-1',
        name: 'caverno',
        rootPath: '/Users/test/Workspace/caverno',
      ),
    ]);
    container = _container(prefs, runProcess: _gitRunner());
    await container
        .read(settingsNotifierProvider.notifier)
        .updateSubagentEndpointId('mesh-1');

    final result = await launcher().enqueue(
      const WorktreeAgentTaskLaunchRequest(
        title: 'Fix flaky widget test',
        prompt: 'Repair the failing widget test.',
        checkpointLineageId: 'checkpoint-1',
        verificationCommand: 'fvm flutter test test/widget_test.dart',
      ),
    );

    expect(result.plan.branchName, 'feature/ll13-fix-flaky-widget-test');
    expect(
      result.plan.worktreePath,
      '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test',
    );
    expect(result.task.codingProjectId, 'project-1');
    expect(result.task.endpointId, 'mesh-1');
    expect(result.task.checkpointLineageId, 'checkpoint-1');
    expect(
      result.task.verificationCommand,
      'fvm flutter test test/widget_test.dart',
    );
    expect(
      container.read(worktreeAgentTaskRegistryNotifierProvider).tasks.single.id,
      result.task.id,
    );
  });

  test(
    'balances implicit endpoint assignment across named endpoints',
    () async {
      container.dispose();
      await _saveProjects(prefs, [
        _project(
          id: 'project-1',
          name: 'caverno',
          rootPath: '/Users/test/Workspace/caverno',
        ),
      ]);
      container = _container(prefs, runProcess: _gitRunner());

      const firstBaseUrl = 'http://mesh-one:1234/v1';
      const secondBaseUrl = 'http://mesh-two:1234/v1';
      const disabledBaseUrl = 'http://mesh-disabled:1234/v1';
      final firstEndpointId = NamedEndpoint.buildId(firstBaseUrl);
      final secondEndpointId = NamedEndpoint.buildId(secondBaseUrl);
      final disabledEndpointId = NamedEndpoint.buildId(disabledBaseUrl);
      final settingsNotifier = container.read(
        settingsNotifierProvider.notifier,
      );
      await settingsNotifier.upsertNamedEndpoint(
        const NamedEndpoint(id: 'mesh-one', baseUrl: firstBaseUrl),
      );
      await settingsNotifier.upsertNamedEndpoint(
        const NamedEndpoint(id: 'mesh-two', baseUrl: secondBaseUrl),
      );
      await settingsNotifier.upsertNamedEndpoint(
        const NamedEndpoint(
          id: 'mesh-disabled',
          baseUrl: disabledBaseUrl,
          enabled: false,
        ),
      );
      await settingsNotifier.updateSubagentEndpointId(firstEndpointId);

      final first = await launcher().enqueue(
        const WorktreeAgentTaskLaunchRequest(
          title: 'Fix alpha flow',
          prompt: 'Repair the alpha flow.',
        ),
      );
      final second = await launcher().enqueue(
        const WorktreeAgentTaskLaunchRequest(
          title: 'Fix beta flow',
          prompt: 'Repair the beta flow.',
        ),
      );
      final third = await launcher().enqueue(
        const WorktreeAgentTaskLaunchRequest(
          title: 'Fix gamma flow',
          prompt: 'Repair the gamma flow.',
        ),
      );

      expect(first.task.endpointId, firstEndpointId);
      expect(second.task.endpointId, secondEndpointId);
      expect(third.task.endpointId, firstEndpointId);
      expect(
        container
            .read(worktreeAgentTaskRegistryNotifierProvider)
            .tasks
            .map((task) => task.endpointId),
        isNot(contains(disabledEndpointId)),
      );
    },
  );

  test(
    'ignores a disabled default endpoint when mesh endpoints exist',
    () async {
      container.dispose();
      await _saveProjects(prefs, [
        _project(
          id: 'project-1',
          name: 'caverno',
          rootPath: '/Users/test/Workspace/caverno',
        ),
      ]);
      container = _container(prefs, runProcess: _gitRunner());

      const enabledBaseUrl = 'http://mesh-enabled:1234/v1';
      const disabledBaseUrl = 'http://mesh-disabled:1234/v1';
      final enabledEndpointId = NamedEndpoint.buildId(enabledBaseUrl);
      final disabledEndpointId = NamedEndpoint.buildId(disabledBaseUrl);
      final settingsNotifier = container.read(
        settingsNotifierProvider.notifier,
      );
      await settingsNotifier.upsertNamedEndpoint(
        const NamedEndpoint(id: 'mesh-enabled', baseUrl: enabledBaseUrl),
      );
      await settingsNotifier.upsertNamedEndpoint(
        const NamedEndpoint(
          id: 'mesh-disabled',
          baseUrl: disabledBaseUrl,
          enabled: false,
        ),
      );
      await settingsNotifier.updateSubagentEndpointId(disabledEndpointId);

      final result = await launcher().enqueue(
        const WorktreeAgentTaskLaunchRequest(
          title: 'Fix endpoint fallback',
          prompt: 'Repair endpoint selection.',
        ),
      );

      expect(result.task.endpointId, enabledEndpointId);
    },
  );

  test('uses explicit roots and git reservations when planning', () async {
    container.dispose();
    container = _container(
      prefs,
      runProcess: _gitRunner(
        branches: const ['feature/custom-fix-flaky-widget-test'],
        worktreePaths: const [
          '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test',
        ],
      ),
    );

    final result = await launcher().enqueue(
      const WorktreeAgentTaskLaunchRequest(
        title: 'Fix flaky widget test',
        prompt: 'Repair the failing widget test.',
        codingProjectId: 'external-project',
        projectRootPath: '/Users/test/Workspace/caverno',
        branchPrefix: 'feature/custom',
        endpointId: 'mesh-explicit',
        verificationCommand: 'fvm flutter analyze',
      ),
    );

    expect(result.task.branchName, 'feature/custom-fix-flaky-widget-test-2');
    expect(
      result.task.worktreePath,
      '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test-2',
    );
    expect(result.task.codingProjectId, 'external-project');
    expect(result.task.endpointId, 'mesh-explicit');
    expect(result.task.verificationCommand, 'fvm flutter analyze');
  });

  test(
    'does not attach the selected project id to an unrelated explicit root',
    () async {
      container.dispose();
      await _saveProjects(prefs, [
        _project(
          id: 'project-1',
          name: 'caverno',
          rootPath: '/Users/test/Workspace/caverno',
        ),
      ]);
      container = _container(prefs, runProcess: _gitRunner());

      final result = await launcher().enqueue(
        const WorktreeAgentTaskLaunchRequest(
          title: 'Fix docs',
          prompt: 'Update docs.',
          projectRootPath: '/Users/test/Workspace/other',
        ),
      );

      expect(result.task.codingProjectId, isEmpty);
      expect(
        result.task.worktreePath,
        '/Users/test/Workspace/other-worktrees/fix-docs',
      );
    },
  );

  test('requires a project root path before enqueueing', () async {
    expect(
      () => launcher().enqueue(
        const WorktreeAgentTaskLaunchRequest(
          title: 'Fix test',
          prompt: 'Fix the failing test.',
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'fails before enqueueing when git reservations cannot be read',
    () async {
      container.dispose();
      container = _container(
        prefs,
        runProcess: (executable, arguments, {workingDirectory}) async {
          return ProcessResult(1, 1, '', 'not a git repository');
        },
      );

      expect(
        () => launcher().enqueue(
          const WorktreeAgentTaskLaunchRequest(
            title: 'Fix test',
            prompt: 'Fix the failing test.',
            projectRootPath: '/Users/test/Workspace/caverno',
          ),
        ),
        throwsStateError,
      );
    },
  );
}

ProviderContainer _container(
  SharedPreferences prefs, {
  CodingEnvironmentProcessRunner? runProcess,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (runProcess != null)
        codingEnvironmentProcessRunnerProvider.overrideWithValue(runProcess),
    ],
  );
}

CodingEnvironmentProcessRunner _gitRunner({
  List<String> branches = const <String>[],
  List<String> worktreePaths = const <String>[],
}) {
  return (executable, arguments, {workingDirectory}) async {
    if (executable != 'git') {
      return ProcessResult(1, 1, '', 'unexpected executable');
    }
    if (_argumentsEqual(arguments, const ['rev-parse', '--show-toplevel'])) {
      return ProcessResult(1, 0, workingDirectory ?? '', '');
    }
    if (_argumentsEqual(arguments, const [
      'for-each-ref',
      '--format=%(refname:short)',
      'refs/heads',
    ])) {
      return ProcessResult(2, 0, branches.join('\n'), '');
    }
    if (_argumentsEqual(arguments, const ['worktree', 'list', '--porcelain'])) {
      return ProcessResult(3, 0, _worktreePorcelain(worktreePaths), '');
    }
    return ProcessResult(4, 1, '', 'unexpected git command');
  };
}

bool _argumentsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

String _worktreePorcelain(List<String> worktreePaths) {
  return worktreePaths
      .map(
        (path) => [
          'worktree $path',
          'HEAD 0000000000000000000000000000000000000000',
          'branch refs/heads/main',
        ].join('\n'),
      )
      .join('\n\n');
}

Future<void> _saveProjects(
  SharedPreferences prefs,
  List<CodingProject> projects,
) {
  return CodingProjectRepository(prefs).saveAll(projects);
}

CodingProject _project({
  required String id,
  required String name,
  required String rootPath,
}) {
  return CodingProject(
    id: id,
    name: name,
    rootPath: rootPath,
    createdAt: DateTime.utc(2026, 6, 19),
    updatedAt: DateTime.utc(2026, 6, 19),
  );
}
