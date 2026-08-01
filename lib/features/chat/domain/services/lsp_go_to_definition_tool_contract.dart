import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/chat_turn_owner.dart';
import 'immutable_json_snapshot.dart';

const String canonicalLspGoToDefinitionToolName = 'lsp_go_to_definition';

/// Exact identity for one immutable LSP definition lookup.
final class LspDefinitionOperationIdentity {
  LspDefinitionOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String requestDigest,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = _canonicalToolName(toolName),
       requestDigest = _requiredValue(requestDigest, 'requestDigest');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String requestDigest;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LspDefinitionOperationIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.requestDigest == requestDigest;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, requestDigest);
}

/// Immutable arguments captured for one owner-scoped definition lookup.
final class LspGoToDefinitionToolInput {
  factory LspGoToDefinitionToolInput({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required String? ownerProjectRoot,
    required Map<String, dynamic> arguments,
  }) {
    final frozenArguments = ImmutableJsonSnapshot.freezeMap(arguments);
    final normalizedProjectRoot = ownerProjectRoot?.trim();
    final canonicalToolName = _canonicalToolName(toolName);
    return LspGoToDefinitionToolInput._(
      identity: LspDefinitionOperationIdentity(
        owner: owner,
        toolCallId: toolCallId,
        toolName: canonicalToolName,
        requestDigest: _requestDigest(
          ownerProjectRoot: normalizedProjectRoot,
          arguments: frozenArguments,
        ),
      ),
      ownerProjectRoot: normalizedProjectRoot,
      arguments: frozenArguments,
    );
  }

  const LspGoToDefinitionToolInput._({
    required this.identity,
    required this.ownerProjectRoot,
    required this.arguments,
  });

  final LspDefinitionOperationIdentity identity;
  final String? ownerProjectRoot;
  final Map<String, dynamic> arguments;

  ChatTurnOwner get owner => identity.owner;
  String get toolCallId => identity.toolCallId;
  String get toolName => identity.toolName;
}

/// Fully resolved request passed to the session-aware LSP adapter.
final class LspDefinitionLookupRequest {
  LspDefinitionLookupRequest({
    required this.identity,
    required String projectRoot,
    required String path,
    required this.line,
    required this.character,
  }) : projectRoot = _requiredValue(projectRoot, 'projectRoot'),
       path = _requiredValue(path, 'path') {
    if (line < 0) {
      throw ArgumentError.value(line, 'line', 'line must not be negative.');
    }
    if (character < 0) {
      throw ArgumentError.value(
        character,
        'character',
        'character must not be negative.',
      );
    }
  }

  final LspDefinitionOperationIdentity identity;
  final String projectRoot;
  final String path;
  final int line;
  final int character;
}

enum LspDefinitionOwnerAcknowledgementDisposition { current, ownerExpired }

/// Exact acknowledgement from the owner lifecycle adapter.
final class LspDefinitionOwnerAcknowledgement {
  const LspDefinitionOwnerAcknowledgement.current({required this.identity})
    : disposition = LspDefinitionOwnerAcknowledgementDisposition.current;

  const LspDefinitionOwnerAcknowledgement.ownerExpired({required this.identity})
    : disposition = LspDefinitionOwnerAcknowledgementDisposition.ownerExpired;

  final LspDefinitionOperationIdentity identity;
  final LspDefinitionOwnerAcknowledgementDisposition disposition;
}

/// Persistent-session effect observed by the LSP adapter.
enum LspDefinitionSessionEffect {
  /// The adapter certifies that no process or session was started.
  none,

  /// The request reused a session that existed before this operation.
  reused,

  /// This operation started a session that remains active.
  started,

  /// A session started by this operation was stopped before returning.
  compensated,

  /// The adapter cannot prove whether a persistent session was started.
  uncertain,
}

enum LspDefinitionLookupResultKind {
  completed,
  failed,
  ownerExpired,
  effectUncertain,
}

/// One definition range returned by an LSP server.
final class LspDefinitionLocation {
  const LspDefinitionLocation({
    required this.uri,
    required this.startLine,
    required this.startCharacter,
    this.endLine,
    this.endCharacter,
  });

  final String uri;
  final int startLine;
  final int startCharacter;
  final int? endLine;
  final int? endCharacter;
}

/// Exact completion from the session-aware LSP adapter.
final class LspDefinitionLookupResult {
  LspDefinitionLookupResult.completed({
    required this.identity,
    required List<LspDefinitionLocation>? definitions,
    required this.sessionEffect,
  }) : kind = LspDefinitionLookupResultKind.completed,
       definitions = definitions == null
           ? null
           : List<LspDefinitionLocation>.unmodifiable(definitions),
       errorMessage = null;

  LspDefinitionLookupResult.failed({
    required this.identity,
    required Object error,
    required this.sessionEffect,
  }) : kind = LspDefinitionLookupResultKind.failed,
       definitions = null,
       errorMessage = error.toString();

  const LspDefinitionLookupResult.ownerExpired({
    required this.identity,
    required this.sessionEffect,
  }) : kind = LspDefinitionLookupResultKind.ownerExpired,
       definitions = null,
       errorMessage = null;

  const LspDefinitionLookupResult.effectUncertain({required this.identity})
    : kind = LspDefinitionLookupResultKind.effectUncertain,
      definitions = null,
      errorMessage = null,
      sessionEffect = LspDefinitionSessionEffect.uncertain;

  final LspDefinitionOperationIdentity identity;
  final LspDefinitionLookupResultKind kind;
  final List<LspDefinitionLocation>? definitions;
  final String? errorMessage;
  final LspDefinitionSessionEffect sessionEffect;
}

abstract interface class LspDefinitionLifecyclePort {
  LspDefinitionOwnerAcknowledgement acknowledgeOwner(
    LspDefinitionOperationIdentity identity,
  );
}

abstract interface class LspDefinitionPort {
  Future<LspDefinitionLookupResult> goToDefinition(
    LspDefinitionLookupRequest request,
  );
}

String _requestDigest({
  required String? ownerProjectRoot,
  required Map<String, dynamic> arguments,
}) {
  return sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'ownerProjectRoot': ownerProjectRoot,
            'arguments': arguments,
          }),
        ),
      )
      .toString();
}

String _requiredValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return normalized;
}

String _canonicalToolName(String value) {
  if (value != canonicalLspGoToDefinitionToolName) {
    throw ArgumentError.value(
      value,
      'toolName',
      'The canonical lsp_go_to_definition tool name is required.',
    );
  }
  return value;
}
