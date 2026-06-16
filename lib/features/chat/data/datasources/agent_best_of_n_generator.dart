import '../../domain/entities/message.dart';
import 'best_of_n_runner.dart';

/// Runs one non-interactive agent attempt for the given prompt and returns the
/// agent's final output text. The caller adapts the real agent loop
/// (`RoutineToolRunner.execute` dispatching through `McpToolService` under the
/// RoutineToolPolicy trust model) to this signature, keeping this generator free
/// of a chat<->routines import cycle and trivially testable.
typedef AgentAttemptRunner = Future<String> Function(List<Message> messages);

/// LL7 candidate generation backed by the non-interactive agent.
///
/// Produces a [BestOfNGenerationStep]: for each candidate it builds the prompt,
/// runs one agent attempt (which edits the working tree), then reports the files
/// git says changed so verification knows what to test. Candidates after the
/// first are nudged toward independent approaches so Best-of-N explores the
/// solution space instead of repeating one answer.
class AgentBestOfNGenerator {
  AgentBestOfNGenerator({
    required this.goal,
    required this.candidateCount,
    required this.runAttempt,
    required this.changedPaths,
    this.systemPrompt = _defaultSystemPrompt,
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  static const _defaultSystemPrompt =
      'You are a coding agent completing a task in the current project. Make the '
      'smallest correct change that satisfies the request, edit files with the '
      'file tools, and verify your work. Do not ask for confirmation.';

  final String goal;
  final int candidateCount;
  final AgentAttemptRunner runAttempt;
  final Future<List<String>> Function() changedPaths;
  final String systemPrompt;
  final DateTime Function() _now;

  /// Use as the [BestOfNGenerationStep] for [BestOfNCoordinator].
  BestOfNGenerationStep get step => generate;

  Future<BestOfNGeneration> generate(int index) async {
    final output = await runAttempt(_buildMessages(index));
    final changed = await changedPaths();
    return BestOfNGeneration(
      summary: _summarize(output, changed),
      changedPaths: changed,
    );
  }

  List<Message> _buildMessages(int index) {
    final timestamp = _now();
    final diversity = candidateCount > 1
        ? '\n\n(This is attempt ${index + 1} of $candidateCount independent '
              'attempts. Produce a complete, self-consistent solution; a '
              'different valid approach from other attempts is welcome.)'
        : '';
    return [
      Message(
        id: 'best_of_n_system_$index',
        content: systemPrompt,
        role: MessageRole.system,
        timestamp: timestamp,
      ),
      Message(
        id: 'best_of_n_user_$index',
        content: '$goal$diversity',
        role: MessageRole.user,
        timestamp: timestamp,
      ),
    ];
  }

  String _summarize(String output, List<String> changed) {
    final firstLine = output
        .trim()
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final head = firstLine.length > 140
        ? '${firstLine.substring(0, 140)}…'
        : firstLine;
    final files = '${changed.length} file(s) changed';
    return head.isEmpty ? files : '$files; $head';
  }
}
