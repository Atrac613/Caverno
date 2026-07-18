import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_audio_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('view model derives exact toggle and action eligibility', () {
    const idleUnarmed = ComputerUseDebugAudioViewModel(
      isBusy: false,
      isRecording: false,
      isArmed: false,
    );
    const idleArmed = ComputerUseDebugAudioViewModel(
      isBusy: false,
      isRecording: false,
      isArmed: true,
    );
    const recording = ComputerUseDebugAudioViewModel(
      isBusy: false,
      isRecording: true,
      isArmed: false,
    );
    const busyRecording = ComputerUseDebugAudioViewModel(
      isBusy: true,
      isRecording: true,
      isArmed: true,
    );

    expect(idleUnarmed.canToggleArmed, isTrue);
    expect(idleUnarmed.canStartRecording, isFalse);
    expect(idleUnarmed.canStopRecording, isFalse);
    expect(idleArmed.canToggleArmed, isTrue);
    expect(idleArmed.canStartRecording, isTrue);
    expect(idleArmed.canStopRecording, isFalse);
    expect(recording.canToggleArmed, isFalse);
    expect(recording.canStartRecording, isFalse);
    expect(recording.canStopRecording, isTrue);
    expect(busyRecording.canToggleArmed, isFalse);
    expect(busyRecording.canStartRecording, isFalse);
    expect(busyRecording.canStopRecording, isFalse);
  });

  testWidgets('armed idle state enables toggle and start in order', (
    tester,
  ) async {
    bool? armedValue;
    var starts = 0;
    var stops = 0;
    await _pump(
      tester,
      viewModel: const ComputerUseDebugAudioViewModel(
        isBusy: false,
        isRecording: false,
        isArmed: true,
      ),
      onArmedChanged: (value) => armedValue = value,
      onStartRecording: () => starts += 1,
      onStopRecording: () => stops += 1,
    );

    expect(find.text('System Audio'), findsOneWidget);
    expect(
      find.text('Start and stop a ScreenCaptureKit system audio recording.'),
      findsOneWidget,
    );
    expect(find.text('System Audio Armed'), findsOneWidget);
    expect(find.text('Not recording'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);

    final switchTile = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    final startButton = _button(tester, 'Start Recording');
    final stopButton = _button(tester, 'Stop Recording');
    expect(switchTile.value, isTrue);
    expect(switchTile.onChanged, isNotNull);
    expect(startButton.onPressed, isNotNull);
    expect(stopButton.onPressed, isNull);

    switchTile.onChanged!(false);
    startButton.onPressed!();
    await tester.pump();

    expect(armedValue, isFalse);
    expect(starts, 1);
    expect(stops, 0);
    expect(
      tester.getTopLeft(find.text('Start Recording')).dx,
      lessThan(tester.getTopLeft(find.text('Stop Recording')).dx),
    );
  });

  testWidgets('recording state locks arming and enables only stop', (
    tester,
  ) async {
    var callCount = 0;
    await _pump(
      tester,
      viewModel: const ComputerUseDebugAudioViewModel(
        isBusy: false,
        isRecording: true,
        isArmed: false,
      ),
      onArmedChanged: (_) => callCount += 1,
      onStartRecording: () => callCount += 1,
      onStopRecording: () => callCount += 1,
    );

    expect(find.text('Recording active'), findsOneWidget);
    final recordingIcon = tester.widget<Icon>(
      find.byIcon(Icons.radio_button_checked),
    );
    expect(
      recordingIcon.color,
      Theme.of(tester.element(find.byType(Card))).colorScheme.error,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(_button(tester, 'Start Recording').onPressed, isNull);
    final stopButton = _button(tester, 'Stop Recording');
    expect(stopButton.onPressed, isNotNull);

    stopButton.onPressed!();
    await tester.pump();
    expect(callCount, 1);
  });

  testWidgets('busy state disables arming, start, and stop callbacks', (
    tester,
  ) async {
    var callCount = 0;
    await _pump(
      tester,
      viewModel: const ComputerUseDebugAudioViewModel(
        isBusy: true,
        isRecording: true,
        isArmed: true,
      ),
      onArmedChanged: (_) => callCount += 1,
      onStartRecording: () => callCount += 1,
      onStopRecording: () => callCount += 1,
    );

    final switchTile = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    final startButton = _button(tester, 'Start Recording');
    final stopButton = _button(tester, 'Stop Recording');
    expect(switchTile.value, isTrue);
    expect(switchTile.onChanged, isNull);
    expect(startButton.onPressed, isNull);
    expect(stopButton.onPressed, isNull);
    expect(callCount, 0);
  });
}

FilledButton _button(WidgetTester tester, String label) {
  return tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
}

Future<void> _pump(
  WidgetTester tester, {
  required ComputerUseDebugAudioViewModel viewModel,
  required ValueChanged<bool> onArmedChanged,
  required VoidCallback onStartRecording,
  required VoidCallback onStopRecording,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: ComputerUseDebugAudioCard(
            viewModel: viewModel,
            onArmedChanged: onArmedChanged,
            onStartRecording: onStartRecording,
            onStopRecording: onStopRecording,
          ),
        ),
      ),
    ),
  );
}
