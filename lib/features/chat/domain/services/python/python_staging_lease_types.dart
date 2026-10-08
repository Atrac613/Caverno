part of 'python_staging_lease_registry.dart';

typedef PythonStagingCleanupPendingCallback =
    void Function(PythonStagingAttempt attempt);

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return normalized;
}

Map<String, dynamic> _freezeMetadata(Map<String, dynamic> value) {
  return ImmutableJsonSnapshot.freezeMap(value, argumentName: 'metadata');
}

final class PythonStagingAttempt {
  PythonStagingAttempt({
    required this.owner,
    required String toolCallId,
    required String toolName,
  }) : toolCallId = _requiredText(toolCallId, 'toolCallId'),
       toolName = _requiredText(toolName, 'toolName');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PythonStagingAttempt &&
          other.owner == owner &&
          other.toolCallId == toolCallId &&
          other.toolName == toolName;

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName);
}

/// Replacement-resistant identity written beside a fresh staging directory.
///
/// The filesystem adapter must resolve [canonicalPath] without symlinks and
/// validate [markerNonce] plus the optional device/inode pair before deletion.
final class PythonStagingDirectoryIdentity {
  PythonStagingDirectoryIdentity({
    required String canonicalPath,
    required String markerNonce,
    this.deviceId,
    this.inode,
  }) : canonicalPath = _canonicalPath(canonicalPath),
       markerNonce = _requiredText(markerNonce, 'markerNonce') {
    if ((deviceId == null) != (inode == null) ||
        (deviceId != null && deviceId! < 0) ||
        (inode != null && inode! < 0)) {
      throw ArgumentError(
        'deviceId and inode must be non-negative and supplied together.',
      );
    }
  }

  final String canonicalPath;
  final String markerNonce;
  final int? deviceId;
  final int? inode;

  static String _canonicalPath(String value) {
    final path = _requiredText(value, 'canonicalPath');
    final isPosix = path.startsWith('/');
    final isWindows = RegExp(r'^[A-Za-z]:\\').hasMatch(path);
    final segments = isPosix
        ? path.substring(1).split('/')
        : isWindows
        ? path.substring(3).split(r'\')
        : const <String>[];
    final invalidSegment = segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    );
    if ((!isPosix && !isWindows) ||
        segments.isEmpty ||
        invalidSegment ||
        (isWindows && path.contains('/'))) {
      throw ArgumentError.value(
        value,
        'canonicalPath',
        'The staging path must be absolute, canonical, and below a root.',
      );
    }
    return path;
  }

  String get claimKey => RegExp(r'^[A-Za-z]:\\').hasMatch(canonicalPath)
      ? canonicalPath.toLowerCase()
      : canonicalPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PythonStagingDirectoryIdentity &&
          other.canonicalPath == canonicalPath &&
          other.markerNonce == markerNonce &&
          other.deviceId == deviceId &&
          other.inode == inode;

  @override
  int get hashCode => Object.hash(canonicalPath, markerNonce, deviceId, inode);
}

final class PythonStagingLeaseToken {
  PythonStagingLeaseToken._();

  @override
  String toString() => 'PythonStagingLeaseToken(<opaque>)';
}

final class PythonStagingLease {
  PythonStagingLease._({
    required this.attempt,
    required this.token,
    required this.directoryIdentity,
    required Map<String, dynamic> metadata,
  }) : metadata = _freezeMetadata(metadata);

  final PythonStagingAttempt attempt;
  final PythonStagingLeaseToken token;
  final PythonStagingDirectoryIdentity directoryIdentity;
  final Map<String, dynamic> metadata;

  String get directoryPath => directoryIdentity.canonicalPath;
}

final class _CleanupClaimToken {
  _CleanupClaimToken();
}

/// Exclusive, one-shot permission to delete one exact staged directory.
final class PythonStagingCleanupClaim {
  PythonStagingCleanupClaim._(this.lease) : _token = _CleanupClaimToken();

  final PythonStagingLease lease;
  final _CleanupClaimToken _token;
}

enum PythonStagingReserveStatus { reserved, ownerCleared, attemptConflict }

final class PythonStagingReserveDisposition {
  const PythonStagingReserveDisposition._(this.status, this.token);

  final PythonStagingReserveStatus status;
  final PythonStagingLeaseToken? token;

  bool get isReserved => status == PythonStagingReserveStatus.reserved;
}

enum PythonStagingCommitStatus {
  committed,
  alreadyCommitted,
  ownerCleared,
  reservationReleased,
  duplicateStage,
  attemptMismatch,
  unknownToken,
  pathConflict,
  cleanupAlreadyClaimed,
  alreadySettled,
}

final class PythonStagingCommitDisposition {
  const PythonStagingCommitDisposition._({
    required this.status,
    this.activeLease,
    this.cleanupClaim,
  });

  final PythonStagingCommitStatus status;
  final PythonStagingLease? activeLease;
  final PythonStagingCleanupClaim? cleanupClaim;
}

enum PythonStagingCleanupClaimStatus {
  claimed,
  alreadyClaimed,
  noLease,
  alreadySettled,
  attemptMismatch,
  unknownToken,
}

final class PythonStagingCleanupClaimDisposition {
  const PythonStagingCleanupClaimDisposition._(this.status, this.claim);

  final PythonStagingCleanupClaimStatus status;
  final PythonStagingCleanupClaim? claim;
}

enum PythonStagingCleanupSettleStatus {
  settled,
  reopened,
  alreadySettled,
  staleClaim,
}

enum PythonStagingReservationReleaseStatus {
  cancelled,
  alreadyReleased,
  leaseActive,
  attemptMismatch,
  unknownToken,
}

final class PythonStagingClearDisposition {
  PythonStagingClearDisposition._({
    required Iterable<PythonStagingCleanupClaim> cleanupClaims,
    required this.retiredReservationCount,
  }) : cleanupClaims = List.unmodifiable(cleanupClaims);

  final List<PythonStagingCleanupClaim> cleanupClaims;
  final int retiredReservationCount;
}
