import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/flutter_run_process_runner.dart';
import 'package:caverno/features/chat/domain/services/flutter_run_command_builder.dart';
import 'package:caverno/features/chat/presentation/providers/flutter_run_provider.dart';
import 'package:caverno/features/chat/presentation/widgets/flutter_run_control_section.dart';
import 'package:caverno/features/chat/presentation/widgets/flutter_run_log_panel.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  const projectRoot = '/work/app';

  Future<void> pump(WidgetTester tester, _FakeRunner runner) async {
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
              home: const Scaffold(
                body: Column(
                  children: [
                    FlutterRunControlSection(projectRoot: projectRoot),
                    FlutterRunLogPanel(projectRoot: projectRoot),
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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(find.text('Pick a device to run on'), findsOneWidget);
    expect(runner.startedArguments, isNull);

    await tester.tap(find.byKey(const ValueKey('flutter-run-device-sim-1')));
    await tester.pumpAndSettle();

    expect(runner.startedArguments, ['run', '-d', 'sim-1']);
  });

  testWidgets('run output reaches the bottom log panel', (tester) async {
    final runner = _FakeRunner(
      devicesJson: '[{"name":"macOS","id":"macos","targetPlatform":"darwin"}]',
    );
    await pump(tester, runner);
    expect(find.byKey(const ValueKey('flutter-run-log-panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await tester.pumpAndSettle();
    runner.handle.emitStdout('Syncing files to macOS...');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flutter-run-log-panel')), findsOneWidget);
    expect(find.text('Syncing files to macOS...'), findsOneWidget);
    expect(find.text(r'$ flutter run -d macos'), findsOneWidget);
  });

  testWidgets('stop asks the run to quit', (tester) async {
    final runner = _FakeRunner(
      devicesJson: '[{"name":"macOS","id":"macos","targetPlatform":"darwin"}]',
    );
    await pump(tester, runner);
    await tester.tap(find.byKey(const ValueKey('flutter-run-start')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('flutter-run-stop')));
    await tester.pump();
    runner.handle.exit(0);
    await tester.pumpAndSettle();

    expect(runner.handle.stdinWrites, ['q']);
    expect(find.byKey(const ValueKey('flutter-run-start')), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(find.text('No pubspec.yaml file found.'), findsOneWidget);
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

  List<String>? startedArguments;

  @override
  Future<FlutterRunCommandOutput> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    return FlutterRunCommandOutput(
      exitCode: devicesExitCode,
      stdout: devicesJson,
      stderr: devicesStderr,
    );
  }

  @override
  Future<FlutterRunProcessHandle> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    startedArguments = arguments;
    return handle;
  }
}

class _FakeHandle implements FlutterRunProcessHandle {
  final _stdout = StreamController<String>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final _exit = Completer<int>();
  final stdinWrites = <String>[];

  void emitStdout(String line) => _stdout.add(line);

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
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
