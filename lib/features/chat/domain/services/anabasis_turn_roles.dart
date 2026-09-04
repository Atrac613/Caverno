import '../entities/model_usage_role.dart';
import 'anabasis_address.dart';

/// Which turns are running as the Anabasis parent, by interaction generation.
///
/// **Not a zone, and the reason is a defect this replaced.** The first version
/// opened a `ModelUsageRole.anabasisParent` zone around the turn. Inside it,
/// `_runWithLlmSessionLogContextForGeneration` opens its own zone defaulting to
/// `ModelUsageRole.chat` — deliberately, so a secondary role started mid-turn
/// wins — and an inner zone beats an outer one. The parent's role was
/// therefore replaced before the system prompt was built, so `@anabasis`
/// reached a real conversation with none of the parent's instructions. Unit
/// tests passed throughout: they exercised the zone directly, not the request
/// path that nests inside it.
///
/// Generations rather than a single flag because threads run concurrently, and
/// a flag would leak one thread's role into another's turn.
class AnabasisTurnRoles {
  final Set<int> _parentGenerations = <int>{};

  /// Records whether the turn starting at [generation] was addressed to the
  /// parent.
  void markAddressed({required int generation, required String content}) {
    if (AnabasisAddress.isAddressed(content)) {
      _parentGenerations.add(generation);
    }
  }

  void release(int generation) => _parentGenerations.remove(generation);

  void clear() => _parentGenerations.clear();

  /// Whether the turn at [generation] is the parent's.
  ///
  /// Named separately from [mainLoopRoleFor] because the transcript asks a
  /// yes/no question, and spelling the comparison out at the call site put
  /// three lines into the file least able to hold them.
  bool isParentTurn(int generation) => _parentGenerations.contains(generation);

  /// The role a main-loop request for [generation] bills to and runs as.
  ModelUsageRole mainLoopRoleFor(int generation) =>
      _parentGenerations.contains(generation)
      ? ModelUsageRole.anabasisParent
      : ModelUsageRole.chat;

  /// [requested], unless it is the main-loop default and this turn is the
  /// parent's.
  ///
  /// A secondary role started mid-turn keeps its own identity: it asked for
  /// something specific, and the parent's turn is not a reason to bill its
  /// memory extraction to the parent.
  ModelUsageRole resolve(ModelUsageRole requested, int generation) =>
      requested == ModelUsageRole.chat
      ? mainLoopRoleFor(generation)
      : requested;
}
