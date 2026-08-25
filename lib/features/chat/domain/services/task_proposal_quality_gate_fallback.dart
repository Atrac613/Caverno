import '../../presentation/providers/chat_state.dart';
import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'planning_research_collector.dart';
import 'planning_retry_context_builder.dart';
import 'workflow_proposal_parser.dart';
import 'workflow_task_proposal_quality_service.dart';

/// Assembles the task proposal to use when the model's own keeps failing the
/// quality gate.
///
/// A retry that keeps missing is not evidence that the work cannot be
/// described -- the goal, the constraints, and the best candidate so far
/// already say what it is. This turns that material into tasks rather than
/// leaving the turn with none, and returns null instead of a proposal that
/// would fail the same gate.
final class TaskProposalQualityGateFallback {
  const TaskProposalQualityGateFallback({
    required WorkflowTaskProposalQualityService quality,
    required WorkflowProposalParser parser,
  }) : _quality = quality,
       _parser = parser;

  final WorkflowTaskProposalQualityService _quality;
  final WorkflowProposalParser _parser;

  /// The proposal to fall back to when the model's tasks keep failing the
  /// quality gate, or null when nothing usable can be assembled.
  WorkflowTaskProposalDraft? build({
    required Conversation currentConversation,
    required bool projectLooksEmpty,
    required PlanningResearchContext researchContext,
    WorkflowTaskProposalDraft? bestRetryCandidate,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    final workflowSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    final rawGoal = workflowSpec.goal.trim().isNotEmpty
        ? workflowSpec.goal.trim()
        : _parser.deriveWorkflowFallbackGoalFromConversation(
            currentConversation,
          );
    if (rawGoal == null || rawGoal.isEmpty) {
      return null;
    }

    if (bestRetryCandidate != null &&
        !_quality.taskProposalNeedsRetryForWorkflow(
          bestRetryCandidate,
          bestRetryCandidate,
          projectLooksEmpty,
          workflowSpec,
        )) {
      return bestRetryCandidate;
    }

    final contextLines = <String>[
      rawGoal,
      ...workflowSpec.constraints,
      ...workflowSpec.acceptanceCriteria,
      ...workflowSpec.openQuestions,
    ];
    if (bestRetryCandidate != null) {
      for (final task in bestRetryCandidate.tasks) {
        contextLines.add(task.title);
        contextLines.add(task.notes);
        contextLines.add(task.validationCommand);
        contextLines.addAll(task.targetFiles);
      }
    }

    final fallbackProposal = WorkflowTaskProposalDraft(
      tasks: _quality.buildHeuristicTaskProposalFallbackTasks(
        contextLines: contextLines,
        projectLooksEmpty: projectLooksEmpty,
      ),
    );
    if (fallbackProposal.tasks.isEmpty) {
      return null;
    }

    final finalizedFallback = _quality.finalizeTaskProposalDraft(
      fallbackProposal,
      projectLooksEmpty: PlanningRetryContextBuilder.projectLooksEmpty(
        researchContext,
      ),
    );
    if (_quality.taskProposalNeedsRetryForWorkflow(
      fallbackProposal,
      finalizedFallback,
      projectLooksEmpty,
      workflowSpec,
    )) {
      return null;
    }
    return finalizedFallback;
  }
}
