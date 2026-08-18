import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/html_preview_session_controller.dart';
import 'package:caverno/features/chat/domain/services/html_preview_static_server.dart';
import 'package:caverno/features/chat/domain/services/html_project_detector.dart';
import 'package:caverno/features/chat/presentation/providers/html_preview_provider.dart';
import 'package:caverno/features/chat/presentation/widgets/html_preview_control_section.dart';

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

  testWidgets('run opens the preview and stop returns to idle', (tester) async {
    final panel = _FakePanel();
    final server = _FakeServer();
    Uri? opened;
    final controller = HtmlPreviewSessionController(
      openPreview: (url) async {
        opened = url;
        panel.open = true;
        panel.notifyListeners();
      },
      closePreview: () async {
        panel.open = false;
        panel.notifyListeners();
      },
      panel: panel,
      isPanelOpen: () => panel.open,
      isPlatformSupported: () => true,
      createServer: () => server,
      detector: const _FixedDetector(
        HtmlProjectEntry(
          absolutePath: '/work/sea/index.html',
          relativePath: 'index.html',
        ),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          htmlPreviewControllerProvider.overrideWithValue(controller),
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
                body: HtmlPreviewControlSection(projectRoot: '/work/sea'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('html-preview-start')));
    await tester.pumpAndSettle();

    expect(opened.toString(), 'http://127.0.0.1:4321/index.html');
    expect(find.byKey(const ValueKey('html-preview-stop')), findsOneWidget);
    expect(find.text('index.html'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('html-preview-stop')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('html-preview-start')), findsOneWidget);
    expect(server.stopped, isTrue);
  });
}

class _FakePanel extends ChangeNotifier {
  bool open = false;
}

class _FixedDetector extends HtmlProjectDetector {
  const _FixedDetector(this.entry);

  final HtmlProjectEntry entry;

  @override
  HtmlProjectEntry? detect(String projectRoot) => entry;
}

class _FakeServer implements HtmlPreviewStaticServer {
  bool stopped = false;

  @override
  Uri? get origin => Uri.parse('http://127.0.0.1:4321');

  @override
  bool get isRunning => !stopped;

  @override
  Future<Uri> start({required String projectRoot}) async {
    stopped = false;
    return origin!;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
