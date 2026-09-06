import 'package:caverno/features/chat/domain/services/pending_approval_summary.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RemoteCodingAuditEntry entry({
    String title = 'rm -rf build',
    String origin = 'local',
    RemoteCodingAuditOutcome outcome = RemoteCodingAuditOutcome.resolved,
    String? refusedReason,
  }) => RemoteCodingAuditEntry(
    at: DateTime.utc(2026, 9, 6, 12, 30),
    deviceId: 'device-1',
    deviceName: 'Phone',
    kind: PendingApprovalKinds.localCommand,
    origin: origin,
    outcome: outcome,
    approved: true,
    title: title,
    subtitle: '/repo',
    warning: 'This deletes files.',
    refusedReason: refusedReason,
    conversationId: 'thread-1',
  );

  test('round-trips through storage', () {
    final parsed = RemoteCodingAuditEntry.fromJson(entry().toJson());

    expect(parsed.at, DateTime.utc(2026, 9, 6, 12, 30));
    expect(parsed.deviceName, 'Phone');
    expect(parsed.kind, PendingApprovalKinds.localCommand);
    expect(parsed.title, 'rm -rf build');
    expect(parsed.warning, 'This deletes files.');
    expect(parsed.outcome, RemoteCodingAuditOutcome.resolved);
    expect(parsed.isDesktopOrigin, isTrue);
  });

  test('a decision on a turn the device started is not desktop origin', () {
    expect(entry(origin: 'remote').isDesktopOrigin, isFalse);
  });

  test('a refusal keeps why it was refused', () {
    final parsed = RemoteCodingAuditEntry.fromJson(
      entry(
        outcome: RemoteCodingAuditOutcome.refused,
        refusedReason: 'not_permitted',
      ).toJson(),
    );

    expect(parsed.outcome, RemoteCodingAuditOutcome.refused);
    expect(parsed.refusedReason, 'not_permitted');
  });

  test('a long field is cut, and says it was cut', () {
    // A file approval's preview can be a whole diff, and this log lives in
    // shared preferences beside the server's configuration.
    final long = 'x' * (RemoteCodingAuditEntry.maxFieldLength + 50);

    final parsed = RemoteCodingAuditEntry.fromJson(entry(title: long).toJson());

    expect(parsed.title.length, RemoteCodingAuditEntry.maxFieldLength + 1);
    expect(parsed.title.endsWith('…'), isTrue);
  });

  test('an unreadable entry decodes to something rather than throwing', () {
    // Settings written by a future build must not make the desktop's own
    // record unreadable; a blank entry is recoverable, an exception on load
    // is not.
    final parsed = RemoteCodingAuditEntry.fromJson(const {'at': 'not-a-date'});

    expect(parsed.at, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(parsed.title, isEmpty);
    expect(parsed.outcome, RemoteCodingAuditOutcome.resolved);
  });

  test('the newest entry is first, and the log stays bounded', () {
    var entries = <RemoteCodingAuditEntry>[];
    for (
      var index = 0;
      index < RemoteCodingAuditEntry.maxEntries + 10;
      index++
    ) {
      entries = appendRemoteCodingAuditEntry(
        entries,
        entry(title: 'cmd-$index'),
      );
    }

    expect(entries, hasLength(RemoteCodingAuditEntry.maxEntries));
    expect(
      entries.first.title,
      'cmd-${RemoteCodingAuditEntry.maxEntries + 9}',
      reason: 'newest first',
    );
    expect(
      entries.map((entry) => entry.title),
      isNot(contains('cmd-0')),
      reason: 'the oldest is dropped rather than the newest refused',
    );
  });
}
