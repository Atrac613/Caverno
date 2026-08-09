import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/background_process_follow_up_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers typed running state when scheduling a follow-up', () {
    final followUp = BackgroundProcessFollowUpPolicy.followUpToolCall([
      ToolResultInfo(
        id: 'status-1',
        name: 'process_status',
        arguments: const {'job_id': 'job-1'},
        result: jsonEncode({
          'ok': true,
          'job_id': 'job-1',
          'status': 'exited',
          'exit_code': 0,
        }),
        outcome: const ToolOutcome(processState: ToolProcessState.running),
      ),
    ], waitMs: 7000);

    expect(followUp?.name, 'process_wait');
    expect(followUp?.arguments, {'job_id': 'job-1', 'wait_ms': 7000});
  });

  test('does not follow up a typed terminal process', () {
    final followUp = BackgroundProcessFollowUpPolicy.followUpToolCall([
      ToolResultInfo(
        id: 'wait-1',
        name: 'process_wait',
        arguments: const {'job_id': 'job-1'},
        result: jsonEncode({
          'ok': true,
          'job_id': 'job-1',
          'status': 'running',
        }),
        outcome: const ToolOutcome(
          processState: ToolProcessState.exited,
          exitCode: 0,
        ),
      ),
    ], waitMs: 7000);

    expect(followUp, isNull);
  });
}
