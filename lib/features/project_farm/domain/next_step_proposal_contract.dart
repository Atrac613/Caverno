/// The next-step proposal contract for FARM3 suggest mode.
///
/// See `docs/project_farm_roadmap.md`, FARM3. The model chooses among
/// candidates Caverno already verified against the roadmap; it cannot name a
/// task of its own. Its rationale and automatability label are advice for the
/// user, never authority: nothing starts without the user's Start work.
///
/// Pure Dart, like the roadmap contract.
library;

import 'dart:convert';

/// Bump when the prompt, schema, or verification changes.
const int nextStepProposalVersion = 1;

enum ProposalAutomatability {
  /// An LL13 worktree agent could finish it with file edits and one declared
  /// verification command.
  unattended,

  /// Needs a person: devices, accounts, a decision, live services, or tools
  /// the worktree agent does not have.
  needsHuman,
}

/// One roadmap item offered to the model, already verified by the roadmap
/// extractor.
final class ProposalCandidate {
  const ProposalCandidate({
    required this.id,
    required this.title,
    required this.quote,
    required this.status,
  });

  final String id;
  final String title;
  final String quote;

  /// `next`, `in_progress`, or `blocked`, as the roadmap states it.
  final String status;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status,
    'quote': quote,
  };
}

/// A coding thread summarized for the model: no transcript, only state.
final class ProposalThread {
  const ProposalThread({
    required this.title,
    required this.state,
    this.goal,
    this.goalStatus,
  });

  final String title;
  final String state;
  final String? goal;
  final String? goalStatus;

  Map<String, dynamic> toJson() => {
    'title': title,
    'state': state,
    'goal': goal,
    'goal_status': goalStatus,
  };
}

const Map<String, dynamic> nextStepProposalSchema = {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'task_id': {'type': 'string'},
    'rationale': {'type': 'string'},
    'automatability': {
      'type': 'string',
      'enum': ['unattended', 'needs_human'],
    },
    'automatability_reason': {'type': 'string'},
  },
  'required': [
    'task_id',
    'rationale',
    'automatability',
    'automatability_reason',
  ],
};

const String nextStepProposalSystemPrompt = '''
You help a developer decide the next step for one software project.

You get the project's roadmap items, already extracted and verified, and the
state of its coding threads. Choose the single item to work on next.

- task_id: the id of one listed item, exactly as given, or an empty string
  when no listed item should be started now (for example, everything is
  blocked or already being worked on in a thread).
- rationale: at most two sentences on why this item is next, citing its
  status or the thread state.
- automatability: "unattended" only if an agent with nothing but file edits
  in a separate git worktree and one test or analysis command could finish it.
  Otherwise "needs_human": physical devices, signing, accounts, a product
  decision, live services or measurements, or code generation tools.
- automatability_reason: one sentence.

Prefer the item the roadmap marks as next unless a thread is already working
on it or it is blocked. Do not invent items.''';

/// Builds the user message for one project.
String nextStepProposalInput({
  required String projectName,
  required List<ProposalCandidate> candidates,
  required List<ProposalThread> threads,
}) => const JsonEncoder.withIndent('  ').convert({
  'project': projectName,
  'roadmap_items': [for (final c in candidates) c.toJson()],
  'threads': [for (final t in threads) t.toJson()],
});

/// A proposal that passed verification.
final class VerifiedProposal {
  const VerifiedProposal({
    required this.taskId,
    required this.rationale,
    required this.automatability,
    required this.automatabilityReason,
  });

  /// Empty when the model proposed starting nothing.
  final String taskId;
  final String rationale;
  final ProposalAutomatability automatability;
  final String automatabilityReason;
}

/// Parses and verifies a model answer. Returns null when the answer is not
/// usable: unparseable, or naming a task that is not a candidate.
VerifiedProposal? verifyNextStepProposal(
  Map<String, dynamic>? decoded,
  List<ProposalCandidate> candidates,
) {
  if (decoded == null) return null;
  String text(String key) =>
      decoded[key] is String ? (decoded[key] as String).trim() : '';
  final taskId = text('task_id');
  if (taskId.isNotEmpty && !candidates.any((c) => c.id == taskId)) {
    return null;
  }
  final automatability = switch (text('automatability')) {
    'unattended' => ProposalAutomatability.unattended,
    'needs_human' => ProposalAutomatability.needsHuman,
    _ => null,
  };
  if (automatability == null) return null;
  return VerifiedProposal(
    taskId: taskId,
    rationale: text('rationale'),
    automatability: automatability,
    automatabilityReason: text('automatability_reason'),
  );
}
