import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/flutter_run_provider.dart';
import 'package:caverno/features/chat/presentation/providers/html_preview_provider.dart';
import 'package:caverno/features/chat/presentation/widgets/flutter_run_control_section.dart';
import 'package:caverno/features/chat/presentation/widgets/html_preview_control_section.dart';
import 'package:caverno/features/chat/presentation/widgets/project_run_control_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, {required bool flutterSupported}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          flutterRunSupportedProvider(
            '/tmp/project',
          ).overrideWithValue(flutterSupported),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ProjectRunControlSection(
              projectRoot: '/tmp/project',
              threadId: 'thread-1',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a Flutter project gets the flutter run control', (tester) async {
    await pump(tester, flutterSupported: true);

    expect(find.byType(FlutterRunControlSection), findsOneWidget);
    expect(find.byType(HtmlPreviewControlSection), findsNothing);
  });

  testWidgets('anything else falls to the HTML preview control', (
    tester,
  ) async {
    // htmlPreviewSupportedProvider already returns false wherever the Flutter
    // one is true, so reaching here means the project is the HTML kind: the
    // panel only renders this section when one of the two holds.
    await pump(tester, flutterSupported: false);

    expect(find.byType(HtmlPreviewControlSection), findsOneWidget);
    expect(find.byType(FlutterRunControlSection), findsNothing);
  });

  test('the panel sees a runner when either kind is supported', () {
    ProviderContainer containerFor({
      required bool flutter,
      required bool html,
    }) => ProviderContainer(
      overrides: [
        flutterRunSupportedProvider('/tmp/p').overrideWithValue(flutter),
        htmlPreviewSupportedProvider('/tmp/p').overrideWithValue(html),
      ],
    );

    for (final (flutter, html, expected) in const [
      (true, false, true),
      (false, true, true),
      (false, false, false),
    ]) {
      final container = containerFor(flutter: flutter, html: html);
      addTearDown(container.dispose);
      expect(
        container.read(projectRunControlSupportedProvider('/tmp/p')),
        expected,
        reason: 'flutter=$flutter html=$html',
      );
    }
  });
}
