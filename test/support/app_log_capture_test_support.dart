import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collects what `appLog` writes for the rest of the current test.
///
/// `appLog` short-circuits its file sink under `FLUTTER_TEST` and reaches
/// `debugPrint` instead, so swapping that is how a test reads the log.
List<String> captureAppLog() {
  final captured = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) =>
      captured.add(message ?? '');
  addTearDown(() => debugPrint = previous);
  return captured;
}

/// Asserts the unexecuted-tool-request notice reached the log and not the user.
///
/// The notice describes the harness, not a wrong claim, so it is deliberately
/// kept out of the reply; see `HarnessNoticeVisibility`.
void expectUnexecutedToolRequestLogged(
  List<String> appLogs,
  String messageContent,
) {
  expect(
    appLogs,
    contains(startsWith('[unexecuted_tool_request_notice] ')),
    reason: 'the notice should reach the log',
  );
  expect(
    messageContent,
    isNot(contains('I could not execute the additional tool request')),
    reason: 'the notice should stay out of the reply',
  );
}
