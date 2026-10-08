/// The prompt sent when a turn answered a browser request with prose after the
/// app recovered a `browser_snapshot` on its behalf.
///
/// A snapshot is not the action: the page was read, nothing was clicked or
/// typed. This says so, names the tool that still has to run, and offers the
/// honest alternative -- say it did not run -- so the turn is not pushed into
/// claiming an action it never took.
abstract final class SkippedBrowserActionRepairPrompt {
  static String forMissingTool(String missingToolName) => [
    'The latest user request still requires a browser action.',
    'The application only executed a recovered browser_snapshot so far.',
    'Do not claim the browser action is complete in prose.',
    'If the snapshot contains a safe target, call $missingToolName now using the latest snapshot ref or selector.',
    'If no safe target exists, answer briefly that $missingToolName remains unexecuted.',
  ].join('\n');
}
