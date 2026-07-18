import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_display_screenshot_card.dart';
import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('view model derives capture eligibility only from busy state', () {
    const idle = ComputerUseDebugDisplayScreenshotViewModel(
      isBusy: false,
      snapshot: null,
      isPreviewActive: false,
    );
    const busyWithPreview = ComputerUseDebugDisplayScreenshotViewModel(
      isBusy: true,
      snapshot: _snapshot,
      isPreviewActive: true,
    );

    expect(idle.canCapture, isTrue);
    expect(busyWithPreview.canCapture, isFalse);
  });

  testWidgets('idle state reuses controller and dispatches capture', (
    tester,
  ) async {
    final controller = TextEditingController(text: '640');
    addTearDown(controller.dispose);
    var captures = 0;
    await _pump(
      tester,
      viewModel: const ComputerUseDebugDisplayScreenshotViewModel(
        isBusy: false,
        snapshot: null,
        isPreviewActive: false,
      ),
      maxWidthController: controller,
      onCapture: () => captures += 1,
    );

    expect(find.text('Display Screenshot'), findsOneWidget);
    expect(
      find.text('Capture the main display and preview the PNG payload.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.desktop_mac_outlined), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    expect(find.text('Max image width'), findsOneWidget);
    expect(find.text('640'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller, same(controller));
    expect(field.keyboardType, TextInputType.number);
    expect(
      find.byKey(const ValueKey('computer-use-display-preview')),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Capture Display'));
    await tester.pump();
    expect(captures, 1);
  });

  testWidgets('preview preserves keys and dispatches selected source point', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1200');
    addTearDown(controller.dispose);
    ComputerUseDebugImagePoint? selectedPoint;
    await _pump(
      tester,
      viewModel: const ComputerUseDebugDisplayScreenshotViewModel(
        isBusy: false,
        snapshot: _snapshot,
        isPreviewActive: false,
      ),
      maxWidthController: controller,
      onPointSelected: (point) => selectedPoint = point,
    );

    expect(
      find.byKey(const ValueKey('computer-use-display-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('computer-use-display-preview-tap-area')),
      findsOneWidget,
    );
    final preview = tester.widget<ComputerUseDebugImagePreview>(
      find.byType(ComputerUseDebugImagePreview),
    );
    expect(preview.active, isFalse);

    preview.onPointSelected!(const ComputerUseDebugImagePoint(3, 4));
    expect(selectedPoint?.x, 3);
    expect(selectedPoint?.y, 4);
  });

  testWidgets('busy active preview disables capture without hiding image', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1200');
    addTearDown(controller.dispose);
    var captures = 0;
    await _pump(
      tester,
      viewModel: const ComputerUseDebugDisplayScreenshotViewModel(
        isBusy: true,
        snapshot: _snapshot,
        isPreviewActive: true,
      ),
      maxWidthController: controller,
      onCapture: () => captures += 1,
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Capture Display'),
    );
    final preview = tester.widget<ComputerUseDebugImagePreview>(
      find.byType(ComputerUseDebugImagePreview),
    );
    expect(button.onPressed, isNull);
    expect(preview.active, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Capture Display'));
    await tester.pump();
    expect(captures, 0);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ComputerUseDebugDisplayScreenshotViewModel viewModel,
  required TextEditingController maxWidthController,
  VoidCallback? onCapture,
  ValueChanged<ComputerUseDebugImagePoint>? onPointSelected,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 800,
            child: ComputerUseDebugDisplayScreenshotCard(
              viewModel: viewModel,
              maxWidthController: maxWidthController,
              onCapture: onCapture ?? () {},
              onPointSelected: onPointSelected ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

const _snapshot = ComputerUseDebugImageSnapshot(
  title: 'Display screenshot',
  base64:
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
  width: 1,
  height: 1,
  mimeType: 'image/png',
);
