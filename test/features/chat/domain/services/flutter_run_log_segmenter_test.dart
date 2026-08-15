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

  test('a half-arrived block is not a candidate while output streams', () {
    // Found through the panel: mid-stream the block has no stack frame yet, so
    // emitting it would take a different signature from the finished block and
    // list the same failure twice.
    final partial = logsOf(_overflow).sublist(0, 9);

    expect(segmenter.segment(partial), isEmpty);
    expect(
      segmenter.segment(partial, allowUnterminated: true),
      hasLength(1),
      reason: 'once the stream is over, a partial block is all there is',
    );
  });

  test('recognises a platform build failure by its banner', () {
    // The Xcode error text differs with every SDK; the banner does not.
    const xcode = '''
Launching lib/main.dart on Untitled 2 in debug mode...
Automatically signing iOS for device deployment...
Running Xcode build...
Xcode build done.                                           28.7s
Failed to build iOS app
Error (Xcode): Signing for "Runner" requires a development team.
Could not build the application for the simulator.
Error launching application on Untitled 2.
''';

    final candidates = segmenter.segment(logsOf(xcode));

    expect(candidates, isNotEmpty);
    final candidate = candidates.first;
    expect(candidate.kind, FlutterRunIssueKind.buildFailure);
    expect(candidate.evidence, contains('requires a development team'));
    // The cause is printed above the banner, so the block reaches back.
    expect(candidate.evidence, contains('Running Xcode build...'));
  });

  test('an unknown failure shape still yields a tail to analyse', () {
    // The generalisation: rather than widening patterns until they match
    // healthy output too, an unrecognised failure hands over its tail.
    const unknown = '''
Launching lib/main.dart on Untitled 2 in debug mode...
ld: warning: ignoring duplicate libraries
SomeToolchain::fatal — object file malformed in a way no pattern knows
''';

    final logs = logsOf(unknown);
    expect(segmenter.segment(logs), isEmpty);

    final tail = segmenter.unclassifiedTail(logs);

    expect(tail, isNotNull);
    expect(tail!.kind, FlutterRunIssueKind.unclassifiedFailure);
    expect(tail.evidence, contains('object file malformed'));
    // Startup chatter is still excluded from the window.
    expect(tail.evidence, isNot(contains('Syncing files')));
  });

  test('the tail is bounded', () {
    final logs = logsOf(
      List.generate(500, (index) => 'line $index').join('\n'),
    );

    final tail = segmenter.unclassifiedTail(logs, maxLines: 20);

    expect(tail!.lines, hasLength(20));
    expect(tail.lines.last, 'line 499');
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
