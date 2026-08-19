import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:caverno/features/chat/presentation/widgets/message_image_io.dart';
import 'package:caverno/features/chat/presentation/widgets/message_image_viewer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final localeName = locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final file = File('$path/$localeName.json');
    final fallbackFile = File('$path/${locale.languageCode}.json');
    final source = file.existsSync() ? file : fallbackFile;
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

const _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUl'
    'EQVR42mP8z8BQDwAFgwJ/lA0T8QAAAABJRU5ErkJggg==';

Uint8List get _pngBytes => base64Decode(_png1x1Base64);

Future<void> _pumpViewer(
  WidgetTester tester, {
  required Uint8List previewBytes,
  String? previewMimeType,
  String? originalImagePath,
  String? originalMimeType,
  String? suggestedFileName,
  MessageImageIo io = const MessageImageIo(),
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoader(),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: MessageImageViewer(
              previewBytes: previewBytes,
              previewMimeType: previewMimeType,
              originalImagePath: originalImagePath,
              originalMimeType: originalMimeType,
              suggestedFileName: suggestedFileName,
              io: io,
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('renders a zoomable image viewer with copy and download actions', (
    tester,
  ) async {
    await _pumpViewer(
      tester,
      previewBytes: _pngBytes,
      previewMimeType: 'image/png',
    );

    expect(find.byKey(kMessageImageViewerKey), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 8);
    expect(find.byTooltip('Copy image'), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('copy action writes the displayed bytes', (tester) async {
    Uint8List? copiedBytes;
    String? copiedMime;
    await _pumpViewer(
      tester,
      previewBytes: _pngBytes,
      previewMimeType: 'image/png',
      io: MessageImageIo(
        copyImage: (bytes, mimeType) async {
          copiedBytes = bytes;
          copiedMime = mimeType;
        },
      ),
    );

    await tester.tap(find.byTooltip('Copy image'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(copiedBytes, _pngBytes);
    expect(copiedMime, 'image/png');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
  });

  testWidgets('download action saves the displayed bytes', (tester) async {
    Uint8List? savedBytes;
    String? savedName;
    String? savedMime;
    await _pumpViewer(
      tester,
      previewBytes: _pngBytes,
      previewMimeType: 'image/png',
      suggestedFileName: 'shot.png',
      io: MessageImageIo(
        saveImage:
            ({
              required bytes,
              required fileName,
              required mimeType,
              dialogTitle,
            }) async {
              savedBytes = bytes;
              savedName = fileName;
              savedMime = mimeType;
              return '/tmp/$fileName';
            },
      ),
    );

    await tester.tap(find.byTooltip('Download'));
    await tester.pumpAndSettle();

    expect(savedBytes, _pngBytes);
    expect(savedName, 'shot.png');
    expect(savedMime, 'image/png');
    expect(find.text('Image saved'), findsOneWidget);
  });

  testWidgets('replaces the preview with original file bytes when present', (
    tester,
  ) async {
    final originalBytes = Uint8List.fromList([9, 8, 7, 6]);
    Uint8List? copiedBytes;
    String? copiedMime;
    await _pumpViewer(
      tester,
      previewBytes: _pngBytes,
      previewMimeType: 'image/png',
      originalImagePath: '/tmp/original.jpg',
      originalMimeType: 'image/jpeg',
      io: MessageImageIo(
        readFileBytes: (path) async {
          expect(path, '/tmp/original.jpg');
          return originalBytes;
        },
        copyImage: (bytes, mimeType) async {
          copiedBytes = bytes;
          copiedMime = mimeType;
        },
      ),
    );

    await tester.tap(find.byTooltip('Copy image'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(copiedBytes, originalBytes);
    expect(copiedMime, 'image/jpeg');

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
  });

  testWidgets('close action pops the viewer route', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        saveLocale: false,
        assetLoader: const _TestTranslationLoader(),
        child: Builder(
          builder: (context) {
            return MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Builder(
                builder: (context) {
                  return Scaffold(
                    body: TextButton(
                      onPressed: () {
                        showMessageImageViewer(
                          context: context,
                          previewBytes: _pngBytes,
                          previewMimeType: 'image/png',
                        );
                      },
                      child: const Text('Open'),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(kMessageImageViewerKey), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(kMessageImageViewerKey), findsNothing);
  });
}
