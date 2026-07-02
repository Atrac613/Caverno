import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/proposal_parsing_text_utils.dart';

void main() {
  group('ProposalJsonExtractor', () {
    test('repairs truncated JSON objects', () {
      var repairCount = 0;
      final extractor = ProposalJsonExtractor(
        onJsonRepair: () => repairCount++,
      );

      final decoded = extractor.extractJsonMap('{"taskCount":1');

      expect(decoded, {'taskCount': 1});
      expect(repairCount, 1);
    });

    test('calls the repair hook only when a repair succeeds', () {
      var repairCount = 0;
      final extractor = ProposalJsonExtractor(
        onJsonRepair: () => repairCount++,
      );

      expect(extractor.extractJsonMap('{"goal":"Direct"}'), {'goal': 'Direct'});
      expect(repairCount, 0);

      expect(extractor.extractJsonMap('prefix {"goal":"Sliced"} suffix'), {
        'goal': 'Sliced',
      });
      expect(repairCount, 0);

      expect(extractor.extractJsonMap('```json\n{"taskCount":1\n```'), {
        'taskCount': 1,
      });
      expect(repairCount, 1);

      expect(extractor.extractJsonMap('prefix {"taskCount":2'), {
        'taskCount': 2,
      });
      expect(repairCount, 2);
    });
  });

  group('ProposalParsingTextUtils', () {
    test('collects proposal sections from markdown labels', () {
      final sections = ProposalParsingTextUtils.collectProposalSections('''
Goal: Add persisted planning state
Constraints:
- Keep existing conversations compatible
Acceptance Criteria:
- Planning state survives reload
Open Questions: Should drafts sync across devices?
''');

      expect(sections['goal'], ['Add persisted planning state']);
      expect(sections['constraints'], [
        'Keep existing conversations compatible',
      ]);
      expect(sections['acceptanceCriteria'], [
        'Planning state survives reload',
      ]);
      expect(sections['openQuestions'], ['Should drafts sync across devices?']);
    });

    test('detects truncation finish reasons', () {
      expect(ProposalParsingTextUtils.isCompletionTruncated('length'), isTrue);
      expect(
        ProposalParsingTextUtils.isCompletionTruncated(' LENGTH '),
        isTrue,
      );
      expect(ProposalParsingTextUtils.isCompletionTruncated('stop'), isFalse);
      expect(ProposalParsingTextUtils.isCompletionTruncated(''), isFalse);
    });
  });
}
