import '../entities/tool_call_info.dart';

/// The one path a `git diff ... -- <path>` inspection was scoped to, or null.
///
/// Such a call is the diff counterpart of a ranged `read_file`: it asks for
/// the current change to a single file. The prompt budget keeps the newest
/// one intact for the same reason it keeps the newest range read. Session
/// 0372d7fb reviewed a 39 KB task patch listed file by file, and every
/// single-file diff reached the reviewer cut to about 5 KB by the shared
/// history budget, so the review ended incomplete.
String? singlePathDiffInspection(ToolResultInfo result) {
  if (result.name != 'git_execute_command' &&
      result.name != 'local_execute_command') {
    return null;
  }
  final command = result.arguments['command'];
  if (command is! String || RegExp(r'[|;&<>`$]').hasMatch(command)) {
    return null;
  }
  var words = command.trim().split(RegExp(r'\s+'));
  if (words.isNotEmpty && words.first == 'git') words = words.sublist(1);
  if (words.isEmpty || words.first != 'diff') return null;
  final separator = words.indexOf('--');
  if (separator < 0 || separator != words.length - 2) return null;
  final path = words.last;
  return path.isEmpty ? null : path;
}
