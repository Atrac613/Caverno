import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_image_preview.dart';
import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_window_targeting_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('view model takes an unmodifiable item snapshot', () {
    final source = <ComputerUseDebugWindowItem>[_terminal];
    final viewModel = ComputerUseDebugWindowViewModel(
      isBusy: false,
      windows: source,
      selectedWindowId: 42,
      snapshot: null,
      isPreviewActive: false,
    );

    source.add(_browser);

    expect(viewModel.windows, [_terminal]);
    expect(viewModel.selectedWindow, same(_terminal));
    expect(() => viewModel.windows.add(_browser), throwsUnsupportedError);
    expect(viewModel.canListWindows, isTrue);
    expect(viewModel.canFocusSelected, isTrue);
    expect(viewModel.canCaptureSelected, isTrue);
    expect(viewModel.canSelectWindow, isTrue);
  });

  testWidgets('empty state enables only list and hides selection controls', (
    tester,
  ) async {
    var lists = 0;
    await _pump(
      tester,
      viewModel: ComputerUseDebugWindowViewModel(
        isBusy: false,
        windows: const [],
        selectedWindowId: null,
        snapshot: null,
        isPreviewActive: false,
      ),
      onListWindows: () => lists += 1,
    );

    expect(find.text('Window Targeting'), findsOneWidget);
    expect(
      find.text(
        'List visible windows, focus one, and capture a window-relative screenshot.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.web_asset_outlined), findsOneWidget);
    expect(_button(tester, 'List Windows').onPressed, isNotNull);
    expect(_button(tester, 'Focus Selected').onPressed, isNull);
    expect(_button(tester, 'Capture Selected').onPressed, isNull);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(
      find.byKey(const ValueKey('computer-use-window-preview')),
      findsNothing,
    );

    _button(tester, 'List Windows').onPressed!();
    expect(lists, 1);
  });

  testWidgets('selected preview dispatches actions, selection, and points', (
    tester,
  ) async {
    final calls = <String>[];
    int? selectedId;
    ComputerUseDebugImagePoint? selectedPoint;
    await _pump(
      tester,
      viewModel: ComputerUseDebugWindowViewModel(
        isBusy: false,
        windows: const [_terminal, _browser],
        selectedWindowId: 42,
        snapshot: _snapshot,
        isPreviewActive: false,
      ),
      onListWindows: () => calls.add('list'),
      onFocusSelected: () => calls.add('focus'),
      onCaptureSelected: () => calls.add('capture'),
      onSelectedWindowChanged: (value) => selectedId = value,
      onPointSelected: (point) => selectedPoint = point,
    );

    expect(find.text(_terminal.label), findsOneWidget);
    expect(find.text(_terminal.boundsLabel), findsOneWidget);
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    final dropdownButton = tester.widget<DropdownButton<int>>(
      find.descendant(
        of: find.byType(DropdownButtonFormField<int>),
        matching: find.byType(DropdownButton<int>),
      ),
    );
    expect(dropdown.initialValue, 42);
    expect(dropdownButton.isExpanded, isTrue);
    expect(dropdown.onChanged, isNotNull);

    _button(tester, 'List Windows').onPressed!();
    _button(tester, 'Focus Selected').onPressed!();
    _button(tester, 'Capture Selected').onPressed!();
    dropdown.onChanged!(43);
    final preview = tester.widget<ComputerUseDebugImagePreview>(
      find.byType(ComputerUseDebugImagePreview),
    );
    preview.onPointSelected!(const ComputerUseDebugImagePoint(3, 4));

    expect(calls, ['list', 'focus', 'capture']);
    expect(selectedId, 43);
    expect(selectedPoint?.x, 3);
    expect(selectedPoint?.y, 4);
    expect(preview.active, isFalse);
    final actionWrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(actionWrap.children[0], same(_button(tester, 'List Windows')));
    expect(actionWrap.children[1], same(_button(tester, 'Focus Selected')));
    expect(actionWrap.children[2], same(_button(tester, 'Capture Selected')));
  });

  testWidgets('busy state disables controls without hiding active preview', (
    tester,
  ) async {
    var callCount = 0;
    await _pump(
      tester,
      viewModel: ComputerUseDebugWindowViewModel(
        isBusy: true,
        windows: const [_terminal],
        selectedWindowId: 42,
        snapshot: _snapshot,
        isPreviewActive: true,
      ),
      onListWindows: () => callCount += 1,
      onFocusSelected: () => callCount += 1,
      onCaptureSelected: () => callCount += 1,
      onSelectedWindowChanged: (_) => callCount += 1,
    );

    expect(_button(tester, 'List Windows').onPressed, isNull);
    expect(_button(tester, 'Focus Selected').onPressed, isNull);
    expect(_button(tester, 'Capture Selected').onPressed, isNull);
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    final preview = tester.widget<ComputerUseDebugImagePreview>(
      find.byType(ComputerUseDebugImagePreview),
    );
    expect(dropdown.onChanged, isNull);
    expect(preview.active, isTrue);
    expect(callCount, 0);
  });
}

FilledButton _button(WidgetTester tester, String label) {
  return tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
}

Future<void> _pump(
  WidgetTester tester, {
  required ComputerUseDebugWindowViewModel viewModel,
  VoidCallback? onListWindows,
  VoidCallback? onFocusSelected,
  VoidCallback? onCaptureSelected,
  ValueChanged<int?>? onSelectedWindowChanged,
  ValueChanged<ComputerUseDebugImagePoint>? onPointSelected,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 800,
            child: ComputerUseDebugWindowTargetingCard(
              viewModel: viewModel,
              onListWindows: onListWindows ?? () {},
              onFocusSelected: onFocusSelected ?? () {},
              onCaptureSelected: onCaptureSelected ?? () {},
              onSelectedWindowChanged: onSelectedWindowChanged ?? (_) {},
              onPointSelected: onPointSelected ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

const _terminal = ComputerUseDebugWindowItem(
  id: 42,
  label: 'Terminal - Shell (#42)',
  boundsLabel: 'Bounds: x=10, y=20, width=800, height=600',
);

const _browser = ComputerUseDebugWindowItem(
  id: 43,
  label: 'Safari - Docs (#43)',
  boundsLabel: 'Bounds: x=30, y=40, width=900, height=700',
);

const _snapshot = ComputerUseDebugImageSnapshot(
  title: 'Terminal - Shell',
  base64:
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
  width: 1,
  height: 1,
  mimeType: 'image/png',
);
