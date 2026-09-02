// ChatNotifier decomposition collaborator: unexecuted-file-mutation-block-payload

import 'dart:convert';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

/// The tool result a blocked command reports back to the loop.
///
/// Kept apart from the guard so the wording — which the model reads and acts
/// on — can be reviewed on its own. `required_action` is the load-bearing part:
/// it names the tool that is missing rather than only stating the refusal.
final class UnexecutedFileMutationBlockPayload {
  const UnexecutedFileMutationBlockPayload();

  String encode({
    required String blockedTool,
    required String claimedResponse,
    String? blockedCommand,
  }) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'code': 'unexecuted_file_save',
      ...ToolResultOrigin.harness.marker,
      'error':
          'A command was blocked because the assistant claimed a local file '
          'would be changed, but no successful write_file, edit_file, or '
          'rollback_last_file_change result is available for that claimed '
          'mutation.',
      'missing_tool': 'edit_file',
      'blocked_tool': blockedTool,
      'claimedResponse': claimedResponse,
      'required_action':
          'Use write_file or edit_file to perform the claimed file mutation '
          'before running the command, or explain that the command remains '
          'blocked because the file change was not executed.',
      'blocked_command': ?blockedCommand,
    });
  }
}
