import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      demoMode: false,
    );
  }
}

Future<void> _pumpMessageInput(
  WidgetTester tester, {
  required ValueNotifier<bool> isLoading,
  required VoidCallback onCancel,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: isLoading,
            builder: (context, loading, child) {
              return MessageInput(
                onSend: (_, _, _) {},
                onCancel: onCancel,
                isLoading: loading,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('disables the composer and shows cancel while loading', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    var cancelCount = 0;
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {
        cancelCount += 1;
      },
    );

    expect(find.byIcon(Icons.record_voice_over), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    isLoading.value = true;
    await tester.pump();

    expect(find.byIcon(Icons.record_voice_over), findsNothing);
    expect(find.byIcon(Icons.stop_circle), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    await tester.tap(find.byIcon(Icons.stop_circle));
    await tester.pump();

    expect(cancelCount, 1);
  });
}
