import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_permission_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('status resolves readiness before snapshot availability', () {
    expect(
      ComputerUseDebugPermissionChecklistStatus.fromReadiness(
        isReady: true,
        hasSnapshot: true,
      ),
      ComputerUseDebugPermissionChecklistStatus.ready,
    );
    expect(
      ComputerUseDebugPermissionChecklistStatus.fromReadiness(
        isReady: false,
        hasSnapshot: true,
      ),
      ComputerUseDebugPermissionChecklistStatus.warning,
    );
    expect(
      ComputerUseDebugPermissionChecklistStatus.fromReadiness(
        isReady: false,
        hasSnapshot: false,
      ),
      ComputerUseDebugPermissionChecklistStatus.unknown,
    );
  });

  for (final testCase in const [
    (
      status: ComputerUseDebugPermissionChecklistStatus.ready,
      icon: Icons.task_alt_outlined,
      colorRole: _ColorRole.primary,
    ),
    (
      status: ComputerUseDebugPermissionChecklistStatus.warning,
      icon: Icons.warning_amber_outlined,
      colorRole: _ColorRole.error,
    ),
    (
      status: ComputerUseDebugPermissionChecklistStatus.unknown,
      icon: Icons.info_outline,
      colorRole: _ColorRole.secondary,
    ),
  ]) {
    testWidgets('${testCase.status.name} preserves checklist presentation', (
      tester,
    ) async {
      final title = '${testCase.status.name} title';
      final subtitle = '${testCase.status.name} subtitle';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          ),
          home: Scaffold(
            body: ComputerUseDebugPermissionChecklist(
              viewModel: ComputerUseDebugPermissionChecklistViewModel(
                title: title,
                subtitle: subtitle,
                status: testCase.status,
              ),
            ),
          ),
        ),
      );

      final checklist = find.byType(ComputerUseDebugPermissionChecklist);
      final context = tester.element(checklist);
      final theme = Theme.of(context);
      final color = switch (testCase.colorRole) {
        _ColorRole.primary => theme.colorScheme.primary,
        _ColorRole.error => theme.colorScheme.error,
        _ColorRole.secondary => theme.colorScheme.secondary,
      };
      expect(find.text(title), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(testCase.icon));
      expect(icon.color, color);

      final decoratedBox = tester.widget<DecoratedBox>(
        find.descendant(of: checklist, matching: find.byType(DecoratedBox)),
      );
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(decoration.color, color.withValues(alpha: 0.12));
      expect(
        (decoration.border! as Border).top.color,
        color.withValues(alpha: 0.35),
      );

      final padding = tester.widget<Padding>(
        find.descendant(of: checklist, matching: find.byType(Padding)).first,
      );
      expect(padding.padding, const EdgeInsets.all(12));
      expect(
        tester
            .widget<Row>(
              find.descendant(of: checklist, matching: find.byType(Row)),
            )
            .crossAxisAlignment,
        CrossAxisAlignment.start,
      );
      expect(
        find.descendant(
          of: checklist,
          matching: find.byWidgetPredicate(
            (widget) => widget is SizedBox && widget.width == 12,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: checklist,
          matching: find.byWidgetPredicate(
            (widget) => widget is SizedBox && widget.height == 2,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.text(title)).style,
        theme.textTheme.titleSmall,
      );
      expect(
        tester.widget<Text>(find.text(subtitle)).style,
        theme.textTheme.bodySmall,
      );
    });
  }
}

enum _ColorRole { primary, error, secondary }
