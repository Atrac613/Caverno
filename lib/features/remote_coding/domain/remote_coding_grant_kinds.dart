import '../../chat/domain/services/pending_approval_summary.dart';

/// The interactions a desktop can grant a paired device over its **own** turns.
///
/// SEC4.5g scopes an interaction to the paired device that started it, and a
/// turn begun at the Mac belongs to no device, so none of these reach a phone
/// unless the desktop owner grants them (SA-26). The grant is per kind because
/// the kinds are not interchangeable: answering a question the Mac asked is
/// not the same act as approving a shell command it wants to run, and a single
/// "trust this phone" switch would make them the same act.
///
/// A device's authority over turns it started itself is not configured here.
/// That is not a widening — it is what pairing already means, since a paired
/// device can send a message that runs on the desktop with the desktop's whole
/// tool catalogue.
abstract final class RemoteCodingGrantKinds {
  /// An `ask_user_question` raised by the desktop's own turn.
  ///
  /// Not an approval, so it is not in [PendingApprovalKinds]; it is granted
  /// separately because it authorizes nothing — it answers.
  static const String question = 'askUserQuestion';

  static const List<String> all = <String>[
    ...PendingApprovalKinds.all,
    question,
  ];

  /// Kinds whose approval lets the desktop change the machine or reach the
  /// network with credentials.
  ///
  /// Not enforced here — the grant is per kind and the desktop owner decides.
  /// Surfaces use it to order and to warn, so that "grant everything" is a
  /// deliberate act rather than the first item on a flat list.
  static const Set<String> consequential = <String>{
    PendingApprovalKinds.localCommand,
    PendingApprovalKinds.gitCommand,
    PendingApprovalKinds.sshCommand,
    PendingApprovalKinds.sshConnect,
    PendingApprovalKinds.file,
    PendingApprovalKinds.computerUse,
    PendingApprovalKinds.browserAction,
  };

  /// A human-readable name for [kind].
  static String label(String kind) => switch (kind) {
    PendingApprovalKinds.file => 'File writes',
    PendingApprovalKinds.localCommand => 'Shell commands',
    PendingApprovalKinds.gitCommand => 'Git commands',
    PendingApprovalKinds.sshCommand => 'SSH commands',
    PendingApprovalKinds.sshConnect => 'SSH connections',
    PendingApprovalKinds.browserAction => 'Browser actions',
    PendingApprovalKinds.computerUse => 'Computer use',
    PendingApprovalKinds.bleConnect => 'Bluetooth connections',
    PendingApprovalKinds.serialOpen => 'Serial ports',
    PendingApprovalKinds.participantTool => 'Participant tools',
    PendingApprovalKinds.assumptionConfirmation => 'Assumption checks',
    question => 'Questions',
    _ => kind,
  };
}
