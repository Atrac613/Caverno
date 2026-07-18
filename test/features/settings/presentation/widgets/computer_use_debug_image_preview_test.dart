import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=';

void main() {
  const tapAreaKey = ValueKey('preview-tap-area');

  Future<void> pumpPreview(
    WidgetTester tester, {
    required ComputerUseDebugImageSnapshot snapshot,
    bool active = true,
    ValueChanged<ComputerUseDebugImagePoint>? onPointSelected,
    double width = 400,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ComputerUseDebugImagePreview(
                snapshot: snapshot,
                active: active,
                tapAreaKey: tapAreaKey,
                onPointSelected: onPointSelected,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const validSnapshot = ComputerUseDebugImageSnapshot(
    title: 'Display screenshot',
    base64: _png1x1Base64,
    width: 200,
    height: 100,
    mimeType: 'image/png',
  );

  testWidgets('renders metadata and the existing interactive image contract', (
    tester,
  ) async {
    await pumpPreview(tester, snapshot: validSnapshot);

    expect(
      find.text('Display screenshot (200x100, image/png)'),
      findsOneWidget,
    );
    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, 2);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, 0.5);
    expect(viewer.maxScale, 4);
    expect(viewer.transformationController, isNotNull);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(image.gaplessPlayback, isTrue);

    final constrainedBox = tester.widget<ConstrainedBox>(
      find.descendant(
        of: find.byType(ComputerUseDebugImagePreview),
        matching: find.byType(ConstrainedBox),
      ),
    );
    expect(constrainedBox.constraints.maxHeight, 420);
  });

  testWidgets('uses active and inactive border colors without changing width', (
    tester,
  ) async {
    Future<Border> borderFor(bool active) async {
      await pumpPreview(tester, snapshot: validSnapshot, active: active);
      final decoratedBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(ComputerUseDebugImagePreview),
          matching: find.byType(DecoratedBox),
        ),
      );
      return (decoratedBox.decoration as BoxDecoration).border! as Border;
    }

    final activeBorder = await borderFor(true);
    final activeContext = tester.element(
      find.byType(ComputerUseDebugImagePreview),
    );
    expect(activeBorder.top.width, 2);
    expect(activeBorder.top.color, Theme.of(activeContext).colorScheme.primary);

    final inactiveBorder = await borderFor(false);
    final inactiveContext = tester.element(
      find.byType(ComputerUseDebugImagePreview),
    );
    expect(inactiveBorder.top.width, 2);
    expect(inactiveBorder.top.color, Theme.of(inactiveContext).dividerColor);
  });

  testWidgets('uses the fallback aspect ratio for non-positive dimensions', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      snapshot: const ComputerUseDebugImageSnapshot(
        title: 'Unknown size',
        base64: _png1x1Base64,
        width: 0,
        height: -1,
        mimeType: 'image/png',
      ),
    );

    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      16 / 9,
    );
  });

  testWidgets('maps transformed taps to clamped source-image coordinates', (
    tester,
  ) async {
    final points = <ComputerUseDebugImagePoint>[];
    await pumpPreview(
      tester,
      snapshot: const ComputerUseDebugImageSnapshot(
        title: 'Coordinate source',
        base64: _png1x1Base64,
        width: 400,
        height: 200,
        mimeType: 'image/png',
      ),
      width: 200,
      onPointSelected: points.add,
    );

    final tapArea = find.byKey(tapAreaKey);
    final tapRect = tester.getRect(tapArea);
    await tester.tapAt(tapRect.center);
    expect(points.last.x, closeTo(200, 0.001));
    expect(points.last.y, closeTo(100, 0.001));

    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.translationValues(tapRect.width * 2, 0, 0);
    await tester.tapAt(tapRect.center);
    expect(points.last.x, 0);

    controller.value = Matrix4.translationValues(-tapRect.width * 2, 0, 0);
    await tester.tapAt(tapRect.center);
    expect(points.last.x, 400);
  });

  testWidgets(
    'disables taps without a callback and ignores invalid dimensions',
    (tester) async {
      await pumpPreview(tester, snapshot: validSnapshot);
      expect(
        tester.widget<GestureDetector>(find.byKey(tapAreaKey)).onTapDown,
        isNull,
      );

      var selectionCount = 0;
      await pumpPreview(
        tester,
        snapshot: const ComputerUseDebugImageSnapshot(
          title: 'Invalid dimensions',
          base64: _png1x1Base64,
          width: 0,
          height: 100,
          mimeType: 'image/png',
        ),
        onPointSelected: (_) => selectionCount++,
      );
      await tester.tap(find.byKey(tapAreaKey));
      expect(selectionCount, 0);
    },
  );

  testWidgets('shows distinct base64 and image decoder failures', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      snapshot: const ComputerUseDebugImageSnapshot(
        title: 'Invalid base64',
        base64: '%not-base64%',
        width: 1,
        height: 1,
        mimeType: 'image/png',
      ),
    );
    expect(find.text('Failed to decode image payload.'), findsOneWidget);

    await pumpPreview(
      tester,
      snapshot: const ComputerUseDebugImageSnapshot(
        title: 'Invalid image',
        base64: 'AQID',
        width: 1,
        height: 1,
        mimeType: 'image/png',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to decode image:'), findsOneWidget);
  });
}
