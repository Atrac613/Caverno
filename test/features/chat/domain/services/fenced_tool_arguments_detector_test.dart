import 'package:caverno/features/chat/domain/services/fenced_tool_arguments_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = FencedToolArgumentsDetector();

  test('finds the arguments an answer printed instead of calling', () {
    // Verbatim from session 6035277f, the turn a user "はい" was answered with.
    const content =
        '本番実行を開始します。\n\n\n'
        '```json\n'
        '{"command":"bash tool/release_ios_macos.sh","label":"Production release iOS/macOS"}\n'
        '```';

    final detected = detector.detect(content);

    expect(detected, isNotNull);
    expect(detected!.command, 'bash tool/release_ios_macos.sh');
    expect(detected.rawJson, contains('Production release iOS/macOS'));
  });

  test('finds a harmless read command in the same shape', () {
    // The same session produced this for a plain grep, so the shape is not an
    // approval dodge.
    const content =
        '`pubspec.yaml` の version 行を探します。\n\n'
        '```json\n'
        '{"command":"grep \'^version:\' pubspec.yaml","label":"Get pubspec version"}\n'
        '```';

    expect(detector.detect(content)?.command, "grep '^version:' pubspec.yaml");
  });

  test('ignores a fence that names its tool', () {
    // A named tool is a content tool-call; the tag parsers own that case and
    // this detector must not compete with them.
    const content =
        '```json\n'
        '{"name":"local_execute_command","command":"ls"}\n'
        '```';

    expect(detector.detect(content), isNull);
  });

  test('ignores fences without a command', () {
    const content =
        'Here is the config:\n'
        '```json\n'
        '{"model":"qwen","temperature":0.7}\n'
        '```';

    expect(detector.detect(content), isNull);
  });

  test('ignores a blank command', () {
    const content = '```json\n{"command":"   "}\n```';

    expect(detector.detect(content), isNull);
  });

  test('ignores malformed JSON and non-object fences', () {
    expect(detector.detect('```json\n{"command":\n```'), isNull);
    expect(detector.detect('```json\n["command"]\n```'), isNull);
  });

  test('ignores content with no fence at all', () {
    expect(detector.detect('I will run the release script now.'), isNull);
    expect(detector.detect(''), isNull);
  });

  test('takes the first fenced command when an answer prints several', () {
    const content =
        '```json\n{"command":"first"}\n```\n'
        'then\n'
        '```json\n{"command":"second"}\n```';

    expect(detector.detect(content)?.command, 'first');
  });

  test('skips a named-tool fence and keeps looking', () {
    const content =
        '```json\n{"tool":"read_file","path":"a.dart"}\n```\n'
        '```json\n{"command":"ls -la"}\n```';

    expect(detector.detect(content)?.command, 'ls -la');
  });
}
