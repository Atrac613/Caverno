import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/security/data_source_classifier.dart';
import 'package:caverno/core/security/taint_policy.dart';
import 'package:caverno/core/security/tool_capability_classifier.dart';

void main() {
  const policy = TaintPolicy();
  const classifier = ToolCapabilityClassifier();

  TaintDecision assess(String tool, Set<TrustLevel> influences) =>
      policy.assess(
        capability: classifier.classify(tool),
        influencingTrustLevels: influences,
      );

  group('TaintPolicy', () {
    test('allows when no untrusted evidence influenced the call', () {
      expect(
        assess('local_execute_command', {
          TrustLevel.userTrusted,
          TrustLevel.projectTrusted,
        }),
        TaintDecision.allow,
      );
    });

    test('allows read-only actions even under untrusted influence', () {
      expect(
        assess('read_file', {TrustLevel.untrusted}),
        TaintDecision.allow,
      );
      expect(
        assess('list_directory', {TrustLevel.untrusted}),
        TaintDecision.allow,
      );
    });

    test('blocks a high-risk mutating action driven by untrusted content', () {
      // The network-fetch-then-execute / AMOS malware-vector shape.
      for (final tool in [
        'local_execute_command',
        'ssh_execute_command',
        'git_execute_command',
        'computer_left_click',
      ]) {
        expect(
          assess(tool, {TrustLevel.untrusted}),
          TaintDecision.block,
          reason: tool,
        );
      }
    });

    test('requires approval for tainted medium-risk mutation or network', () {
      expect(
        assess('write_file', {TrustLevel.untrusted}),
        TaintDecision.requireApproval,
      );
      expect(
        assess('http_get', {TrustLevel.untrusted}),
        TaintDecision.requireApproval,
      );
    });

    test('honors untrusted influence mixed with trusted evidence', () {
      expect(
        assess('write_file', {
          TrustLevel.userTrusted,
          TrustLevel.untrusted,
        }),
        TaintDecision.requireApproval,
      );
    });

    test('allows an untainted mutating action', () {
      expect(
        assess('write_file', {TrustLevel.projectTrusted}),
        TaintDecision.allow,
      );
    });
  });
}
