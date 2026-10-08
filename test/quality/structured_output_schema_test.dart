import 'package:caverno/features/chat/domain/services/flutter_run/flutter_run_issue_request.dart';
import 'package:caverno/features/project_farm/domain/next_step_proposal_contract.dart';
import 'package:caverno/features/project_farm/domain/project_task_decomposition_contract.dart';
import 'package:caverno/features/project_farm/domain/roadmap_next_task_contract.dart';
import 'package:flutter_test/flutter_test.dart';

/// Strict structured output rejects a schema whose `required` omits any key in
/// `properties`, and the rejection is an opaque HTTP 400 at request time: the
/// Issue tab simply stopped analysing runs, with the reason only in the log.
/// These schemas are small and hand-written, so pin the rule where it is cheap.
void main() {
  test('every response-format schema requires all of its properties', () {
    const schemas = <String, Map<String, dynamic>>{
      'caverno_run_issue': FlutterRunIssueRequest.schema,
      'caverno_roadmap_next_task': extractionSchema,
      'caverno_roadmap_sections': outlineSchema,
      'caverno_next_step_proposal': nextStepProposalSchema,
      'caverno_project_task_decomposition': projectTaskDecompositionSchema,
    };

    for (final entry in schemas.entries) {
      final properties = (entry.value['properties'] as Map).keys.toSet();
      final required = (entry.value['required'] as List).toSet();
      expect(
        required,
        equals(properties),
        reason: '${entry.key} must list every property in required',
      );
    }
  });
}
