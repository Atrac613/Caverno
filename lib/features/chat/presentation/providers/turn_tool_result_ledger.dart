import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/tool_call_info.dart';

/// Tool results and commands retained independently by assistant-turn owner.
class TurnToolResultLedger {
  TurnToolResultLedger({
    Duration retention = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : assert(retention > Duration.zero),
       _retention = retention,
       _now = now ?? DateTime.now;

  final Duration _retention;
  final DateTime Function() _now;
  final Map<ChatTurnOwner, _TurnToolResultState> _states = {};

  int get length {
    _purgeExpired(_now());
    return _states.length;
  }

  bool get isEmpty => length == 0;

  List<ToolResultInfo> completed(ChatTurnOwner owner) =>
      _stateForRead(owner)?.completed ?? const <ToolResultInfo>[];

  List<ToolResultInfo> content(ChatTurnOwner owner) =>
      List.unmodifiable(_stateForRead(owner)?.content ?? const []);

  List<String> commands(ChatTurnOwner owner) =>
      List.unmodifiable(_stateForRead(owner)?.commands ?? const []);

  List<ToolResultInfo> all(ChatTurnOwner owner) {
    final state = _stateForRead(owner);
    return List.unmodifiable([...?state?.completed, ...?state?.content]);
  }

  void setCompleted(ChatTurnOwner owner, Iterable<ToolResultInfo> results) =>
      _stateFor(owner).completed = List.unmodifiable(results);

  void addContent(ChatTurnOwner owner, ToolResultInfo result) =>
      _stateFor(owner).content.add(result);
  void recordContent(
    ChatTurnOwner owner,
    ToolCallInfo toolCall,
    String result,
  ) {
    addContent(
      owner,
      ToolResultInfo(
        id: toolCall.id,
        name: toolCall.name,
        arguments: Map<String, dynamic>.unmodifiable(toolCall.arguments),
        result: result,
      ),
    );
  }

  ToolResultInfo? lastContentResultWhere(
    ChatTurnOwner owner,
    bool Function(ToolResultInfo) test,
  ) {
    final results = _stateForRead(owner)?.content;
    if (results == null) return null;
    for (final result in results.reversed) {
      if (test(result)) return result;
    }
    return null;
  }

  ToolResultInfo? lastSuccessfulContentWhere(
    ChatTurnOwner owner,
    bool Function(ToolResultInfo) test,
  ) => lastContentResultWhere(
    owner,
    (result) => test(result) && !_looksFailed(result.result),
  );

  void clearResults(ChatTurnOwner owner) {
    final state = _stateForRead(owner);
    if (state == null) return;
    state.completed = const <ToolResultInfo>[];
    state.content.clear();
  }

  void clearContentResults(ChatTurnOwner owner) =>
      _stateForRead(owner)?.content.clear();

  List<ToolResultInfo> takeAll(ChatTurnOwner owner) {
    final snapshot = all(owner);
    clearResults(owner);
    return snapshot;
  }

  List<ToolResultInfo> takeAndDispose(ChatTurnOwner owner) {
    final snapshot = all(owner);
    dispose(owner);
    return snapshot;
  }

  void recordCommand(ChatTurnOwner owner, String command) =>
      _stateFor(owner).commands.add(command);

  void publish(ChatTurnOwner owner) {
    final state = _stateForRead(owner);
    if (state != null) state.expiresAt = _now().add(_retention);
  }

  bool dispose(ChatTurnOwner owner) {
    _purgeExpired(_now());
    return _states.remove(owner) != null;
  }

  void clear() => _states.clear();

  _TurnToolResultState _stateFor(ChatTurnOwner owner) {
    _purgeExpired(_now());
    return _states.putIfAbsent(owner, _TurnToolResultState.new);
  }

  _TurnToolResultState? _stateForRead(ChatTurnOwner owner) {
    _purgeExpired(_now());
    return _states[owner];
  }

  void _purgeExpired(DateTime current) => _states.removeWhere(
    (_, state) => state.expiresAt?.isAfter(current) == false,
  );

  bool _looksFailed(String result) {
    final normalized = result.toLowerCase();
    if (normalized.contains('"error"') && normalized.contains('"code"')) {
      return true;
    }
    try {
      final decoded = jsonDecode(result);
      return decoded is Map && decoded.containsKey('error');
    } catch (_) {
      return false;
    }
  }
}

final class _TurnToolResultState {
  DateTime? expiresAt;
  List<ToolResultInfo> completed = const <ToolResultInfo>[];
  final List<ToolResultInfo> content = <ToolResultInfo>[];
  final List<String> commands = <String>[];
}
