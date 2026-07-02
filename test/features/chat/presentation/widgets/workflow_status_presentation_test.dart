import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/presentation/widgets/workflow_status_presentation.dart';

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

  test('selects projection status label keys', () {
    const markdown = '# Plan\n\n- Ship it';
    final fresh = _conversation(
      markdown: markdown,
      workflowSourceHash: computeConversationPlanHash(markdown),
      workflowDerivedAt: DateTime(2026),
      workflowSpec: const ConversationWorkflowSpec(goal: 'Ship it'),
    );
    final stale = _conversation(
      markdown: markdown,
      workflowSourceHash: 'older-hash',
      workflowDerivedAt: DateTime(2026),
      workflowSpec: const ConversationWorkflowSpec(goal: 'Ship it'),
    );
    final unavailable = _conversation();

    expect(
      WorkflowStatusPresentation.workflowProjectionStatusLabelKey(fresh),
      'chat.plan_document_projection_fresh',
    );
    expect(
      WorkflowStatusPresentation.workflowProjectionStatusLabelKey(stale),
      'chat.plan_document_projection_stale',
    );
    expect(
      WorkflowStatusPresentation.workflowProjectionStatusLabelKey(unavailable),
      'chat.plan_document_projection_unavailable',
    );
  });

  testWidgets('maps workflow stage and status labels', (tester) async {
    await _pumpLocalization(tester);

    expect(
      WorkflowStatusPresentation.workflowStageLabel(
        ConversationWorkflowStage.idle,
      ),
      'Idle',
    );
    expect(
      WorkflowStatusPresentation.workflowStageLabel(
        ConversationWorkflowStage.implement,
      ),
      'Implement',
    );
    expect(
      WorkflowStatusPresentation.workflowTaskStatusLabel(
        ConversationWorkflowTaskStatus.pending,
      ),
      'Pending',
    );
    expect(
      WorkflowStatusPresentation.workflowTaskStatusLabel(
        ConversationWorkflowTaskStatus.completed,
      ),
      'Completed',
    );
    expect(
      WorkflowStatusPresentation.workflowValidationStatusLabel(
        ConversationExecutionValidationStatus.unknown,
      ),
      'Unknown',
    );
    expect(
      WorkflowStatusPresentation.workflowValidationStatusLabel(
        ConversationExecutionValidationStatus.failed,
      ),
      'Failed',
    );
  });

  test('recommends the next workflow stage', () {
    expect(
      WorkflowStatusPresentation.recommendedWorkflowStage(
        ConversationWorkflowStage.idle,
      ),
      ConversationWorkflowStage.clarify,
    );
    expect(
      WorkflowStatusPresentation.recommendedWorkflowStage(
        ConversationWorkflowStage.implement,
      ),
      ConversationWorkflowStage.review,
    );
    expect(
      WorkflowStatusPresentation.recommendedWorkflowStage(
        ConversationWorkflowStage.review,
      ),
      isNull,
    );
  });
}

Future<void> _pumpLocalization(WidgetTester tester) async {
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
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const SizedBox.shrink(),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Conversation _conversation({
  String? markdown,
  String workflowSourceHash = '',
  DateTime? workflowDerivedAt,
  ConversationWorkflowSpec? workflowSpec,
}) {
  return Conversation(
    id: 'conversation-test',
    title: 'Conversation',
    messages: const [],
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    planArtifact: markdown == null
        ? null
        : ConversationPlanArtifact(approvedMarkdown: markdown),
    workflowSourceHash: workflowSourceHash,
    workflowDerivedAt: workflowDerivedAt,
    workflowSpec: workflowSpec,
  );
}
