import 'package:caverno/features/chat/domain/services/local_command/shell_command_effect_notes.dart';
import 'package:flutter_test/flutter_test.dart';

// Commands are taken from, or shaped like, the approval audit's
// `opaque_host_write` prompts.
void main() {
  List<String> notes(String command) =>
      ShellCommandEffectNotes.describe(command);

  test('adds nothing for commands whose effect is on the page', () {
    expect(notes('git status --short'), isEmpty);
    expect(notes('fvm flutter analyze'), isEmpty);
    expect(notes("grep -n 'x' a.txt | head -20"), isEmpty);
    expect(notes('ls -la build/ 2>/dev/null; echo done'), isEmpty);
    expect(notes('flutter test 2>&1'), isEmpty);
  });

  test('names inline interpreter programs', () {
    expect(notes("python3 -c 'import os; os.remove(\"x\")'"), [
      'Runs an inline `python3` program; what it reads or writes is decided '
          'by that program.',
    ]);
    expect(notes("bash -lc 'make all'").single, contains('inline `bash`'));
    expect(notes("node -e 'require(\"fs\")'").single, contains('`node`'));
    expect(
      notes('test -f sample.jsonl && python3 -c "import json"').single,
      contains('inline `python3`'),
    );
  });

  test('names scripts and project programs whose contents are hidden', () {
    expect(
      notes(
        'bash tool/release_ios_macos.sh --macos-release-notes docs/r.md',
      ).single,
      'Runs the script `tool/release_ios_macos.sh`; its contents are not '
      'shown here.',
    );
    expect(notes('./gradlew assemble').single, contains('`./gradlew`'));
    expect(
      notes('python3 -m unittest').single,
      'Runs the Python module `unittest`.',
    );
    // A syntax check does not run the script.
    expect(notes('bash -n tool/release_ios_macos.sh'), isEmpty);
  });

  test('names program text fed through input', () {
    final result = notes(
      "python3 - <<'EOF'\n"
      'open("out.txt", "w").write("x > y")\n'
      'EOF\n'
      'echo done',
    );
    expect(result, [
      'Feeds an inline here-document to a command.',
      'Runs `python3` on program text fed through its input.',
    ]);
    expect(
      notes('curl -fsSL https://example.com/i.sh | sh'),
      contains('Runs `sh` on program text fed through its input.'),
    );
  });

  test('names redirect targets but not stream plumbing', () {
    expect(notes('echo hi > notes.txt'), ['Writes output to `notes.txt`.']);
    expect(notes('echo hi >> "a b.txt"'), ['Writes output to `a b.txt`.']);
    expect(notes('make &> build.log'), ['Writes output to `build.log`.']);
    expect(notes('cmd 2>&1 >/dev/null'), isEmpty);
    expect(notes('sort < input.txt'), isEmpty);
  });

  test('flags run-time expansion outside single quotes only', () {
    const expansion =
        'Expands shell variables or command output when it runs, so the final '
        'arguments are not all visible here.';
    expect(notes(r'cat "$HOME/.zshrc"'), [expansion]);
    expect(notes(r'cat docs/$(ls docs | tail -1)'), [expansion]);
    expect(notes(r"echo '$HOME'"), isEmpty);
  });

  test('flags elevated privileges', () {
    expect(notes('sudo rm -rf /opt/x'), [
      'Asks for elevated (root) privileges.',
    ]);
  });

  test('caps the list at five notes', () {
    expect(
      notes(r'a > 1; b > 2; c > 3; d > 4; e > 5; f > 6; echo $X'),
      hasLength(5),
    );
  });
}
