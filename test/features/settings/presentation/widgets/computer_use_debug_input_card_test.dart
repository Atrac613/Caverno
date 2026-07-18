import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_input_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('view model derives the asymmetric action eligibility matrix', () {
    const idle = ComputerUseDebugInputViewModel(
      isBusy: false,
      isArmed: false,
      hasCoordinateTarget: false,
      coordinateTargetLabel: 'Active source: none',
    );
    const armedWithoutTarget = ComputerUseDebugInputViewModel(
      isBusy: false,
      isArmed: true,
      hasCoordinateTarget: false,
      coordinateTargetLabel: 'Active source: none',
    );
    const armedWithTarget = ComputerUseDebugInputViewModel(
      isBusy: false,
      isArmed: true,
      hasCoordinateTarget: true,
      coordinateTargetLabel: 'Active source: display screenshot',
    );
    const busy = ComputerUseDebugInputViewModel(
      isBusy: true,
      isArmed: true,
      hasCoordinateTarget: true,
      coordinateTargetLabel: 'Active source: display screenshot',
    );

    expect(idle.canToggleArmed, isTrue);
    expect(idle.canMovePointer, isFalse);
    expect(idle.canClickPoint, isFalse);
    expect(idle.canTypeText, isFalse);
    expect(armedWithoutTarget.canMovePointer, isFalse);
    expect(armedWithoutTarget.canClickPoint, isFalse);
    expect(armedWithoutTarget.canTypeText, isTrue);
    expect(armedWithTarget.canMovePointer, isTrue);
    expect(armedWithTarget.canClickPoint, isTrue);
    expect(armedWithTarget.canTypeText, isTrue);
    expect(busy.canToggleArmed, isFalse);
    expect(busy.canMovePointer, isFalse);
    expect(busy.canClickPoint, isFalse);
    expect(busy.canTypeText, isFalse);
  });

  testWidgets('idle state reuses controllers and preserves field contract', (
    tester,
  ) async {
    final controllers = _Controllers();
    addTearDown(controllers.dispose);
    bool? armedValue;
    await _pump(
      tester,
      viewModel: const ComputerUseDebugInputViewModel(
        isBusy: false,
        isArmed: false,
        hasCoordinateTarget: false,
        coordinateTargetLabel: 'Active source: none',
      ),
      controllers: controllers,
      onArmedChanged: (value) => armedValue = value,
    );

    expect(find.text('Input Smoke Checks'), findsOneWidget);
    expect(
      find.text(
        'Run explicit input events against the selected window or display coordinates.',
      ),
      findsOneWidget,
    );
    expect(find.text('Active source: none'), findsOneWidget);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller, same(controllers.x));
    expect(fields[1].controller, same(controllers.y));
    expect(fields[2].controller, same(controllers.text));
    expect(fields[0].keyboardType, TextInputType.number);
    expect(fields[1].keyboardType, TextInputType.number);
    expect(fields[2].keyboardType, TextInputType.text);
    expect(_button(tester, 'Move Pointer').onPressed, isNull);
    expect(_button(tester, 'Click Point').onPressed, isNull);
    expect(_button(tester, 'Type Text').onPressed, isNull);

    final switchTile = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    switchTile.onChanged!(true);
    expect(armedValue, isTrue);
  });

  testWidgets('armed state dispatches only actions allowed by target state', (
    tester,
  ) async {
    final controllers = _Controllers();
    addTearDown(controllers.dispose);
    final calls = <String>[];
    await _pump(
      tester,
      viewModel: const ComputerUseDebugInputViewModel(
        isBusy: false,
        isArmed: true,
        hasCoordinateTarget: false,
        coordinateTargetLabel: 'Active source: none',
      ),
      controllers: controllers,
      onMovePointer: () => calls.add('move'),
      onClickPoint: () => calls.add('click'),
      onTypeText: () => calls.add('type'),
    );

    expect(_button(tester, 'Move Pointer').onPressed, isNull);
    expect(_button(tester, 'Click Point').onPressed, isNull);
    _button(tester, 'Type Text').onPressed!();
    expect(calls, ['type']);

    await _pump(
      tester,
      viewModel: const ComputerUseDebugInputViewModel(
        isBusy: false,
        isArmed: true,
        hasCoordinateTarget: true,
        coordinateTargetLabel: 'Active source: display screenshot',
      ),
      controllers: controllers,
      onMovePointer: () => calls.add('move'),
      onClickPoint: () => calls.add('click'),
      onTypeText: () => calls.add('type'),
    );

    _button(tester, 'Move Pointer').onPressed!();
    _button(tester, 'Click Point').onPressed!();
    _button(tester, 'Type Text').onPressed!();
    expect(calls, ['type', 'move', 'click', 'type']);
    expect(
      tester.getTopLeft(find.text('Move Pointer')).dx,
      lessThan(tester.getTopLeft(find.text('Click Point')).dx),
    );
    expect(
      tester.getTopLeft(find.text('Click Point')).dx,
      lessThan(tester.getTopLeft(find.text('Type Text')).dx),
    );
  });

  testWidgets('busy state disables callbacks but leaves fields editable', (
    tester,
  ) async {
    final controllers = _Controllers();
    addTearDown(controllers.dispose);
    var callCount = 0;
    await _pump(
      tester,
      viewModel: const ComputerUseDebugInputViewModel(
        isBusy: true,
        isArmed: true,
        hasCoordinateTarget: true,
        coordinateTargetLabel: 'Active source: selected window screenshot',
      ),
      controllers: controllers,
      onArmedChanged: (_) => callCount += 1,
      onMovePointer: () => callCount += 1,
      onClickPoint: () => callCount += 1,
      onTypeText: () => callCount += 1,
    );

    expect(
      find.text('Active source: selected window screenshot'),
      findsOneWidget,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(_button(tester, 'Move Pointer').onPressed, isNull);
    expect(_button(tester, 'Click Point').onPressed, isNull);
    expect(_button(tester, 'Type Text').onPressed, isNull);

    final textField = find.widgetWithText(TextField, 'Text to type');
    await tester.enterText(textField, 'still editable');
    expect(controllers.text.text, 'still editable');
    expect(callCount, 0);
  });
}

FilledButton _button(WidgetTester tester, String label) {
  return tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
}

Future<void> _pump(
  WidgetTester tester, {
  required ComputerUseDebugInputViewModel viewModel,
  required _Controllers controllers,
  ValueChanged<bool>? onArmedChanged,
  VoidCallback? onMovePointer,
  VoidCallback? onClickPoint,
  VoidCallback? onTypeText,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 800,
            child: ComputerUseDebugInputCard(
              viewModel: viewModel,
              xController: controllers.x,
              yController: controllers.y,
              textController: controllers.text,
              onArmedChanged: onArmedChanged ?? (_) {},
              onMovePointer: onMovePointer ?? () {},
              onClickPoint: onClickPoint ?? () {},
              onTypeText: onTypeText ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}

final class _Controllers {
  final x = TextEditingController(text: '40');
  final y = TextEditingController(text: '50');
  final text = TextEditingController(text: 'hello');

  void dispose() {
    x.dispose();
    y.dispose();
    text.dispose();
  }
}
