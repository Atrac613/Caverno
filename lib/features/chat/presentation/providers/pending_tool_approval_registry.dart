import '../../domain/entities/chat_turn_owner.dart';
import 'pending_tool_approvals.dart';

/// Every pending approval in the app, keyed by id and by owning turn.
///
/// Extracted from `pending_tool_approvals.dart`, which sat at its ratchet
/// ceiling with no margin, so the eleventh pending type (ANA0's material
/// assumption confirmation) could not be added without either raising that
/// budget or extracting. The split is along a real seam: that file declares
/// what an approval *is*, and this one owns the lifetime of the ones currently
/// outstanding. Re-exported from `pending_tool_approvals.dart`, so no importer
/// changed.
class PendingToolApprovalRegistry {
  final Map<ChatTurnOwner, Map<String, PendingToolApproval<dynamic>>>
  _requestsByOwner = {};
  final Map<String, PendingToolApproval<dynamic>> _requestsById = {};

  int get length => _requestsById.length;
  bool get isEmpty => _requestsById.isEmpty;

  void register<T>(PendingToolApproval<T> request) {
    if (_requestsById.containsKey(request.id)) {
      throw StateError(
        'A pending tool approval already uses ID ${request.id}.',
      );
    }
    _requestsById[request.id] = request;
    (_requestsByOwner[request.owner] ??= {})[request.id] = request;
  }

  Future<T> registerCurrent<T>(
    PendingToolApproval<T> request, {
    required bool ownerIsCurrent,
    required void Function() show,
  }) {
    if (!ownerIsCurrent) {
      request.completeCancellation();
    } else {
      register(request);
      show();
    }
    return request.completer.future;
  }

  /// Every registered approval of type [T], including ones stashed for a
  /// thread the user is not reading.
  ///
  /// The projection into [ChatState] is per-thread, but the registry is not:
  /// an approval can be answered by id from anywhere, which is what lets a
  /// background turn be unblocked without first opening its thread.
  Iterable<T> pendingOfType<T extends PendingToolApproval<dynamic>>() =>
      _requestsById.values.whereType<T>();

  T? find<T extends PendingToolApproval<dynamic>>(String id) {
    final request = _requestsById[id];
    return request is T ? request : null;
  }

  T? take<T extends PendingToolApproval<dynamic>>({
    required ChatTurnOwner owner,
    required String id,
  }) {
    final request = _requestsByOwner[owner]?[id];
    if (request is! T) {
      return null;
    }
    _remove(owner: owner, id: id);
    return request;
  }

  T? takeCurrent<T extends PendingToolApproval<dynamic>>({
    required String id,
    required bool Function(ChatTurnOwner owner) ownerIsCurrent,
    required void Function(PendingToolApproval<dynamic> request) clear,
  }) {
    final request = find<T>(id);
    if (request == null) return null;
    if (!ownerIsCurrent(request.owner)) {
      cancel(owner: request.owner, id: id);
      clear(request);
      return null;
    }
    final taken = take<T>(owner: request.owner, id: id);
    if (taken != null) clear(taken);
    return taken;
  }

  bool cancel({required ChatTurnOwner owner, required String id}) {
    final request = _remove(owner: owner, id: id);
    if (request == null) {
      return false;
    }
    request.completeCancellation();
    return true;
  }

  List<PendingToolApproval<dynamic>> cancelOwner(ChatTurnOwner owner) {
    final requests = _requestsByOwner.remove(owner);
    if (requests == null) {
      return const [];
    }
    for (final entry in requests.entries) {
      if (identical(_requestsById[entry.key], entry.value)) {
        _requestsById.remove(entry.key);
      }
    }
    final cancelled = requests.values.toList(growable: false);
    for (final request in cancelled) {
      request.completeCancellation();
    }
    return cancelled;
  }

  int cancelAll() {
    if (_requestsById.isEmpty) {
      return 0;
    }
    final requests = _requestsById.values.toList(growable: false);
    _requestsById.clear();
    _requestsByOwner.clear();
    for (final request in requests) {
      request.completeCancellation();
    }
    return requests.length;
  }

  PendingToolApproval<dynamic>? _remove({
    required ChatTurnOwner owner,
    required String id,
  }) {
    final ownerRequests = _requestsByOwner[owner];
    final request = ownerRequests?.remove(id);
    if (request == null) {
      return null;
    }
    if (ownerRequests!.isEmpty) {
      _requestsByOwner.remove(owner);
    }
    if (identical(_requestsById[id], request)) {
      _requestsById.remove(id);
    }
    return request;
  }
}
