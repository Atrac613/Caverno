import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_replay_tool_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('denies only the built-in browser and desktop families', () {
    for (final name in ['browser_open', 'browser_snapshot', 'computer_click']) {
      expect(PersonalEvalReplayToolPolicy.isDenied(name), isTrue, reason: name);
    }
    for (final name in [
      'read_file',
      'local_execute_command',
      'search_web',
      'fetch_url',
      'mdns_browse',
      'remote_browser_open',
    ]) {
      expect(
        PersonalEvalReplayToolPolicy.isDenied(name),
        isFalse,
        reason: name,
      );
    }
  });

  test('declares the denial as a policy refusal', () {
    final result = PersonalEvalReplayToolPolicy.deniedResult(
      ToolCallInfo(id: 't1', name: 'browser_open', arguments: const {}),
    );
    final payload = jsonDecode(result.result) as Map<String, Object?>;

    expect(result.isSuccess, isFalse);
    expect(payload['tool'], 'browser_open');
    expect(ToolResultOrigin.fromPayload(payload), ToolResultOrigin.refusal);
  });
}
