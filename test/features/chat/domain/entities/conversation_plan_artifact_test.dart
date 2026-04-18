import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';

void main() {
  test('planning and execution markdown prefer the expected source', () {
    const artifact = ConversationPlanArtifact(
      draftMarkdown: '# Plan\n\n## Goal\nDraft',
      approvedMarkdown: '# Plan\n\n## Goal\nApproved',
    );

    expect(artifact.planningMarkdown, '# Plan\n\n## Goal\nDraft');
    expect(artifact.executionMarkdown, '# Plan\n\n## Goal\nApproved');
    expect(
      artifact.displayMarkdown(isPlanning: true),
      '# Plan\n\n## Goal\nDraft',
    );
    expect(
      artifact.displayMarkdown(isPlanning: false),
      '# Plan\n\n## Goal\nApproved',
    );
    expect(artifact.hasPlanningDocument, isTrue);
    expect(artifact.hasExecutionDocument, isTrue);
  });

  test('execution markdown falls back to the draft when needed', () {
    const artifact = ConversationPlanArtifact(
      draftMarkdown: '# Plan\n\n## Goal\nDraft only',
    );

    expect(artifact.planningMarkdown, '# Plan\n\n## Goal\nDraft only');
    expect(artifact.executionMarkdown, '# Plan\n\n## Goal\nDraft only');
    expect(artifact.hasExecutionDocument, isTrue);
  });
}
