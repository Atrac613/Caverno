import 'package:caverno/features/chat/domain/services/out_of_root_command_paths.dart';
import 'package:test/test.dart';

void main() {
  const scanner = OutOfRootCommandPaths();
  const root = '/Users/dev/project';
  const spacedRoot = '/Users/noguwo/Documents/Workspace/Web/3D Sea Qwen';

  List<String> scan(String command, {String projectRoot = root}) =>
      scanner.scan(command: command, projectRoot: projectRoot);

  test('finds the path the shell fence never inspected', () {
    // The exact shape from session db878d3a: a heredoc is neither an
    // internally-executable command nor free of shell syntax, so
    // LocalShellTools.projectReadDenial returned null and no path was checked.
    const command =
        "python3 - <<'PY'\n"
        "from pathlib import Path\n"
        "p=Path('/Users/dev/.caverno/session_logs/chat/abc.jsonl')\n"
        'PY';

    expect(scan(command), ['/Users/dev/.caverno/session_logs/chat/abc.jsonl']);
  });

  test('ignores paths inside the project, including the root itself', () {
    expect(scan('cat $root/lib/main.dart'), isEmpty);
    expect(scan('ls $root'), isEmpty);
    expect(scan('ls $root/'), isEmpty);
  });

  test('a sibling directory sharing the root prefix is outside', () {
    expect(scan('cat /Users/dev/project-secrets/key.pem'), [
      '/Users/dev/project-secrets/key.pem',
    ]);
  });

  test('a parent directory is still outside', () {
    expect(scan('ls /Users/dev'), ['/Users/dev']);
  });

  test('relative paths are not absolute claims and are left alone', () {
    expect(scan('cat lib/main.dart && rg TODO src/'), isEmpty);
  });

  test('URLs and word-internal slashes are not paths', () {
    expect(scan('curl https://example.com/api/v1 && echo and/or'), isEmpty);
  });

  test('home-relative paths count as outside without expanding them', () {
    expect(scan('cat ~/.ssh/id_rsa'), ['~/.ssh/id_rsa']);
  });

  test('reports each distinct path once, in order', () {
    expect(scan('diff /etc/hosts /tmp/hosts /etc/hosts'), [
      '/etc/hosts',
      '/tmp/hosts',
    ]);
  });

  test('reports nothing when there is no root to compare against', () {
    // Not a claim that the path is safe -- there is simply no boundary here,
    // and the caller's missing-root path is where that gets refused.
    expect(scanner.scan(command: 'cat /etc/hosts', projectRoot: null), isEmpty);
    expect(scanner.scan(command: 'cat /etc/hosts', projectRoot: '  '), isEmpty);
  });

  test('referencesOutsidePath mirrors scan', () {
    expect(
      scanner.referencesOutsidePath(
        command: 'cat /etc/hosts',
        projectRoot: root,
      ),
      isTrue,
    );
    expect(
      scanner.referencesOutsidePath(
        command: 'cat $root/pubspec.yaml',
        projectRoot: root,
      ),
      isFalse,
    );
  });

  test('quoted in-project paths that contain spaces stay inside', () {
    // Session that followed 69aa8077: the unquoted token regex stopped at the
    // space in `3D Sea Qwen` and reported `/Users/.../Web/3D`, a directory
    // that does not exist, as outside the project.
    final command = 'node --input-type=module --check < "$spacedRoot/sea.js"';

    expect(scan(command, projectRoot: spacedRoot), isEmpty);
  });

  test('an unquoted truncation of a spaced root is not outside evidence', () {
    final command = 'node --input-type=module --check < $spacedRoot/sea.js';

    expect(scan(command, projectRoot: spacedRoot), isEmpty);
  });

  test('quoted outside paths that contain spaces are still reported whole', () {
    expect(scan('cat "/Users/dev/My Documents/secret.txt"'), [
      '/Users/dev/My Documents/secret.txt',
    ]);
  });

  test('nested quotes still yield the inner absolute path', () {
    expect(scan('''python3 -c "print(open('/etc/hosts').read())"'''), [
      '/etc/hosts',
    ]);
  });

  test('standard device files are not outside the project', () {
    expect(scan('curl -s -o /dev/null https://example.com'), isEmpty);
    expect(scan("awk 'BEGIN { print 1 }' /dev/null"), isEmpty);
    expect(scan('echo hi >/dev/stdout'), isEmpty);
    expect(scan('cat /dev/fd/2'), isEmpty);
  });

  test('an unquoted path between contraction apostrophes is still found', () {
    // Regression: `'([^']*)'` pairs the apostrophes in `it's` and `that's`,
    // and blanking that span erased the path between them, so the scan
    // returned nothing and the command skipped approval entirely.
    expect(
      scan(r'''echo "it's fine" && cat /etc/hosts && echo "that's all"'''),
      ['/etc/hosts'],
    );
    expect(scan(r'''bash -c "echo it's; cat /etc/passwd; echo that's"'''), [
      '/etc/passwd',
    ]);
  });

  test(
    'a real path that prefixes the root is not mistaken for a truncation',
    () {
      // `/Users/dev/pro` breaks the root at `j`, not at a space, so it is a
      // different file rather than the head of an in-project path.
      expect(scan('cat /Users/dev/pro'), ['/Users/dev/pro']);
    },
  );

  test('the approval prompt asserts no token and repeats no command', () {
    final decision = LocalCommandApprovalScope.outsideProjectApproval(const [
      '/etc/hosts',
    ]);

    expect(decision, isNotNull);
    expect(decision!.approvalPromptTitle, contains('may reach outside'));
    expect(
      decision.approvalPromptRationale,
      isNot(contains('/etc/hosts')),
      reason: 'the token is why the ask fired, not a claim about the disk',
    );
    // The sheet renders pending.command in its own block. Carrying it here too
    // showed it twice and pushed an uncapped copy into the audit rationale,
    // which is written verbatim while arguments truncate at 240 characters.
    expect(decision.approvalPromptRationale, isNot(contains('cat ')));
  });

  test('outsideProjectApproval is silent when nothing is outside', () {
    expect(LocalCommandApprovalScope.outsideProjectApproval(const []), isNull);
  });
}
