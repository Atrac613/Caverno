import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:caverno/features/chat/presentation/widgets/message_video_poster.dart';

/// Stands in for the platform player, which has no implementation under
/// `flutter_test`.
class _FakeController extends VideoPlayerController {
  _FakeController({this.failInitialize = false, this.duration = const Duration(seconds: 8)})
    : super.networkUrl(Uri.parse('https://example.test/clip.mp4'));

  final bool failInitialize;
  final Duration duration;

  Duration? seekedTo;
  bool disposed = false;
  bool played = false;

  @override
  Future<void> initialize() async {
    if (failInitialize) throw StateError('no decoder here');
    value = VideoPlayerValue(
      duration: duration,
      size: const Size(640, 480),
      isInitialized: true,
    );
  }

  @override
  Future<void> seekTo(Duration position) async => seekedTo = position;

  @override
  Future<void> play() async => played = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required VideoPlayerController Function() controller,
  bool supportsPlayback = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: MessageVideoPoster(
          filePath: '/tmp/clip.mp4',
          width: 200,
          height: 140,
          placeholder: const ColoredBox(
            key: ValueKey('placeholder'),
            color: Colors.black12,
          ),
          controllerFactory: ({file, url}) => controller(),
          supportsPlayback: () => supportsPlayback,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a frame from a second in, without playing', (
    tester,
  ) async {
    final fake = _FakeController();
    await _pump(tester, controller: () => fake);

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);
    expect(fake.seekedTo, MessageVideoPoster.posterFrameAt);
    expect(
      fake.played,
      isFalse,
      reason: 'a poster that plays is a decode loop per visible bubble',
    );
  });

  testWidgets('a clip shorter than the seek point keeps its first frame', (
    tester,
  ) async {
    final fake = _FakeController(duration: const Duration(milliseconds: 400));
    await _pump(tester, controller: () => fake);

    expect(fake.seekedTo, isNull);
    expect(find.byType(VideoPlayer), findsOneWidget);
  });

  testWidgets('keeps the placeholder when no frame can be read', (
    tester,
  ) async {
    final fake = _FakeController(failInitialize: true);
    await _pump(tester, controller: () => fake);

    expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(fake.disposed, isTrue, reason: 'a failed controller must be freed');
  });

  testWidgets('does not open a player where playback is unsupported', (
    tester,
  ) async {
    var built = 0;
    await _pump(
      tester,
      supportsPlayback: false,
      controller: () {
        built++;
        return _FakeController();
      },
    );

    expect(built, 0);
    expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
  });

  testWidgets('frees the controller when scrolled out of the tree', (
    tester,
  ) async {
    // Posters are re-created as a long conversation scrolls, so a leaked
    // controller here is a decoder per video ever seen.
    final fake = _FakeController();
    await _pump(tester, controller: () => fake);
    expect(fake.disposed, isFalse);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    expect(fake.disposed, isTrue);
  });
}
