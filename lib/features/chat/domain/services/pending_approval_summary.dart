import '../../presentation/providers/chat_state.dart';

/// A pending tool approval flattened into one displayable shape.
///
/// `ChatState` keeps eleven independent `Pending*` fields, and more arrive over
/// time. Every surface that has to render "what is this turn blocked on" —
/// the Apple Watch companion, an actionable notification, and anything added
/// later — needs the same flattening, so it lives here once instead of being
/// re-derived per surface with slightly different coverage. (Remote Coding's
/// own `_pendingRemoteApproval` predates this and covers only three kinds; it
/// is left alone because widening it would change what paired devices see.)
class PendingApprovalSummary {
  const PendingApprovalSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.isSimpleDecision,
    required this.conversationId,
    this.origin = ChatInteractionOrigin.local,
    this.remoteDeviceId,
  });

  final String id;

  /// Free-form rather than an enum so a surface built against an older build
  /// degrades to a generic presentation instead of failing to decode.
  final String kind;
  final String title;
  final String subtitle;
  final String detail;

  /// Whether a bare approve/deny is enough to resolve this request.
  ///
  /// False for approvals that need structured input (SSH credentials,
  /// computer-use smoke arming); those must be completed in the full UI.
  final bool isSimpleDecision;
  final String conversationId;

  /// Where the turn that raised this interaction came from. Only four pending
  /// types carry it; the rest have no remote producer and are structurally
  /// local.
  final ChatInteractionOrigin origin;

  /// The paired Remote Coding device that owns this interaction, when one does.
  final String? remoteDeviceId;

  /// Whether a surface on *this* device must leave this interaction alone.
  ///
  /// Mirrors the shape of `RemoteCodingServerNotifier._canResolveInteraction`,
  /// which is the reference gate for SEC4.5g: it checks `origin` first and
  /// treats a remote interaction with a missing owner as **not** resolvable.
  /// Reading only `remoteDeviceId` would invert that — inferring "remote" from
  /// the presence of an id means a remote-origin interaction that somehow lost
  /// its owner becomes resolvable here. `ChatNotifier` nulls the id for
  /// local-origin turns, so today the single remote producer always supplies
  /// an authenticated one and the two tests agree; checking origin is what
  /// keeps them agreeing after the next refactor.
  bool get isOwnedByRemoteDevice =>
      origin == ChatInteractionOrigin.remote ||
      (remoteDeviceId?.trim() ?? '').isNotEmpty;
}

/// Kind identifiers emitted by [describePendingApproval].
abstract final class PendingApprovalKinds {
  static const String file = 'file';
  static const String localCommand = 'localCommand';
  static const String gitCommand = 'gitCommand';
  static const String sshCommand = 'sshCommand';
  static const String sshConnect = 'sshConnect';
  static const String bleConnect = 'bleConnect';
  static const String serialOpen = 'serialOpen';
  static const String browserAction = 'browserAction';
  static const String computerUse = 'computerUse';
  static const String participantTool = 'participantTool';
  static const String assumptionConfirmation = 'assumptionConfirmation';
}

/// Describes [request] for a compact surface.
///
/// `PendingToolApproval` is sealed, so this switch is exhaustive and a new
/// approval kind becomes a compile error here rather than an approval that
/// silently never reaches the watch or the notification. Version skew is a
/// wire-format concern, handled by keeping [PendingApprovalSummary.kind] a
/// string that older readers can fall back on.
PendingApprovalSummary describePendingApproval(
  PendingToolApproval<dynamic> request,
) {
  final conversationId = request.owner.conversationId;
  return switch (request) {
    PendingFileOperation() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.file,
      title: request.operation,
      subtitle: request.path,
      detail: request.reason ?? request.preview,
      isSimpleDecision: true,
      conversationId: conversationId,
      origin: request.origin,
      remoteDeviceId: request.remoteDeviceId,
    ),
    PendingLocalCommand() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.localCommand,
      title: request.command,
      subtitle: request.workingDirectory,
      // The warning is what makes a shell approval a decision rather than a
      // formality, so it outranks the model's stated reason.
      detail: request.warningMessage ?? request.reason ?? '',
      isSimpleDecision: true,
      conversationId: conversationId,
      origin: request.origin,
      remoteDeviceId: request.remoteDeviceId,
    ),
    PendingGitCommand() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.gitCommand,
      title: request.command,
      subtitle: request.workingDirectory,
      detail: request.reason ?? '',
      isSimpleDecision: true,
      conversationId: conversationId,
      origin: request.origin,
      remoteDeviceId: request.remoteDeviceId,
    ),
    PendingSshCommand() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.sshCommand,
      title: request.command,
      subtitle: '${request.username}@${request.host}',
      detail: request.reason ?? '',
      isSimpleDecision: true,
      conversationId: conversationId,
    ),
    PendingBrowserAction() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.browserAction,
      title: request.title,
      subtitle: request.targetSummary ?? request.toolName,
      detail: request.warningMessage.isNotEmpty
          ? request.warningMessage
          : request.summary,
      isSimpleDecision: true,
      conversationId: conversationId,
    ),
    PendingBleConnect() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.bleConnect,
      title: 'Connect to Bluetooth device',
      subtitle: request.deviceName ?? request.deviceId,
      detail: request.deviceId,
      isSimpleDecision: true,
      conversationId: conversationId,
    ),
    PendingSerialOpen() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.serialOpen,
      title: 'Open serial port',
      subtitle: request.portName,
      detail: '${request.baudRate} baud',
      isSimpleDecision: true,
      conversationId: conversationId,
    ),
    PendingParticipantToolApproval() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.participantTool,
      title: request.toolName,
      subtitle: '${request.participantName} (${request.participantRoleLabel})',
      detail: request.reason ?? '',
      isSimpleDecision: true,
      conversationId: conversationId,
    ),
    PendingComputerUseAction() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.computerUse,
      title: request.title,
      subtitle: request.targetSummary ?? request.toolName,
      detail: request.warningMessage.isNotEmpty
          ? request.warningMessage
          : request.summary,
      // Smoke arming is a second, deliberate gesture no compact surface can
      // represent honestly.
      isSimpleDecision: false,
      conversationId: conversationId,
    ),
    PendingAssumptionConfirmation() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.assumptionConfirmation,
      title: 'Confirm assumption',
      subtitle: request.itemText,
      // The model's own question when it wrote one, because that is what the
      // user is being asked to judge; otherwise say what is blocked, which is
      // the only other thing that makes the interruption make sense.
      detail: request.clarificationQuestion ?? 'Blocked: ${request.toolName}',
      // Approve or decline resolves it. Declining is not a deferral: the
      // assumption stays unconfirmed and the mutation stays refused.
      isSimpleDecision: true,
      conversationId: conversationId,
      origin: request.origin,
      remoteDeviceId: request.remoteDeviceId,
    ),
    PendingSshConnect() => PendingApprovalSummary(
      id: request.id,
      kind: PendingApprovalKinds.sshConnect,
      title: 'SSH connection',
      subtitle: '${request.username}@${request.host}',
      detail: 'Credentials are required.',
      // Resolving needs an SshConnectApproval carrying credential material.
      isSimpleDecision: false,
      conversationId: conversationId,
    ),
  };
}
