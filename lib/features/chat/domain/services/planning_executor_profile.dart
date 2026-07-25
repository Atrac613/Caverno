import '../../../settings/domain/entities/app_settings.dart';

/// Measured limits of the model that will *execute* a plan, for the model that
/// *drafts* it.
///
/// Plan drafting can be routed to a different (usually stronger) model than the
/// one that runs the plan — see the planning role in model routing settings. A
/// planner that assumes its own context window and tool budget writes tasks the
/// executor cannot carry out: task lists sized for a large context, single
/// tasks that need more tool iterations than the loop allows, or verification
/// that presumes the planner's own competence.
///
/// Only probed or explicitly configured facts are carried here — never inferred
/// ones, and only facts a prompt rule below actually acts on. Disclosing a bare
/// capability the planner is given no instruction about (tool-call style, edit
/// format) just spends instruction budget, so those stay out until a rule needs
/// them. An unmeasured budget is omitted rather than guessed.
class PlanningExecutorProfile {
  const PlanningExecutorProfile({
    required this.model,
    this.usableContextTokens = 0,
    this.toolLoopMaxIterations = 0,
  });

  /// Tool-loop iteration cap used when no per-model harness override is stored.
  /// Mirrors the default in the chat tool loop; both read this constant.
  static const int defaultToolLoopMaxIterations = 12;

  final String model;
  final int usableContextTokens;
  final int toolLoopMaxIterations;

  /// The executor profile to disclose to the planner, or null when plan
  /// drafting runs on the executor model itself.
  ///
  /// Returning null for the unrouted case keeps a planning session's prompt
  /// byte-identical to what it was before the planning role existed: the block
  /// only appears once planner and executor actually differ, which is the only
  /// case where the mismatch it guards against can occur.
  static PlanningExecutorProfile? fromSettings(AppSettings settings) {
    final executorModel = settings.effectiveModel.trim();
    if (executorModel.isEmpty) return null;
    if (settings.effectivePlanningModel.trim() == executorModel) return null;

    final harness = settings.effectiveModelHarnessConfig;
    return PlanningExecutorProfile(
      model: executorModel,
      usableContextTokens:
          settings.effectiveModelCapabilityProfile?.usableContextTokens ?? 0,
      toolLoopMaxIterations:
          harness?.resolveToolLoopMaxIterations(defaultToolLoopMaxIterations) ??
          defaultToolLoopMaxIterations,
    );
  }

  /// Prompt block describing the executor, or null when nothing is known
  /// beyond a model id that carries no budget information.
  String? toPromptBlock({bool compact = false}) {
    if (compact) return _compactBlock();

    final buffer = StringBuffer()
      ..writeln('Plan executor:')
      ..writeln(
        '- A different model executes this plan than the one drafting it.',
      )
      ..writeln('- model: $model');
    if (usableContextTokens > 0) {
      buffer.writeln('- usableContextTokens: $usableContextTokens');
    }
    if (toolLoopMaxIterations > 0) {
      buffer.writeln('- toolLoopMaxIterations: $toolLoopMaxIterations');
    }
    buffer
      ..writeln(
        '- Size every task so the executing model can finish it within those '
        'limits. Prefer more, smaller tasks over few large ones.',
      )
      ..writeln(
        '- Do not assume the executor can hold the whole repository, or every '
        'file in one task\'s targetFiles, in context at once.',
      )
      ..writeln(
        '- Each task must be verifiable by its own validationCommand without '
        'the drafting model.',
      );
    return buffer.toString().trimRight();
  }

  String _compactBlock() {
    final facts = <String>[
      'model: $model',
      if (usableContextTokens > 0) 'context: $usableContextTokens tokens',
      if (toolLoopMaxIterations > 0)
        'tool-loop: $toolLoopMaxIterations iterations',
    ];
    return 'Plan executor (a different model runs this plan): '
        '${facts.join(', ')}. '
        'Size tasks to fit; prefer more, smaller tasks.';
  }
}
