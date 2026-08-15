import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/flutter_run_process_runner.dart';
import 'package:caverno/features/chat/domain/entities/flutter_run_issue.dart';
import 'package:caverno/features/chat/domain/services/flutter_run_command_builder.dart';
import 'package:caverno/features/chat/presentation/providers/flutter_run_provider.dart';
import 'package:caverno/features/chat/presentation/widgets/flutter_run_control_section.dart';
import 'package:caverno/features/chat/presentation/widgets/flutter_run_issue_list.dart';
import 'package:caverno/features/chat/presentation/widgets/flutter_run_log_view.dart';
import 'package:caverno/features/chat/presentation/widgets/terminal/coding_terminal_dock.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

/// Lets an async chain finish between frames.
///
/// `pumpAndSettle` stops as soon as no frame is scheduled, which is before the
/// device listing has walked its process, drain and parse hops. Each zero-length
/// pump drains the microtask queue, which is what those hops resume on --
/// `pumpEventQueue` cannot be used here, since its delayed futures need the
/// binding's fake clock to advance.
Future<void> settle(WidgetTester tester) async {
  // `runAsync` steps outside the binding's fake clock so the listing's process,
  // drain and parse hops actually run; `pumpAndSettle` alone returns as soon as
  // no frame is scheduled, which is well before they finish.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  const projectRoot = '/work/app';

  Future<void> pump(
    WidgetTester tester,
    _FakeRunner runner, {
    void Function(FlutterRunIssue issue)? onIssue,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          flutterRunProcessRunnerProvider.overrideWithValue(runner),
          flutterRunCommandBuilderProvider.overrideWithValue(
            const FlutterRunCommandBuilder(usesFvm: _noFvm),
          ),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          useOnlyLangCode: true,
          saveLocale: false,
          assetLoader: const _TestTranslationLoader(),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Scaffold(
                body: Column(
                  children: [
                    const FlutterRunControlSection(projectRoot: projectRoot),
                    const Expanded(
                      child: FlutterRunLogView(projectRoot: projectRoot),
                    ),
                    Expanded(
                      child: FlutterRunIssueList(
                        projectRoot: projectRoot,
                        onSendToChat: onIssue ?? (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a single device starts without asking', (tester) async {
    final runner = _FakeRunner(
      devicesJson: '[{"name":"macOS","id":"macos","targetPlatform":"darwin"}]',
    );
    await pump(tester, runner);

    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await settle(tester);

    expect(find.text('Pick a device to run on'), findsNothing);
    expect(runner.startedArguments, ['run', '-d', 'macos']);
    expect(find.byKey(const ValueKey('flutter-run-stop')), findsOneWidget);
  });

  testWidgets('several devices open the picker sheet', (tester) async {
    final runner = _FakeRunner(
      devicesJson:
          '[{"name":"macOS","id":"macos","targetPlatform":"darwin"},'
          '{"name":"iPhone 16","id":"sim-1","targetPlatform":"ios",'
          '"emulator":true}]',
    );
    await pump(tester, runner);

    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await settle(tester);

    expect(find.text('Pick a device to run on'), findsOneWidget);
    expect(runner.startedArguments, isNull);

    await tester.tap(find.byKey(const ValueKey('flutter-run-device-sim-1')));
    await tester.pumpAndSettle();

    expect(runner.startedArguments, ['run', '-d', 'sim-1']);
  });

  testWidgets('the picker still opens when the dock opens first', (
    tester,
  ) async {
    // Reported from the app: the run listed devices into the log and then did
    // nothing. Opening the dock re-parents this subtree, so a picker shown
    // from the pre-await context is shown from an unmounted element.
    final runner = _FakeRunner(
      devicesJson:
          '[{"name":"macOS","id":"macos","targetPlatform":"darwin"},'
          '{"name":"iPhone 16","id":"sim-1","targetPlatform":"ios"}]',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          flutterRunProcessRunnerProvider.overrideWithValue(runner),
          flutterRunCommandBuilderProvider.overrideWithValue(
            const FlutterRunCommandBuilder(usesFvm: _noFvm),
          ),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          useOnlyLangCode: true,
          saveLocale: false,
          assetLoader: const _TestTranslationLoader(),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Scaffold(
                body: CodingTerminalDock(
                  workingDirectory: null,
                  threadId: 'thread-a',
                  runProjectRoot: projectRoot,
                  onSendIssueToChat: (_) {},
                  child: const FlutterRunControlSection(
                    projectRoot: projectRoot,
                    threadId: 'thread-a',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await settle(tester);

    expect(find.text('Pick a device to run on'), findsOneWidget);
  });

  testWidgets('run output reaches the bottom log panel', (tester) async {
    final runner = _FakeRunner(
      devicesJson: '[{"name":"macOS","id":"macos","targetPlatform":"darwin"}]',
    );
    await pump(tester, runner);

    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await settle(tester);
    runner.handle.emitStdout('Syncing files to macOS...');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flutter-run-log-view')), findsOneWidget);
    expect(find.text('Syncing files to macOS...'), findsOneWidget);
    expect(find.text(r'$ flutter run -d macos'), findsOneWidget);
  });

  testWidgets('stop asks the run to quit', (tester) async {
    final runner = _FakeRunner(
      devicesJson: '[{"name":"macOS","id":"macos","targetPlatform":"darwin"}]',
    );
    await pump(tester, runner);
    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('flutter-run-stop')));
    await tester.pump();
    runner.handle.exit(0);
    await tester.pumpAndSettle();

    expect(runner.handle.stdinWrites, ['q']);
    expect(find.byKey(const ValueKey('flutter-run-start')), findsOneWidget);
  });

  testWidgets('a failure in the output becomes an issue row', (tester) async {
    // End to end through the panel: the block is segmented, listed before any
    // analysis, and handed to the conversation with its evidence.
    final runner = _FakeRunner(
      devicesJson: '[{"name":"macOS","id":"macos","targetPlatform":"darwin"}]',
    );
    String? prompt;
    await pump(tester, runner, onIssue: (issue) => prompt = issue.evidence);
    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await settle(tester);

    for (final line in const [
      '══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════',
      'The following assertion was thrown during layout:',
      'A RenderFlex overflowed by 42 pixels on the right.',
      '  Row Row:file:///Users/dev/app/lib/home_page.dart:64:16',
      '════════════════════════════════════════════════════════════════',
    ]) {
      runner.handle.emitStdout(line);
    }
    await tester.pumpAndSettle();

    // Both panes are mounted side by side here; in the dock only one shows at
    // a time, so the assertion is scoped to the issue list.
    expect(
      find.descendant(
        of: find.byType(FlutterRunIssueList),
        matching: find.text(
          'The following assertion was thrown during layout:',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('not analysed yet'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(FlutterRunIssueList),
        matching: find.textContaining('assertion was thrown'),
      ),
    );
    await tester.pumpAndSettle();
    // The action sits below the fold of the 200px panel.
    await tester.ensureVisible(find.text('Ask in chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask in chat'));
    await tester.pumpAndSettle();

    expect(prompt, contains('A RenderFlex overflowed by 42 pixels'));
  });

  testWidgets('a device listing failure is shown, not swallowed', (
    tester,
  ) async {
    final runner = _FakeRunner(
      devicesJson: '',
      devicesExitCode: 1,
      devicesStderr: 'No pubspec.yaml file found.',
    );
    await pump(tester, runner);

    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await settle(tester);

    // Twice over now: once as the panel's status line, once as the log line
    // the tool actually printed.
    expect(find.text('No pubspec.yaml file found.'), findsWidgets);
  });
}

bool _noFvm(String projectRoot) => false;

class _FakeRunner implements FlutterRunProcessRunner {
  _FakeRunner({
    required this.devicesJson,
    this.devicesExitCode = 0,
    this.devicesStderr = '',
  });

  final String devicesJson;
  final int devicesExitCode;
  final String devicesStderr;
  final handle = _FakeHandle();
  final listingHandle = _FakeHandle();

  List<String>? startedArguments;

  @override
  Future<FlutterRunCommandOutput> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async => throw UnimplementedError('the listing streams like the run');

  @override
  Future<FlutterRunProcessHandle> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    if (arguments.contains('devices')) {
      // After the caller has attached its listeners, as a real process would.
      scheduleMicrotask(() {
        if (devicesJson.isNotEmpty) listingHandle.emitStdout(devicesJson);
        if (devicesStderr.isNotEmpty) listingHandle.emitStderr(devicesStderr);
        listingHandle.exit(devicesExitCode);
      });
      return listingHandle;
    }
    startedArguments = arguments;
    return handle;
  }
}

class _FakeHandle implements FlutterRunProcessHandle {
  // Single-subscription like a real process pipe: output written before the
  // reader attaches is buffered, not dropped.
  final _stdout = StreamController<String>();
  final _stderr = StreamController<String>();
  final _exit = Completer<int>();
  final stdinWrites = <String>[];

  void emitStdout(String line) => _stdout.add(line);

  void emitStderr(String line) => _stderr.add(line);

  void exit(int code) {
    if (_exit.isCompleted) return;
    // A real process closes its pipes when it exits.
    _stdout.close();
    _stderr.close();
    _exit.complete(code);
  }

  @override
  Stream<String> get stdoutLines => _stdout.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(String input) => stdinWrites.add(input);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    exit(-15);
    return true;
  }
}
