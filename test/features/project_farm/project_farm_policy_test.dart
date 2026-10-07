import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/presentation/widgets/project_farm_policy_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('policyCommandProblem', () {
    test('accepts a plain argv', () {
      expect(policyCommandProblem('fvm flutter analyze'), isNull);
      expect(
        policyCommandProblem('tool/flutter_test_quiet.sh test/a.dart'),
        isNull,
      );
    });

    test('rejects shell syntax and empty lines', () {
      for (final command in [
        'flutter test | tee log',
        'rm -rf x; true',
        'echo \$HOME',
        'make && make install',
        'cat < in',
        'echo "quoted"',
        'ls *.dart',
        '',
      ]) {
        expect(policyCommandProblem(command), isNotNull, reason: command);
      }
    });
  });

  test('allows only declared commands, ignoring extra whitespace', () {
    final policy = ProjectFarmPolicy(
      projectId: 'p',
      allowedVerificationCommands: const ['fvm flutter analyze'],
      updatedAt: DateTime.utc(2026, 9, 26),
    );
    expect(policy.allows('fvm  flutter   analyze'), isTrue);
    expect(policy.allows('fvm flutter analyze --fatal-infos'), isFalse);
    expect(policy.allowsBackgroundWork, isTrue);
  });

  test('the repository round-trips a policy', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = RoadmapSnapshotRepository(
      await SharedPreferences.getInstance(),
    );
    expect(repository.policyFor('p'), isNull);
    await repository.savePolicy(
      ProjectFarmPolicy(
        projectId: 'p',
        allowedVerificationCommands: const ['fvm flutter analyze'],
        updatedAt: DateTime.utc(2026, 9, 26),
      ),
    );
    expect(repository.policyFor('p')?.allowedVerificationCommands, [
      'fvm flutter analyze',
    ]);
  });

  testWidgets('the dialog refuses shell syntax and saves clean lines', (
    tester,
  ) async {
    List<String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showDialog<List<String>>(
              context: context,
              builder: (_) =>
                  const ProjectFarmPolicyDialog(initialCommands: []),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('project-farm-policy-commands'));
    final save = find.byKey(const ValueKey('project-farm-policy-save'));

    await tester.enterText(field, 'fvm flutter analyze\nflutter test | tee x');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, isNull, reason: 'the dialog stays open on an invalid line');

    await tester.enterText(
      field,
      'fvm   flutter analyze\n\nfvm flutter analyze',
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, ['fvm flutter analyze']);
  });

  testWidgets('the unattended dialog saves the switch, limit and commands', (
    tester,
  ) async {
    ProjectFarmPolicy? saved;
    final policy = ProjectFarmPolicy(
      projectId: 'p',
      allowedVerificationCommands: const [
        'fvm flutter analyze',
        'tool/flutter_test_quiet.sh',
      ],
      updatedAt: DateTime.utc(2026, 9, 26),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showDialog<ProjectFarmPolicy>(
              context: context,
              builder: (_) => ProjectFarmUnattendedDialog(policy: policy),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('project-farm-unattended-switch')),
    );
    await tester.tap(
      find.byKey(const ValueKey('project-farm-unattended-fvm flutter analyze')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('project-farm-unattended-save')),
    );
    await tester.pumpAndSettle();

    expect(saved!.autoRunEnabled, isTrue);
    expect(saved!.unattendedCommands, ['fvm flutter analyze']);
    expect(saved!.unattendedCommand, 'fvm flutter analyze');
    expect(saved!.allowsUnattendedRuns, isTrue);
  });
}
