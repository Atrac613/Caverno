import '../entities/chat_turn_owner.dart';
import '../entities/tool_call_info.dart';
import 'context_surgery_observation_service.dart';
import 'immutable_json_snapshot.dart';

// ChatNotifier decomposition collaborator: context-surgery-observation-accumulator
final class ContextSurgeryObservationUpdate {
  ContextSurgeryObservationUpdate({
    this.systemPrompt,
    List<ToolResultInfo>? toolResults,
    List<Map<String, dynamic>>? toolDefinitions,
    Set<String>? mcpToolNames,
  }) : toolResults = toolResults == null
           ? null
           : _freezeToolResults(toolResults),
       toolDefinitions = toolDefinitions == null
           ? null
           : _freezeDefinitions(toolDefinitions),
       mcpToolNames = mcpToolNames == null
           ? null
           : Set<String>.unmodifiable(mcpToolNames);

  final String? systemPrompt;
  final List<ToolResultInfo>? toolResults;
  final List<Map<String, dynamic>>? toolDefinitions;
  final Set<String>? mcpToolNames;
}

final class ContextSurgeryObservationUpdateResult {
  const ContextSurgeryObservationUpdateResult({
    required this.owner,
    required this.snapshot,
    required this.changed,
  });

  final ChatTurnOwner owner;
  final ContextSurgeryObservationSnapshot snapshot;
  final bool changed;
}

final class ContextSurgeryObservationAccumulator {
  final Map<ChatTurnOwner, _ContextSurgeryObservationState> _states = {};

  ContextSurgeryObservationUpdateResult apply({
    required ChatTurnOwner owner,
    required ContextSurgeryObservationUpdate update,
  }) {
    final state = _states.putIfAbsent(
      owner,
      _ContextSurgeryObservationState.new,
    );
    if (update.systemPrompt != null) {
      state.systemPrompt = update.systemPrompt;
    }
    if (update.toolResults != null) {
      state.toolResults = _freezeToolResults(update.toolResults!);
    }
    if (update.toolDefinitions != null) {
      state.toolDefinitions = _freezeDefinitions(update.toolDefinitions!);
    }
    if (update.mcpToolNames != null) {
      state.mcpToolNames = Set<String>.unmodifiable(update.mcpToolNames!);
    }
    final nextSnapshot = _freezeSnapshot(
      ContextSurgeryObservationService.buildSnapshot(
        systemPrompt: state.systemPrompt,
        toolResults: state.toolResults,
        toolDefinitions: state.toolDefinitions,
        mcpToolNames: state.mcpToolNames,
      ),
    );
    final changed = state.snapshot != nextSnapshot;
    state.snapshot = nextSnapshot;
    return ContextSurgeryObservationUpdateResult(
      owner: owner,
      snapshot: nextSnapshot,
      changed: changed,
    );
  }

  ContextSurgeryObservationSnapshot snapshotFor(ChatTurnOwner owner) =>
      _states[owner]?.snapshot ?? ContextSurgeryObservationSnapshot.empty;

  bool removeOwner(ChatTurnOwner owner) => _states.remove(owner) != null;

  int clearConversation(String conversationId) {
    final previousLength = _states.length;
    _states.removeWhere(
      (owner, value) => owner.conversationId == conversationId,
    );
    return previousLength - _states.length;
  }

  void clear() => _states.clear();
}

final class _ContextSurgeryObservationState {
  String? systemPrompt;
  List<ToolResultInfo> toolResults = const [];
  List<Map<String, dynamic>> toolDefinitions = const [];
  Set<String> mcpToolNames = const {};
  ContextSurgeryObservationSnapshot snapshot =
      ContextSurgeryObservationSnapshot.empty;
}

List<ToolResultInfo> _freezeToolResults(List<ToolResultInfo> results) =>
    List<ToolResultInfo>.unmodifiable(
      results.map(
        (result) => ToolResultInfo(
          id: result.id,
          name: result.name,
          arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
          result: result.result,
        ),
      ),
    );

List<Map<String, dynamic>> _freezeDefinitions(
  List<Map<String, dynamic>> definitions,
) => List<Map<String, dynamic>>.unmodifiable(
  definitions.map(ImmutableJsonSnapshot.freezeMap),
);

ContextSurgeryObservationSnapshot _freezeSnapshot(
  ContextSurgeryObservationSnapshot snapshot,
) => ContextSurgeryObservationSnapshot(
  sections: List<ContextSurgerySectionSummary>.unmodifiable(snapshot.sections),
  staleToolResultCandidateCount: snapshot.staleToolResultCandidateCount,
  staleToolResultEstimatedTokens: snapshot.staleToolResultEstimatedTokens,
);
