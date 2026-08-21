import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/widgets/message_video_io.dart';
import 'package:caverno/features/chat/presentation/widgets/message_video_playback.dart';
import 'package:caverno/features/chat/presentation/widgets/message_video_viewer.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return jsonDecode(
      File('$path/${locale.languageCode}.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  }
}

Future<void> _pumpViewer(
  WidgetTester tester, {
  required MessageVideoIo io,
  bool supportsPlayback = false,
  String? filePath = '/tmp/clip.mov',
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
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: MessageVideoViewer(
            filePath: filePath,
            url: filePath == null ? 'https://cdn.example.com/clip.mp4' : null,
            fileName: 'clip.mov',
            mimeType: 'video/quicktime',
            sizeBytes: 7932096,
            io: io,
            supportsPlayback: () => supportsPlayback,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('offers saving even where playback is unavailable', (
    tester,
  ) async {
    // Windows and Linux have no player. Withholding the download there would
    // leave the attachment unreachable rather than merely unplayable.
    var saved = 0;
    await _pumpViewer(
      tester,
      io: MessageVideoIo(
        isMobile: () => false,
        saveFile: ({required sourcePath, required fileName, dialogTitle}) async {
          saved++;
          return '/tmp/out.mov';
        },
      ),
    );

    expect(
      find.text('Playback is not available on this platform. '
          'You can still save the video.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('message-video-viewer-download')));
    await tester.pumpAndSettle();

    expect(saved, 1);
    expect(find.text('Video saved'), findsOneWidget);
  });

  testWidgets('reports a save that failed rather than looking done', (
    tester,
  ) async {
    await _pumpViewer(
      tester,
      io: MessageVideoIo(
        isMobile: () => false,
        saveFile: ({required sourcePath, required fileName, dialogTitle}) async {
          throw const FileSystemException('disk full');
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message-video-viewer-download')));
    await tester.pumpAndSettle();

    expect(find.text('Could not save the video'), findsOneWidget);
  });

  testWidgets('a cancelled save says nothing at all', (tester) async {
    await _pumpViewer(
      tester,
      io: MessageVideoIo(
        isMobile: () => false,
        saveFile: ({required sourcePath, required fileName, dialogTitle}) async =>
            null,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message-video-viewer-download')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a video that is only a URL has nothing to save', (tester) async {
    // There is no local file behind a typed URL, so a save button would be a
    // control that cannot do anything.
    await _pumpViewer(
      tester,
      filePath: null,
      io: const MessageVideoIo(),
    );

    expect(
      find.byKey(const ValueKey('message-video-viewer-download')),
      findsNothing,
    );
  });

  testWidgets('shows the file name and size', (tester) async {
    await _pumpViewer(tester, io: const MessageVideoIo());

    expect(find.text('clip.mov'), findsOneWidget);
    expect(find.text('7.6 MB'), findsOneWidget);
  });

  group('formatPlaybackPosition', () {
    test('counts in minutes below an hour', () {
      expect(formatPlaybackPosition(Duration.zero), '0:00');
      expect(formatPlaybackPosition(const Duration(seconds: 7)), '0:07');
      expect(
        formatPlaybackPosition(const Duration(minutes: 3, seconds: 5)),
        '3:05',
      );
    });

    test('adds hours once it runs that long', () {
      expect(
        formatPlaybackPosition(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '1:02:03',
      );
    });
  });
}
