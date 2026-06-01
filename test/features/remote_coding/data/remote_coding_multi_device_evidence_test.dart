import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_multi_device_evidence.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_security.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'multi-device evidence patches household checklist without token hashes',
    () {
      final settings = RemoteCodingServerSettings(
        enabled: true,
        port: 8767,
        pairedDevices: [
          RemoteCodingPairedDevice(
            id: 'device-1',
            name: 'Phone',
            tokenHash: RemoteCodingSecurity.hashToken('mobile-token-1'),
            createdAt: DateTime(2026, 5, 26, 12),
            lastSeenAt: DateTime(2026, 5, 26, 12, 30),
          ),
          RemoteCodingPairedDevice(
            id: 'device-2',
            name: 'Tablet',
            tokenHash: RemoteCodingSecurity.hashToken('mobile-token-2'),
            createdAt: DateTime(2026, 5, 26, 13),
            lastSeenAt: DateTime(2026, 5, 26, 13, 30),
          ),
        ],
      );

      final evidence = RemoteCodingMultiDeviceEvidence.build(
        settings: settings,
        activeConnectionCount: 2,
        revokingOneDeviceKeepsOtherDeviceUsable: true,
        approvalsReachOnlyRemoteOriginTurns: true,
        generatedAt: DateTime(2026, 5, 26, 14),
      );
      final encoded = jsonEncode(evidence);
      final patch = evidence['manualChecklistPatch'] as Map<String, dynamic>;
      final multiDevice = patch['multiDevice'] as Map<String, dynamic>;
      final review = evidence['review'] as Map<String, dynamic>;

      expect(evidence['schemaName'], 'remote_coding_p1_multi_device_evidence');
      expect(evidence['generatedAt'], '2026-05-26T14:00:00.000');
      expect(review['pairedDeviceCount'], 2);
      expect(review['activeConnectionCount'], 2);
      expect(multiDevice['twoDevicesCanPair'], isTrue);
      expect(multiDevice['activeSessionCountUpdates'], isTrue);
      expect(multiDevice['revokingOneDeviceKeepsOtherDeviceUsable'], isTrue);
      expect(multiDevice['approvalsReachOnlyRemoteOriginTurns'], isTrue);
      expect(encoded, isNot(contains('mobile-token-1')));
      expect(encoded, isNot(contains('mobile-token-2')));
      expect(
        encoded,
        isNot(contains(RemoteCodingSecurity.hashToken('mobile-token-1'))),
      );
      expect(
        encoded,
        isNot(contains(RemoteCodingSecurity.hashToken('mobile-token-2'))),
      );
    },
  );
}
