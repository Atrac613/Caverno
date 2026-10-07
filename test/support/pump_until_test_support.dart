import 'package:flutter_test/flutter_test.dart';

/// Pump until [finder] matches, then say how long it waited if it never does.
///
/// **For a widget whose appearance waits on real async work.** The diagnostics
/// export writes a file to `Directory.systemTemp` and only then calls
/// `setState`, so "Last export:" arrives after an I/O round trip that no amount
/// of pumping makes synchronous. Two tests asserted it two different ways and
/// both were order-dependent flakes, failing only in full-suite runs and
/// passing in isolation:
///
/// - `settings_page_test.dart` polled against a 3-second wall-clock deadline
///   and `break`ed out of the loop when it expired, so a timeout surfaced as
///   `findsOneWidget` failing on the next line — a message that says nothing
///   about waiting.
/// - `computer_use_debug_page_test.dart` asserted immediately after the tap,
///   and passed only while the write happened to land inside the tap's own
///   pumping.
///
/// Wall clock is the right budget here, because what is being waited on is real
/// I/O rather than frames — but three seconds is a measurement of an idle
/// machine, and a full run is not one. The generous default costs nothing when
/// the widget arrives at once, since the loop exits on the first match.
///
/// [what] is required, not optional: a failure that has to be read from a
/// `Finder`'s own description is a failure someone will re-diagnose, and the
/// caller is the only one who knows what it was really waiting on.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  required String what,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final elapsed = Stopwatch()..start();
  while (!tester.any(finder)) {
    if (elapsed.elapsed > timeout) {
      fail(
        'Waited ${elapsed.elapsed.inSeconds}s for $what and it never '
        'appeared. If this is the diagnostics export, the widget is waiting on '
        'a real file write; a timeout here means the write did not finish, not '
        'that the label is wrong.',
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
