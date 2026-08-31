import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/widgets/chat_media_drop_target.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('supported image drop invokes callback', (tester) async {
    Uint8List? droppedBytes;
    String? droppedMimeType;
    String? droppedFilePath;
    await _pumpHarness(
      tester,
      onImageDropped: (bytes, mimeType, filePath) {
        droppedBytes = bytes;
        droppedMimeType = mimeType;
        droppedFilePath = filePath;
      },
    );
    await tester.pumpAndSettle();

    final state = tester.state<ChatMediaDropTargetState>(
      find.byType(ChatMediaDropTarget),
    );
    await state.handleDrop([
      DropItemFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'photo.png',
        path: '/tmp/photo.png',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(droppedBytes, Uint8List.fromList([1, 2, 3]));
    expect(droppedMimeType, 'image/png');
    expect(droppedFilePath, '/tmp/photo.png');
  });

  testWidgets('PDF drop hands over the path', (tester) async {
    String? droppedPath;
    await _pumpHarness(
      tester,
      onImageDropped: (_, _, _) {},
      onFileDropped: (filePath) => droppedPath = filePath,
    );
    await tester.pumpAndSettle();

    final state = tester.state<ChatMediaDropTargetState>(
      find.byType(ChatMediaDropTarget),
    );
    await state.handleDrop([
      DropItemFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'report.pdf',
        path: '/tmp/report.pdf',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(droppedPath, '/tmp/report.pdf');
  });

  testWidgets('an image still wins over the document handler', (tester) async {
    String? droppedFilePath;
    String? droppedImagePath;
    await _pumpHarness(
      tester,
      onImageDropped: (_, _, filePath) => droppedImagePath = filePath,
      onFileDropped: (filePath) => droppedFilePath = filePath,
    );
    await tester.pumpAndSettle();

    final state = tester.state<ChatMediaDropTargetState>(
      find.byType(ChatMediaDropTarget),
    );
    await state.handleDrop([
      DropItemFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'photo.png',
        path: '/tmp/photo.png',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(droppedImagePath, '/tmp/photo.png');
    expect(droppedFilePath, isNull);
  });

  testWidgets('a document type the picker refuses shows the snackbar', (
    tester,
  ) async {
    var dropped = false;
    await _pumpHarness(
      tester,
      onImageDropped: (_, _, _) {},
      onFileDropped: (_) => dropped = true,
    );
    await tester.pumpAndSettle();

    final state = tester.state<ChatMediaDropTargetState>(
      find.byType(ChatMediaDropTarget),
    );
    await state.handleDrop([
      DropItemFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'archive.zip',
        path: '/tmp/archive.zip',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(dropped, isFalse);
    expect(
      find.text('Drop an image, a video, a text file or a PDF'),
      findsOneWidget,
    );
  });

  testWidgets('unsupported drop shows snackbar without invoking callback', (
    tester,
  ) async {
    var dropped = false;
    await _pumpHarness(
      tester,
      onImageDropped: (_, _, _) {
        dropped = true;
      },
    );
    await tester.pumpAndSettle();

    final state = tester.state<ChatMediaDropTargetState>(
      find.byType(ChatMediaDropTarget),
    );
    await state.handleDrop([
      DropItemFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'text/plain',
        name: 'notes.txt',
        path: '/tmp/notes.txt',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(dropped, isFalse);
    expect(find.text('Drop an image, a video, a text file or a PDF'), findsOneWidget);
  });

  testWidgets('video drop hands over the path, not the bytes', (tester) async {
    String? droppedPath;
    String? droppedMimeType;
    await _pumpHarness(
      tester,
      videoEnabled: true,
      onImageDropped: (_, _, _) {},
      onVideoDropped: (filePath, mimeType) {
        droppedPath = filePath;
        droppedMimeType = mimeType;
      },
    );
    await tester.pumpAndSettle();

    final state = tester.state<ChatMediaDropTargetState>(
      find.byType(ChatMediaDropTarget),
    );
    await state.handleDrop([
      DropItemFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'clip.mov',
        path: '/tmp/clip.mov',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(droppedPath, '/tmp/clip.mov');
    expect(droppedMimeType, 'video/quicktime');
  });

  testWidgets('video drop is refused when the endpoint cannot take one', (
    tester,
  ) async {
    var dropped = false;
    await _pumpHarness(
      tester,
      onImageDropped: (_, _, _) {},
      onVideoDropped: (_, _) => dropped = true,
    );
    await tester.pumpAndSettle();

    final state = tester.state<ChatMediaDropTargetState>(
      find.byType(ChatMediaDropTarget),
    );
    await state.handleDrop([
      DropItemFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'clip.mp4',
        path: '/tmp/clip.mp4',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(dropped, isFalse);
    expect(find.text('Drop an image, a video, a text file or a PDF'), findsOneWidget);
  });
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required void Function(Uint8List bytes, String mimeType, String filePath)
  onImageDropped,
  void Function(String filePath, String mimeType)? onVideoDropped,
  void Function(String filePath)? onFileDropped,
  bool videoEnabled = false,
}) {
  return tester.pumpWidget(
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
            home: Scaffold(
              body: ChatMediaDropTarget(
                enabled: true,
                onImageDropped: onImageDropped,
                onVideoDropped: onVideoDropped,
                onFileDropped: onFileDropped,
                videoEnabled: videoEnabled,
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    ),
  );
}
