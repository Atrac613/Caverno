import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/local_command_permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalCommandPermissionService', () {
    test('matches the first enabled exact rule', () {
      const rules = [
        LocalCommandPermissionRule(
          id: 'allow-test',
          action: LocalCommandPermissionAction.allow,
          pattern: 'flutter test',
        ),
      ];

      final evaluation = LocalCommandPermissionService.evaluate(
        command: 'flutter test',
        workingDirectory: '/repo',
        rules: rules,
      );

      expect(evaluation.action, LocalCommandPermissionAction.allow);
      expect(evaluation.rule?.id, 'allow-test');
    });

    test('does not match exact rules with additional arguments', () {
      const rules = [
        LocalCommandPermissionRule(
          id: 'allow-test',
          action: LocalCommandPermissionAction.allow,
          pattern: 'flutter test',
        ),
      ];

      final evaluation = LocalCommandPermissionService.evaluate(
        command: 'flutter test test/widget_test.dart',
        workingDirectory: '/repo',
        rules: rules,
      );

      expect(evaluation.action, LocalCommandPermissionAction.ask);
      expect(evaluation.rule, isNull);
    });

    test('matches prefix rules on command boundaries', () {
      const rules = [
        LocalCommandPermissionRule(
          id: 'deny-rm',
          action: LocalCommandPermissionAction.deny,
          match: LocalCommandPermissionMatch.prefix,
          pattern: 'rm',
        ),
      ];

      final matching = LocalCommandPermissionService.evaluate(
        command: 'rm -rf build',
        workingDirectory: '/repo',
        rules: rules,
      );
      final boundarySafe = LocalCommandPermissionService.evaluate(
        command: 'rmdir build',
        workingDirectory: '/repo',
        rules: rules,
      );

      expect(matching.action, LocalCommandPermissionAction.deny);
      expect(boundarySafe.action, LocalCommandPermissionAction.ask);
    });

    test('ignores disabled rules', () {
      const rules = [
        LocalCommandPermissionRule(
          id: 'disabled-deny',
          enabled: false,
          action: LocalCommandPermissionAction.deny,
          pattern: 'npm install',
        ),
      ];

      final evaluation = LocalCommandPermissionService.evaluate(
        command: 'npm install',
        workingDirectory: '/repo',
        rules: rules,
      );

      expect(evaluation.action, LocalCommandPermissionAction.ask);
    });

    test('matches scoped rules only in their working directory', () {
      const rules = [
        LocalCommandPermissionRule(
          id: 'allow-test',
          action: LocalCommandPermissionAction.allow,
          pattern: 'flutter test',
          workingDirectory: '/repo/app',
        ),
      ];

      final matching = LocalCommandPermissionService.evaluate(
        command: 'flutter test',
        workingDirectory: '/repo/app',
        rules: rules,
      );
      final outsideScope = LocalCommandPermissionService.evaluate(
        command: 'flutter test',
        workingDirectory: '/repo/other',
        rules: rules,
      );

      expect(matching.action, LocalCommandPermissionAction.allow);
      expect(outsideScope.action, LocalCommandPermissionAction.ask);
    });

    test('rejects broad allow prefix rules', () {
      const rule = LocalCommandPermissionRule(
        id: 'broad-python',
        action: LocalCommandPermissionAction.allow,
        match: LocalCommandPermissionMatch.prefix,
        pattern: 'python3',
      );

      expect(LocalCommandPermissionService.validateRule(rule), isNotNull);
    });

    test('allows exact rules for broad commands', () {
      const rule = LocalCommandPermissionRule(
        id: 'exact-python',
        action: LocalCommandPermissionAction.allow,
        pattern: 'python3 scripts/check.py',
      );

      expect(LocalCommandPermissionService.validateRule(rule), isNull);
    });

    test('reports destructive risk warnings', () {
      expect(
        LocalCommandPermissionService.riskWarningFor('rm -rf build')?.title,
        'Recursive file deletion',
      );
      expect(
        LocalCommandPermissionService.riskWarningFor('git reset --hard')?.title,
        'Hard git reset',
      );
      expect(
        LocalCommandPermissionService.riskWarningFor('git status'),
        isNull,
      );
    });

    test('requires approval for dangerous removals despite allow rules', () {
      const rules = [
        LocalCommandPermissionRule(
          id: 'allow-rm',
          action: LocalCommandPermissionAction.allow,
          match: LocalCommandPermissionMatch.prefix,
          pattern: 'rm -rf',
        ),
      ];

      final evaluation = LocalCommandPermissionService.evaluate(
        command: 'rm -rf /',
        workingDirectory: '/repo',
        rules: rules,
      );

      expect(evaluation.action, LocalCommandPermissionAction.ask);
      expect(
        LocalCommandPermissionService.riskWarningFor('rm -rf /')?.title,
        'Dangerous file deletion target',
      );
    });

    test('handles POSIX double dash before dangerous removal targets', () {
      expect(
        LocalCommandPermissionService.riskWarningFor(
          'rm -- -/../.caverno/settings.local.json',
        )?.title,
        'Dangerous file deletion target',
      );
      expect(
        LocalCommandPermissionService.riskWarningFor('rm -- /')?.title,
        'Dangerous file deletion target',
      );
    });

    test('finds destructive commands across shell separators', () {
      expect(
        LocalCommandPermissionService.riskWarningFor(
          'echo ok; git reset --hard',
        )?.title,
        'Hard git reset',
      );
      expect(
        LocalCommandPermissionService.riskWarningFor(
          'printf safe || psql -c "truncate table users"',
        )?.title,
        'Database destructive operation',
      );
    });

    test('reports additional git risks', () {
      expect(
        LocalCommandPermissionService.riskWarningFor('git push -f')?.title,
        'Forced git push',
      );
      expect(
        LocalCommandPermissionService.riskWarningFor('git restore -- .')?.title,
        'Git worktree overwrite',
      );
      expect(
        LocalCommandPermissionService.riskWarningFor(
          'git branch --delete --force old-branch',
        )?.title,
        'Forced branch deletion',
      );
      expect(
        LocalCommandPermissionService.riskWarningFor(
          'git commit --amend',
        )?.title,
        'Git commit amend',
      );
    });
  });
}
