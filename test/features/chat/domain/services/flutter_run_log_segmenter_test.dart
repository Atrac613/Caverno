import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/flutter_run_issue.dart';
import 'package:caverno/features/chat/domain/entities/flutter_run_session.dart';
import 'package:caverno/features/chat/domain/services/flutter_run_log_segmenter.dart';

/// Shapes copied from real `flutter run` output. The segmenter is judged
/// against the toolchain's actual framing, not against a tidied-up idea of it.
const _overflow = '''
Launching lib/main.dart on macOS in debug mode...
Building macOS application...
Syncing files to device macOS...
Flutter run key commands.
r Hot reload.
A Dart VM Service on macOS is available at: http://127.0.0.1:52341/abc=/
The Flutter DevTools debugger and profiler on macOS is available at: http://127.0.0.1:9101
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════════════════
The following assertion was thrown during layout:
A RenderFlex overflowed by 42 pixels on the right.

The relevant error-causing widget was:
  Row Row:file:///Users/dev/app/lib/home_page.dart:64:16
════════════════════════════════════════════════════════════════════════════════
''';

const _nullCheck = '''
[ERROR:flutter/runtime/dart_vm_initializer.cc(41)] Unhandled Exception: Null check operator used on a null value
#0      _HomePageState._load (package:app/home_page.dart:88:24)
#1      _HomePageState.build.<anonymous closure> (package:app/home_page.dart:52:9)
#2      State.setState (package:flutter/src/widgets/framework.dart:1204:30)
Another line that is not a frame.
''';

const _compileError = '''
Launching lib/main.dart on macOS in debug mode...
lib/home_page.dart:12:5: Error: Expected ';' after this.
    final value = 1
    ^
Target kernel_snapshot_program failed: Exception
''';

void main() {
  const segmenter = FlutterRunLogSegmenter();

  List<FlutterRunLogLine> logsOf(String raw) => [
    for (final line in raw.trim().split('\n'))
      FlutterRunLogLine(
        text: line,
        source: FlutterRunLogSource.stdout,
        at: DateTime.utc(2026, 8, 15),
      ),
  ];

  test('cuts a framework exception at its banner rules', () {
    final candidates = segmenter.segment(logsOf(_overflow));

    expect(candidates, hasLength(1));
    final candidate = candidates.single;
    expect(candidate.kind, FlutterRunIssueKind.frameworkException);
    expect(
      candidate.headline,
      'The following assertion was thrown during layout:',
    );
    expect(candidate.evidence, contains('A RenderFlex overflowed by 42'));
    expect(candidate.evidence, startsWith('══╡ EXCEPTION CAUGHT BY'));
    expect(candidate.location, 'lib/home_page.dart:64');
  });

  test('startup chatter and service URLs are never candidates', () {
    final logs = logsOf(_overflow).sublist(0, 7);

    expect(segmenter.segment(logs), isEmpty);
  });

  test('cuts an unhandled exception at the end of its stack', () {
    final candidates = segmenter.segment(logsOf(_nullCheck));

    expect(candidates, hasLength(1));
    final candidate = candidates.single;
    expect(candidate.kind, FlutterRunIssueKind.unhandledException);
    expect(candidate.headline, 'Null check operator used on a null value');
    expect(candidate.lines, hasLength(4));
    expect(candidate.evidence, isNot(contains('not a frame')));
    // The first frame outside the framework is the actionable one, in the
    // same project-relative spelling a file:// frame would produce.
    expect(candidate.location, 'lib/home_page.dart:88');
  });

  test('cuts a compile error with its source line and caret', () {
    final candidates = segmenter.segment(logsOf(_compileError));

    expect(candidates, hasLength(1));
    final candidate = candidates.single;
    expect(candidate.kind, FlutterRunIssueKind.compileError);
    expect(candidate.headline, "Expected ';' after this.");
    expect(candidate.location, 'lib/home_page.dart:12');
    expect(candidate.evidence, contains('final value = 1'));
  });

  test('the same overflow keeps one signature as the pixels change', () {
    // The count differs every frame; a signature that moved with it would
    // defeat the deduplication it exists for.
    final first = segmenter.segment(logsOf(_overflow)).single;
    final second = segmenter
        .segment(logsOf(_overflow.replaceAll('42 pixels', '137 pixels')))
        .single;

    expect(first.signature, second.signature);
  });

  test('different failures keep different signatures', () {
    final overflow = segmenter.segment(logsOf(_overflow)).single;
    final nullCheck = segmenter.segment(logsOf(_nullCheck)).single;
    final otherLine = segmenter
        .segment(
          logsOf(
            _nullCheck.replaceAll('home_page.dart:88', 'home_page.dart:91'),
          ),
        )
        .single;

    expect(overflow.signature, isNot(nullCheck.signature));
    expect(nullCheck.signature, isNot(otherLine.signature));
  });

  test('the two frame spellings of one file agree', () {
    // `package:app/home_page.dart` and an absolute `file:///.../lib/...` name
    // the same line; if they normalised differently, one bug would become two
    // issues depending on which frame the toolchain happened to print.
    final fromPackageUri = segmenter.segment(logsOf(_nullCheck)).single;
    final fromFileUri = segmenter
        .segment(
          logsOf(
            _nullCheck.replaceAll(
              'package:app/home_page.dart:88:24',
              'file:///Users/dev/app/lib/home_page.dart:88:24',
            ),
          ),
        )
        .single;

    expect(fromPackageUri.location, 'lib/home_page.dart:88');
    expect(fromFileUri.location, fromPackageUri.location);
    expect(fromFileUri.signature, fromPackageUri.signature);
  });

  test('reads a stream containing several distinct failures', () {
    final logs = logsOf('$_overflow\n$_nullCheck\n$_compileError');

    final candidates = segmenter.segment(logs);

    expect(candidates.map((candidate) => candidate.kind), [
      FlutterRunIssueKind.frameworkException,
      FlutterRunIssueKind.unhandledException,
      FlutterRunIssueKind.compileError,
    ]);
    expect(
      candidates.map((candidate) => candidate.signature).toSet(),
      hasLength(3),
    );
  });

  test('re-segmenting the same buffer is idempotent', () {
    // Callers re-run this after every batch of lines rather than keeping
    // incremental parser state, so repeats must be identical.
    final logs = logsOf('$_overflow\n$_nullCheck');

    final first = segmenter.segment(logs).map((c) => c.signature).toList();
    final second = segmenter.segment(logs).map((c) => c.signature).toList();

    expect(first, second);
  });

  test('a clean run produces nothing to analyse', () {
    const clean = '''
Launching lib/main.dart on macOS in debug mode...
Building macOS application...
Syncing files to device macOS...
Flutter run key commands.
Application finished.
''';

    expect(segmenter.segment(logsOf(clean)), isEmpty);
  });
}
