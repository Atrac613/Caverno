import 'dart:convert';

import '../../entities/tool_call_info.dart';

/// Tools whose result is a standing instruction the model keeps reading. See
/// `StickyToolResultPolicy`.
const Set<String> stickyToolNames = {'ask_user_question', 'load_skill'};

/// Whether [toolResult] is content from a sticky tool, rather than a call
/// that was rejected before it ran.
///
/// A rejected call (the argument type guard's `"executed": false` failure)
/// asked nothing and loaded nothing. In session b41b57fa a malformed
/// `ask_user_question` was treated as a newer answer: it superseded the
/// answered one, so the next two requests no longer carried the user's choice,
/// and the first malformed call rode along as history in three requests.
bool isStickyToolContent(ToolResultInfo toolResult) {
  if (!stickyToolNames.contains(toolResult.name)) return false;
  try {
    final decoded = jsonDecode(toolResult.result);
    return !(decoded is Map && decoded['executed'] == false);
  } on FormatException {
    return true;
  }
}
