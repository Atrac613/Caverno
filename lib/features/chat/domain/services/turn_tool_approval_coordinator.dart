import 'dart:convert';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import 'immutable_json_snapshot.dart';
import 'tool_approval_auto_review_service.dart';

// ChatNotifier decomposition collaborator: turn-tool-approval-coordinator
final class ToolApprovalRequest {
  ToolApprovalRequest({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required Map<String, dynamic> arguments,
    required this.actionKind,
    required this.mode,
    required this.reviewDomain,
    required this.fullAccessEligible,
    Map<String, dynamic>? cacheArguments,
    this.cacheStateFingerprint,
    this.path,
    this.workingDirectory,
    this.reason,
    this.warningTitle,
    this.warningMessage,
    this.preview,
    List<Message> conversationMessages = const [],
    this.hasUntrustedInfluence = false,
  }) : arguments = _freezeMap(arguments),
       cacheArguments = cacheArguments == null
           ? null
           : _freezeMap(cacheArguments),
       conversationMessages = List<Message>.unmodifiable(conversationMessages);
  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String actionKind;
  final ToolApprovalMode mode;
  final ToolApprovalAutoReviewDomain reviewDomain;
  final bool fullAccessEligible;
  final Map<String, dynamic>? cacheArguments;
  final String? cacheStateFingerprint;
  final String? path;
  final String? workingDirectory;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;
  final String? preview;
  final List<Message> conversationMessages;
  final bool hasUntrustedInfluence;
  static Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
      ImmutableJsonSnapshot.freezeMap(value);
}

final class ManualToolApprovalRequest {
  const ManualToolApprovalRequest({
    required this.toolCallId,
    required this.toolName,
    required this.actionKind,
    required this.arguments,
    required this.warningTitle,
    required this.warningMessage,
    required this.preview,
    this.targetDisplayName,
  });
  final String toolCallId;
  final String toolName;
  final String actionKind;
  final Map<String, dynamic> arguments;
  final String? warningTitle;
  final String? warningMessage;
  final String? preview;
  final String? targetDisplayName;
}

final class ManualToolApprovalDecision {
  const ManualToolApprovalDecision.approved({this.rememberApproval = false})
    : denialResult = null;
  const ManualToolApprovalDecision.denied(McpToolResult this.denialResult)
    : rememberApproval = false;
  final bool rememberApproval;
  final McpToolResult? denialResult;
  bool get isApproved => denialResult == null;
}

final class ToolApprovalAuditRecord {
  ToolApprovalAuditRecord({
    required this.toolName,
    required this.actionKind,
    required this.domain,
    required this.mode,
    required this.outcome,
    required this.decisionSource,
    required Map<String, dynamic> arguments,
    required this.hasUntrustedInfluence,
    this.rationale,
    this.riskLevel,
  }) : arguments = ToolApprovalRequest._freezeMap(arguments);
  final String toolName;
  final String actionKind;
  final ToolApprovalAutoReviewDomain domain;
  final ToolApprovalMode mode;
  final String outcome;
  final String decisionSource;
  final Map<String, dynamic> arguments;
  final bool hasUntrustedInfluence;
  final String? rationale;
  final String? riskLevel;
}

abstract interface class ManualToolApprovalPort {
  Future<ManualToolApprovalDecision> requestApproval(
    ChatTurnOwner owner,
    ManualToolApprovalRequest request,
  );
}

abstract interface class ToolApprovalAutoReviewPort {
  Future<ToolApprovalAutoReviewDecision?> review(
    ChatTurnOwner owner,
    ToolApprovalAutoReviewRequest request, {
    required ToolApprovalAutoReviewDomain domain,
  });
}

abstract interface class ToolApprovalAuditPort {
  Future<void> record(ChatTurnOwner owner, ToolApprovalAuditRecord record);
}

abstract interface class ToolApprovalOwnerPort {
  bool isCurrent(ChatTurnOwner owner);
}

final class ToolApprovalOutcome {
  const ToolApprovalOutcome.approved({
    required this.gateDecision,
    this.rememberApproval = false,
  }) : denialResult = null,
       reusedCachedDenial = false;
  const ToolApprovalOutcome.denied({
    required this.denialResult,
    this.gateDecision,
    this.reusedCachedDenial = false,
  }) : rememberApproval = false;
  final ToolApprovalGateDecision? gateDecision;
  final McpToolResult? denialResult;
  final bool rememberApproval;
  final bool reusedCachedDenial;
  bool get isApproved => denialResult == null;
  bool get reusedCachedApproval =>
      gateDecision == ToolApprovalGateDecision.cachedApproval;
}

final class ToolApprovalPreflight {
  ToolApprovalPreflight._(
    this.request,
    this._coordinator,
    this._hasCachedApproval,
    this.outcome,
  );

  final ToolApprovalRequest request;
  final TurnToolApprovalCoordinator _coordinator;
  final bool _hasCachedApproval;
  final ToolApprovalOutcome? outcome;
  bool _consumed = false;
}

final class TurnToolApprovalCoordinator {
  TurnToolApprovalCoordinator({
    required ManualToolApprovalPort manualApprovalPort,
    required ToolApprovalAutoReviewPort autoReviewPort,
    required ToolApprovalAuditPort auditPort,
    required ToolApprovalOwnerPort ownerPort,
  }) : _manualApprovalPort = manualApprovalPort,
       _autoReviewPort = autoReviewPort,
       _auditPort = auditPort,
       _ownerPort = ownerPort;
  static const _expiredRationale = 'The approval turn expired before execution';
  final ManualToolApprovalPort _manualApprovalPort;
  final ToolApprovalAutoReviewPort _autoReviewPort;
  final ToolApprovalAuditPort _auditPort;
  final ToolApprovalOwnerPort _ownerPort;
  final Map<ChatTurnOwner, Map<String, _CachedApprovalDecision>> _cache = {};
  final Set<ChatTurnOwner> _retired = {};
  Future<ToolApprovalOutcome> resolve(ToolApprovalRequest request) async {
    final preflight = await preflightCachedDenial(request);
    return preflight.outcome ?? resolveAfterPreflight(preflight);
  }

  Future<ToolApprovalPreflight> preflightCachedDenial(
    ToolApprovalRequest request,
  ) async {
    if (!_ownerIsCurrent(request.owner)) {
      await _recordAuditBestEffort(
        request,
        arguments: request.arguments,
        outcome: 'denied',
        decisionSource: 'owner_expired',
        rationale: _expiredRationale,
      );
      return ToolApprovalPreflight._(
        request,
        this,
        false,
        _expiredOutcome(request.toolName),
      );
    }
    final cacheKey = _cacheKey(request);
    final cached = cacheKey == null ? null : _cache[request.owner]?[cacheKey];
    if (cached?.denialResult case final denial?) {
      return ToolApprovalPreflight._(
        request,
        this,
        false,
        ToolApprovalOutcome.denied(
          denialResult: denial,
          reusedCachedDenial: true,
        ),
      );
    }
    final approved = cached?.isApproved ?? false;
    return ToolApprovalPreflight._(request, this, approved, null);
  }

  Future<ToolApprovalOutcome> resolveAfterPreflight(
    ToolApprovalPreflight preflight, {
    String? targetDisplayName,
  }) async {
    if (!identical(preflight._coordinator, this) ||
        preflight.outcome != null ||
        preflight._consumed) {
      throw StateError('Invalid or already consumed approval preflight');
    }
    preflight._consumed = true;
    final request = preflight.request;
    final hasCachedApproval = preflight._hasCachedApproval;
    final auditArguments = hasCachedApproval
        ? request.cacheArguments!
        : request.arguments;
    final gate = await ToolApprovalAutoReviewService.resolveGate(
      toolName: request.toolName,
      hasCachedApproval: hasCachedApproval,
      mode: request.mode,
      fullAccessEligible: request.fullAccessEligible,
      review: () => _runAutoReview(request),
      recordAudit:
          ({required outcome, required decisionSource, rationale, riskLevel}) =>
              _recordAuditBestEffort(
                request,
                arguments: auditArguments,
                outcome: outcome,
                decisionSource: decisionSource,
                rationale: rationale,
                riskLevel: riskLevel,
              ),
      ownerIsCurrent: () => _ownerIsCurrent(request.owner),
      deniedEscalates: domainEscalatesDeniedActionToManual(
        request.reviewDomain,
      ),
      hasUntrustedInfluence: request.hasUntrustedInfluence,
    );
    if (!_ownerIsCurrent(request.owner)) {
      return _expiredOutcome(request.toolName);
    }
    if (gate.isDenied) {
      final denial = autoReviewDeniedResult(
        toolName: request.toolName,
        rationale: gate.deniedRationale ?? 'No rationale was provided.',
      );
      _rememberDenial(request, denial);
      return ToolApprovalOutcome.denied(
        denialResult: denial,
        gateDecision: gate,
      );
    }
    if (gate.runsDirectly) {
      return ToolApprovalOutcome.approved(gateDecision: gate);
    }
    final manualDecision = await _manualApprovalPort.requestApproval(
      request.owner,
      ManualToolApprovalRequest(
        toolCallId: request.toolCallId,
        toolName: request.toolName,
        actionKind: request.actionKind,
        arguments: request.arguments,
        warningTitle: escalatedWarningTitle(gate, request.warningTitle),
        warningMessage: escalatedWarningMessage(gate, request.warningMessage),
        preview: request.preview,
        targetDisplayName: targetDisplayName,
      ),
    );
    if (!_ownerIsCurrent(request.owner)) {
      return _expiredOutcome(request.toolName);
    }
    if (manualDecision.denialResult case final denial?) {
      _rememberDenial(request, denial);
      return ToolApprovalOutcome.denied(
        denialResult: denial,
        gateDecision: gate,
      );
    }
    return ToolApprovalOutcome.approved(
      gateDecision: gate,
      rememberApproval: manualDecision.rememberApproval,
    );
  }

  McpToolResult? expiredResult(ToolApprovalRequest request) =>
      _ownerIsCurrent(request.owner)
      ? null
      : _expiredOutcome(request.toolName).denialResult;
  McpToolResult rememberApprovalResult(
    ToolApprovalRequest request,
    McpToolResult result,
  ) {
    final cacheKey = _cacheKey(request);
    if (cacheKey != null && _ownerIsCurrent(request.owner)) {
      _entriesFor(request.owner)[cacheKey] =
          const _CachedApprovalDecision.approved();
    }
    return result;
  }

  McpToolResult rememberDenial(
    ToolApprovalRequest request,
    McpToolResult result,
  ) {
    if (_ownerIsCurrent(request.owner)) _rememberDenial(request, result);
    return result;
  }

  bool clearOwner(ChatTurnOwner owner) {
    _retired.add(owner);
    return _cache.remove(owner) != null;
  }

  void clearAll() {
    _retired.addAll(_cache.keys);
    _cache.clear();
  }

  ToolApprovalAutoReviewRequest buildAutoReviewRequest(
    ToolApprovalRequest request,
  ) => ToolApprovalAutoReviewRequest(
    actionKind: request.actionKind,
    toolName: request.toolName,
    arguments: request.arguments,
    path: request.path,
    workingDirectory: request.workingDirectory,
    reason: request.reason,
    warningTitle: request.warningTitle,
    warningMessage: request.warningMessage,
    preview: request.preview,
    conversationTail: ToolApprovalAutoReviewService.buildConversationTail(
      request.conversationMessages,
    ),
    hasUntrustedInfluence: request.hasUntrustedInfluence,
  );

  bool domainEscalatesDeniedActionToManual(
    ToolApprovalAutoReviewDomain domain,
  ) => domain == ToolApprovalAutoReviewDomain.coding;
  String? escalatedWarningTitle(
    ToolApprovalGateDecision gate,
    String? fallback,
  ) => gate.escalatedFromAutoReviewDenial
      ? 'Auto-review flagged this action'
      : fallback;
  String? escalatedWarningMessage(
    ToolApprovalGateDecision gate,
    String? fallback,
  ) {
    final rationale = gate.autoReviewEscalationRationale;
    if (rationale == null) return fallback;
    return fallback == null || fallback.isEmpty
        ? rationale
        : '$rationale\n\n$fallback';
  }

  McpToolResult autoReviewDeniedResult({
    required String toolName,
    required String rationale,
  }) => McpToolResult(
    toolName: toolName,
    result: 'Auto-review denied this action. Rationale: $rationale',
    isSuccess: false,
    errorMessage: 'Auto-review denied: $rationale',
  );

  Future<ToolApprovalAutoReviewDecision?> _runAutoReview(
    ToolApprovalRequest request,
  ) async {
    try {
      return await _autoReviewPort.review(
        request.owner,
        buildAutoReviewRequest(request),
        domain: request.reviewDomain,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordAuditBestEffort(
    ToolApprovalRequest request, {
    required Map<String, dynamic> arguments,
    required String outcome,
    required String decisionSource,
    String? rationale,
    String? riskLevel,
  }) async {
    try {
      await _auditPort.record(
        request.owner,
        ToolApprovalAuditRecord(
          toolName: request.toolName,
          actionKind: request.actionKind,
          domain: request.reviewDomain,
          mode: request.mode,
          outcome: outcome,
          decisionSource: decisionSource,
          rationale: rationale,
          riskLevel: riskLevel,
          arguments: arguments,
          hasUntrustedInfluence: request.hasUntrustedInfluence,
        ),
      );
    } catch (_) {}
  }

  bool _ownerIsCurrent(ChatTurnOwner owner) =>
      !_retired.contains(owner) && _ownerPort.isCurrent(owner);
  ToolApprovalOutcome _expiredOutcome(String toolName) =>
      ToolApprovalOutcome.denied(
        denialResult: McpToolResult(
          toolName: toolName,
          result: '',
          isSuccess: false,
          errorMessage: _expiredRationale,
        ),
      );

  void _rememberDenial(ToolApprovalRequest request, McpToolResult result) {
    if (_cacheKey(request) case final cacheKey?) {
      _entriesFor(request.owner)[cacheKey] = _CachedApprovalDecision.denied(
        result,
      );
    }
  }

  Map<String, _CachedApprovalDecision> _entriesFor(ChatTurnOwner owner) =>
      _cache.putIfAbsent(owner, () => {});
  String? _cacheKey(ToolApprovalRequest request) {
    final arguments = request.cacheArguments;
    if (arguments == null) return null;
    return jsonEncode({
      'tool': request.toolName,
      'arguments': _normalizeValue(arguments),
      'state': ?request.cacheStateFingerprint,
    });
  }

  Object? _normalizeValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, dynamic>{
        for (final entry in entries)
          if (entry.key.toString() != 'reason')
            entry.key.toString(): _normalizeValue(entry.value),
      };
    }
    if (value is List) return value.map(_normalizeValue).toList();
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    return value.toString();
  }
}

final class _CachedApprovalDecision {
  const _CachedApprovalDecision.approved() : denialResult = null;
  const _CachedApprovalDecision.denied(this.denialResult);
  final McpToolResult? denialResult;
  bool get isApproved => denialResult == null;
}
