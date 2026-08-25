import '../entities/conversation_workflow.dart';
import 'planning_research_collector.dart';
import 'workflow_task_proposal_quality_service.dart';

/// Builds the extra planning context a proposal retry carries.
///
/// A retry exists because the first answer was too long or missed the quality
/// gate, so the hints are written to shrink and concretise the next one rather
/// than to re-explain the request. They are prose with no state of their own,
/// which is why they live here instead of in the notifier that decides when a
/// retry happens.
final class PlanningRetryContextBuilder {
  const PlanningRetryContextBuilder(this._quality);

  final WorkflowTaskProposalQualityService _quality;

  /// Retry context for a workflow proposal that has to come back smaller.
  String? forWorkflowProposal(
    String? additionalPlanningContext, {
    required bool minimalRetry,
    required bool projectLooksEmpty,
  }) {
    final normalizedContext = additionalPlanningContext?.trim();
    if (!minimalRetry && !projectLooksEmpty) {
      return normalizedContext;
    }

    final retryLines = <String>[
      if (projectLooksEmpty)
        'Retry hint: The workspace is empty, so prefer the shortest viable workflow proposal.',
      'Retry hint:',
      '- Return the smallest valid JSON proposal possible.',
      '- Do not restate the user request, project summary, or research context.',
      '- Prefer a short goal plus one or two short list items over verbose explanations.',
      '- If you are space-constrained, return workflowStage, goal, and a minimal acceptanceCriteria list only.',
    ];
    if (projectLooksEmpty) {
      retryLines.add(
        '- For an empty project, avoid setup narration and focus on the requested outcome.',
      );
    }
    final retryHint = retryLines.join('\n');
    if (normalizedContext == null || normalizedContext.isEmpty) {
      return retryHint;
    }
    return '$normalizedContext\n$retryHint'.trim();
  }

  /// Retry context for a task proposal that failed the quality gate.
  String? forTaskProposal(
    String? additionalPlanningContext, {
    required bool minimalRetry,
    required bool projectLooksEmpty,
    ConversationWorkflowSpec? workflowSpec,
  }) {
    final normalizedContext = additionalPlanningContext?.trim();
    if (!minimalRetry) {
      return normalizedContext;
    }

    final prefersSingleTask =
        workflowSpec != null &&
        _quality.workflowPrefersExplicitSingleTask(workflowSpec);

    final retryHint = StringBuffer()
      ..writeln('Retry hint:')
      ..writeln('- Return the smallest valid JSON task list possible.')
      ..writeln(
        '- Every task must describe an action the agent can perform immediately.',
      )
      ..writeln('- Keep each title short and imperative.')
      ..writeln(
        '- Use at most one primary implementation file per non-scaffold task.',
      )
      ..writeln(
        '- For implementation tasks, use a validationCommand that directly references, executes, or tests the target file or module.',
      )
      ..writeln(
        '- Do not use generic validation such as "module importable" or commands that only append src to sys.path.',
      )
      ..writeln(
        '- Do not restate the user request, repo summary, or research context.',
      );
    if (prefersSingleTask) {
      retryHint
        ..writeln('- Return exactly one concrete implementation task.')
        ..writeln(
          '- The single task must include implementation and validation in that task.',
        )
        ..writeln(
          '- Do not add a separate verification-only task or follow-up task.',
        );
    } else {
      final requiredFirstSliceTargets = workflowSpec == null
          ? const <String>{}
          : _quality.explicitFirstSliceTargetFiles(workflowSpec);
      retryHint
        ..writeln('- Return two to four concrete tasks.')
        ..writeln('- Do not stop at a single generic setup or scaffold task.');
      if (requiredFirstSliceTargets.isNotEmpty) {
        final targetList = requiredFirstSliceTargets.toList()..sort();
        retryHint
          ..writeln(
            '- The first task targetFiles must include ${targetList.join(', ')}.',
          )
          ..writeln(
            '- Do not split those first-slice scaffold files into separate tasks.',
          );
      }
    }
    if (projectLooksEmpty) {
      if (prefersSingleTask) {
        retryHint
          ..writeln(
            '- In an empty workspace, create the requested single implementation file directly.',
          )
          ..writeln(
            '- Do not scaffold README.md, requirements.txt, tests, or package files unless the workflow explicitly names them.',
          );
      } else {
        retryHint
          ..writeln(
            '- The first task may scaffold the workspace, but a later task must implement or validate the requested feature.',
          )
          ..writeln('- Include a concrete code task after any scaffold task.')
          ..writeln(
            '- Prefer a simple Python entrypoint such as main.py when the workspace is empty.',
          )
          ..writeln(
            '- Avoid pytest-based verification in an empty Python workspace. Prefer standard-library validation such as python3 target.py, python3 tests/test_ping.py, or python3 -m unittest.',
          );
      }
      retryHint.writeln(
        '- Prefer Python standard-library or subprocess-based implementations over third-party runtime dependencies unless the user explicitly asked for a package.',
      );
    }

    final retryContext = retryHint.toString().trim();
    if (normalizedContext == null || normalizedContext.isEmpty) {
      return retryContext;
    }
    return '$normalizedContext\n$retryContext'.trim();
  }

  /// Whether planning should treat the workspace as empty.
  ///
  /// Image files alone still count as empty: a screenshot the user dropped
  /// in is context for the request, not work already standing.
  static bool projectLooksEmpty(PlanningResearchContext context) {
    final rootEntries = context.rootEntries
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (rootEntries.isEmpty) {
      return true;
    }
    return rootEntries.every(
      (entry) =>
          entry.contains('.png') ||
          entry.contains('.jpg') ||
          entry.contains('.jpeg'),
    );
  }
}
